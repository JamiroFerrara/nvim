// The dashboard's client: fetch the sectioned payload, draw it, and send the
// clicks back to nvim. Everything shown comes from /api/data, so the views
// are defined once, in Lua (helpers/org/web/data.lua).

const state = {
  data: null,
  selection: 'all',
  view: 'board',
  query: '',
  selected: null, // {file, line, id}
  loading: false,
  count: 0, // digits typed before a motion
  pending: '', // a key waiting for its second (g, d, <Space>…)
  folded: new Set(), // entry keys folded away
  refile: null, // the entry `r` picked, waiting for a destination
  live: { tickets: new Set(), sessions: new Set(), activity: {} }, // runs in flight
  runStream: null, // the open event stream of the run the detail pane shows
};

const $ = (sel) => document.querySelector(sel);
const el = (tag, cls, text) => {
  const node = document.createElement(tag);
  if (cls) node.className = cls;
  if (text !== undefined && text !== null) node.textContent = text;
  return node;
};

function showToast(text) {
  let toast = $('#toast');
  if (!toast) {
    toast = el('div');
    toast.id = 'toast';
    document.body.append(toast);
  }
  toast.textContent = text;
  toast.classList.add('on');
  clearTimeout(showToast.t);
  showToast.t = setTimeout(() => toast.classList.remove('on'), 2200);
}

async function api(path, opts) {
  const res = await fetch(path, opts);
  if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
  return res.json();
}

function debounce(fn, ms) {
  let t;
  return (...args) => {
    clearTimeout(t);
    t = setTimeout(() => fn(...args), ms);
  };
}

async function load() {
  if (state.loading) return;
  state.loading = true;
  try {
    state.data = await api('/api/data?file=' + encodeURIComponent(state.selection));
    setLive(state.data.live);
    render();
    if (state.live.tickets.size || state.live.sessions.size) watchLive();
    $('#live').classList.add('on');
    setTimeout(() => $('#live').classList.remove('on'), 900);
  } catch (err) {
    console.error(err);
    showToast('Could not read the vault');
  } finally {
    state.loading = false;
  }
}

function matches(entry) {
  const q = state.query.trim().toLowerCase();
  if (!q) return true;
  const haystack = (entry.title + ' ' + (entry.project || '') + ' ' + (entry.tags || []).join(' ')).toLowerCase();
  // every word has to appear somewhere: "ing tree" finds the tree tickets
  return q.split(/\s+/).every((word) => {
    if (word.startsWith('#')) return (entry.tags || []).some((t) => t.toLowerCase().includes(word.slice(1)));
    return haystack.includes(word);
  });
}

function entryRow(entry) {
  const li = el('li', 'entry' + (entry.done ? ' done-entry' : ''));
  li.dataset.file = entry.file;
  li.dataset.line = entry.line;
  li.style.setProperty('--depth', entry.depth || 0);

  const chip = el('button', 'state ' + (entry.todo || ''), entry.todo || '—');
  chip.title = 'Change state';
  chip.addEventListener('click', (ev) => {
    ev.stopPropagation();
    openStateMenu(chip, entry);
  });
  li.append(chip);

  li.append(el('span', 'prio', entry.priority || ''));

  if (entry._children) {
    const canOpen = !state.folded.has(foldKey(entry));
    const fold = el('span', 'fold', canOpen ? '▾' : '▸');
    fold.title = '<Tab> folds the entries under this one';
    fold.addEventListener('click', (ev) => {
      ev.stopPropagation();
      cycleFold(entry);
    });
    li.append(fold);
  } else {
    li.append(el('span', 'fold empty'));
  }

  const title = el('span', 'title');
  if (runKey(entry)) title.append(el('span', 'live-dot', '●'));
  title.append(document.createTextNode(entry.title));
  if (entry.cookie) title.append(el('span', 'cookie', ' ' + entry.cookie));
  title.title = entry.rel + ':' + entry.line;
  title.addEventListener('click', () => selectEntry(entry));
  li.append(title);

  const base = (entry.rel.split('/').pop() || '').replace(/\.org$/, '').toLowerCase();
  const tags = el('span', 'tags');
  for (const tag of entry.tags || []) {
    const lower = tag.toLowerCase();
    if (lower === base || lower === (entry.project || '').toLowerCase()) continue;
    tags.append(el('span', '', tag));
  }
  li.append(tags);

  const meta = el('span', 'meta');
  const date = entry.deadline || entry.scheduled;
  if (date) {
    const label = entry.deadline ? '⏰' : '⏳';
    const cls = deadlineClass(entry.deadline);
    meta.append(el('span', cls, label + ' ' + date));
  }
  if (entry.done && entry.closed) {
    meta.append(el('span', '', '✓ ' + entry.closed));
  } else if (!entry.done && entry.changed) {
    meta.append(el('span', '', entry.changed));
  }
  li.append(meta);
  li.append(el('span', 'project', state.selection === 'all' ? entry.project || '' : ''));

  const key = runKey(entry);
  if (key) {
    li.classList.add('running');
    li.append(el('span', 'live-line', state.live.activity[key] || ''));
  }

  li._entry = entry;
  li.addEventListener('click', () => selectEntry(entry));
  return li;
}

function deadlineClass(deadline) {
  if (!deadline) return '';
  const m = deadline.match(/(\d{4})-(\d{2})-(\d{2})/);
  if (!m) return '';
  const then = new Date(+m[1], +m[2] - 1, +m[3]);
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const days = Math.round((then - today) / 86400000);
  if (days < 0) return 'late';
  if (days <= 2) return 'soon';
  return '';
}

function render() {
  renderSidebar();
  renderTabs();
  renderViews();
}

// The rail's two numbers: what a run is on (NEXT, TEST, WARN) and what is
// still waiting to be taken, each in its own color. A zero stays in place so
// the columns line up, dimmed so it reads as nothing.
function counts(btn, count) {
  const box = el('span', 'counts');
  for (const [key, title] of [
    ['flight', 'in flight'],
    ['pending', 'waiting to be taken'],
  ]) {
    const n = count[key] || 0;
    const chip = el('span', 'count ' + key + (n ? '' : ' zero'), String(n));
    chip.title = `${n} ${title}`;
    box.append(chip);
  }
  btn.append(box);
}

function renderSidebar() {
  const nav = $('#projects');
  nav.replaceChildren();
  const all = el('button', state.selection === 'all' ? 'active' : '');
  all.append(el('span', 'name', 'All projects'));
  const totals = state.data.totals;
  counts(all, totals);
  all.addEventListener('click', () => {
    state.selection = 'all';
    load();
  });
  nav.append(all);
  for (const project of state.data.projects) {
    const btn = el('button', state.selection === project.path ? 'active' : '');
    btn.title = '~/' + project.rel;
    btn.append(el('span', 'name', project.name));
    counts(btn, project);
    btn.addEventListener('click', () => {
      state.selection = project.path;
      load();
    });
    nav.append(btn);
  }
  const footer = $('#totals');
  footer.replaceChildren();
  footer.append(el('span', '', `${totals.open} open`));
  footer.append(el('span', '', `${totals.done} done`));
}

function viewCount(view) {
  let n = 0;
  for (const section of view.sections) n += section.items.length;
  return n;
}

function renderTabs() {
  const tabs = $('#tabs');
  tabs.replaceChildren();
  for (const view of state.data.views) {
    const btn = el('button', state.view === view.key ? 'active' : '');
    btn.append(el('span', '', view.icon + ' ' + view.title));
    btn.append(el('span', 'badge', String(viewCount(view))));
    btn.addEventListener('click', () => {
      state.view = view.key;
      renderTabs();
      renderViews();
    });
    tabs.append(btn);
  }
}

let visibleEntries = [];

// ---- runs in flight ------------------------------------------------------
//
// A ticket a run is on is marked in the pane the launcher opened
// (`@omp_ticket`), and the run writes every step to its session transcript
// (helpers/org/web/live.lua). The list shows that the run is there and the
// last thing it did; the detail pane streams the rest.

// The session key of an entry whose run is in flight, or null. A batch's
// orchestrator pane carries the session key, so a ticket launched in one
// still matches through its own :OMP_SESSION:.
function runKey(entry) {
  if (!entry) return null;
  const key = entry.session;
  if (key && state.live.sessions.has(key)) return key;
  if (entry.id && state.live.tickets.has(entry.id)) return entry.id;
  return null;
}

function setLive(live) {
  live = live || {};
  state.live.tickets = new Set(live.tickets || []);
  state.live.sessions = new Set(live.sessions || []);
  state.live.activity = live.activity || {};
}

// Patch the drawn rows instead of redrawing them: a redraw would drop the
// selection and the scroll position every couple of seconds.
function applyLive() {
  for (const li of document.querySelectorAll('li.entry')) {
    const entry = li._entry;
    const key = runKey(entry);
    li.classList.toggle('running', !!key);
    const title = li.querySelector('.title');
    let dot = title && title.querySelector('.live-dot');
    if (key && title && !dot) {
      dot = el('span', 'live-dot', '●');
      title.prepend(dot);
    } else if (!key && dot) {
      dot.remove();
    }
    let line = li.querySelector('.live-line');
    if (key) {
      if (!line) {
        line = el('span', 'live-line');
        li.append(line);
      }
      line.textContent = state.live.activity[key] || '';
    } else if (line) {
      line.remove();
    }
  }
}

// While something runs, ask again every few seconds: a run's steps change no
// org file, so the vault's own `change` events do not cover them.
let liveTimer = null;
async function pollLive() {
  const any = state.live.tickets.size > 0 || state.live.sessions.size > 0;
  if (!any) {
    clearInterval(liveTimer);
    liveTimer = null;
    return;
  }
  if (document.hidden) return;
  try {
    setLive(await api('/api/live'));
    applyLive();
  } catch (err) {
    console.error(err);
  }
}

function watchLive() {
  if (liveTimer) return;
  liveTimer = setInterval(pollLive, 2500);
}

// An entry holds the entries nested under it: the next row of its own
// section that sits deeper. Folding one hides that run of rows, the way
// <Tab> on a headline does in the TODO view.
function hasChildren(items, i) {
  return i + 1 < items.length && items[i + 1].depth > items[i].depth;
}

function renderViews() {
  const container = $('#views');
  container.replaceChildren();
  visibleEntries = [];
  const view = state.data.views.find((v) => v.key === state.view) || state.data.views[0];
  if (!view) return;
  let drawn = 0;
  for (const section of view.sections) {
    const items = section.items.filter(matches);
    if (items.length === 0) continue;
    const shown = [];
    const foldedDepths = [];
    for (let i = 0; i < items.length; i++) {
      const entry = items[i];
      entry._children = hasChildren(items, i);
      while (foldedDepths.length && foldedDepths[foldedDepths.length - 1] >= entry.depth) {
        foldedDepths.pop();
      }
      if (foldedDepths.length) continue;
      shown.push(entry);
      if (entry._children && state.folded.has(foldKey(entry))) foldedDepths.push(entry.depth);
    }
    if (shown.length === 0) continue;
    drawn += shown.length;
    const box = el('section', 'view-section' + (section.rule ? ' rule' : ''));
    const head = el('h2');
    head.append(el('span', '', (section.icon ? section.icon + ' ' : '') + section.title));
    head.append(el('span', 'n', String(items.length)));
    if (section.note) head.append(el('span', 'note', section.note));
    box.append(head);
    const list = el('ul', 'entries');
    for (const entry of shown) {
      list.append(entryRow(entry));
      visibleEntries.push(entry);
    }
    box.append(list);
    container.append(box);
  }
  if (drawn === 0) {
    container.append(el('p', 'empty', state.query ? 'Nothing matches the filter.' : 'Nothing here.'));
  }
}

function selectEntry(entry, focusNote) {
  state.selected = { file: entry.file, line: entry.line, id: entry.id };
  state.selectedEntry = entry;
  for (const li of document.querySelectorAll('li.entry.selected')) li.classList.remove('selected');
  const row = document.querySelector(
    `li.entry[data-file="${CSS.escape(entry.file)}"][data-line="${entry.line}"]`,
  );
  if (row) row.classList.add('selected');
  showDetail(entry, focusNote);
}

async function showDetail(entry, focusNote) {
  const detail = $('#detail');
  detail.hidden = false;
  document.body.classList.add('detail-open');
  detail.replaceChildren();
  const header = el('header');
  header.append(el('span', 'where', '~/' + entry.rel + ':' + entry.line));
  const actions = el('span');
  const edit = el('button', '', 'edit');
  edit.title = 'i  edit the entry here';
  edit.addEventListener('click', () => editEntry(entry));
  const open = el('button', '', 'open in editor');
  open.title = 'o  reveal the entry in nvim';
  open.addEventListener('click', () => post('/api/open', entry));
  const close = el('button', '', '✕');
  close.title = 'q  close';
  close.addEventListener('click', () => closeDetail());
  actions.append(edit, open, close);
  header.append(actions);
  detail.append(header);
  const body = el('div', 'body');
  body.append(el('p', 'empty', 'Loading…'));
  detail.append(body);
  try {
    const res = await api(
      '/api/entry?file=' +
        encodeURIComponent(entry.file) +
        '&line=' +
        entry.line +
        (entry.id ? '&id=' + encodeURIComponent(entry.id) : ''),
    );
    body.replaceChildren();
    const title = el('h2', 'detail-title headline');
    if (entry.todo) {
      const chip = el('button', 'state ' + (entry.done ? 'done ' : 'todo ') + entry.todo, entry.todo);
      chip.type = 'button';
      chip.dataset.entry = '1';
      chip.dataset.state = entry.todo;
      chip.title = 'change the state of this entry';
      title.append(chip);
    }
    if (entry.priority) title.append(el('span', 'priority', '[#' + entry.priority + ']'));
    title.append(el('span', 'title', entry.title));
    if (entry.cookie) title.append(el('span', 'cookie', entry.cookie));
    const tags = el('span', 'tag');
    for (const tag of entry.tags || []) tags.append(el('span', '', tag));
    if ((entry.tags || []).length) title.append(tags);
    const org = el('div', 'org');
    org.innerHTML = res.html || '<p class="empty">No body.</p>';
    body.append(title, org);
    // a headline's state and a checkbox of the body write the file, the way
    // the keyword on the entry's own title does (helpers/org/web/clicks)
    OrgActions.bind(title, entry);
    OrgActions.bind(org, entry);
    appendNoteBox(body, entry, focusNote);
    appendRunBox(body, entry);
  } catch (err) {
    body.replaceChildren(el('p', 'empty', 'Could not render the entry.'));
  }
}

function closeDetail() {
  state.selected = null;
  state.selectedEntry = null;
  stopRunStream();
  $('#detail').hidden = true;
  document.body.classList.remove('detail-open');
  for (const li of document.querySelectorAll('li.entry.selected')) li.classList.remove('selected');
}

// The note box of the detail pane: what `<leader>n` in the editor writes --
// a timestamped block at the end of the entry's body, as
// helpers/org/notes.lua stores it. A note on an entry in TEST is the answer
// the run was waiting for, so nvim launches the ticket too.
function appendNoteBox(body, entry, focus) {
  const box = el('div', 'note-box');
  const text = document.createElement('textarea');
  text.rows = 3;
  text.placeholder = 'Add a note';
  const row = el('div', 'note-row');
  const button = el('button', 'primary', 'add note');
  button.type = 'button';
  const hint = el('span', 'hint', 'ctrl+enter');
  row.append(button, hint);
  box.append(text, row);

  async function add() {
    const value = text.value;
    if (!value.trim()) {
      text.focus();
      return;
    }
    button.disabled = true;
    const res = await post('/api/note', entry, { text: value });
    button.disabled = false;
    if (!res || res.error) return;
    showToast(res.launched ? 'note added, the ticket was launched' : 'note added');
    text.value = '';
    await load();
    refreshSelection();
  }

  button.addEventListener('click', add);
  text.addEventListener('keydown', (ev) => {
    if (ev.key === 'Enter' && (ev.ctrlKey || ev.metaKey)) {
      ev.preventDefault();
      add();
    } else if (ev.key === 'Escape') {
      ev.preventDefault();
      text.blur();
    }
  });
  body.append(box);
  if (focus) text.focus();
}

// ---- the run in flight ---------------------------------------------------

function stopRunStream() {
  if (state.runStream) {
    state.runStream.close();
    state.runStream = null;
  }
}

// A question the run put to you, drawn whole: the chip the run gave it, the
// question, and the answers it offered with their tradeoffs. The answer it
// leans on (`recommended`, an index) is marked. This is the same round the
// picker in the omp pane shows, and the run waits on it until you answer
// there, so it is the one step of a transcript that is a turn of yours.
function askCard(ev) {
  const card = el('div', 'run-ask');
  if (ev.t) card.append(el('p', 'run-ask-intent', ev.t));
  for (const q of ev.q || []) {
    const item = el('div', 'run-ask-item');
    if (q.h) item.append(el('span', 'run-ask-header', q.h));
    item.append(el('p', 'run-ask-text', q.q || ''));
    if (q.m) item.append(el('span', 'run-ask-any', 'pick any'));
    const list = el('ol', 'run-ask-options');
    (q.o || []).forEach((opt, i) => {
      const row = el('li', 'run-ask-option' + (q.r === i ? ' recommended' : ''));
      row.append(el('span', 'run-ask-label', opt.l || ''));
      if (opt.d) row.append(el('span', 'run-ask-desc', opt.d));
      list.append(row);
    });
    item.append(list);
    card.append(item);
  }
  return card;
}

// One event of the run, drawn as what it is: the agent speaking, a step of
// thought, a tool it reached for, what the tool answered, a question it put
// to you and your answer to it.
function runEvent(ev) {
  if (ev.k === 'say') return el('p', 'run-say', ev.t);
  if (ev.k === 'think') return el('p', 'run-think', ev.t);
  if (ev.k === 'ask') return askCard(ev);
  if (ev.k === 'answer') return el('p', 'run-answer' + (ev.e ? ' failed' : ''), (ev.e ? '✗ ' : '✔ ') + ev.t);
  if (ev.k === 'user') {
    const box = el('details', 'run-user');
    box.append(el('summary', '', 'the message the run was started with'));
    box.append(el('pre', '', ev.t));
    return box;
  }
  if (ev.k === 'result') {
    const box = el('details', 'run-result' + (ev.e ? ' failed' : ''));
    box.append(el('summary', '', (ev.e ? '✗ ' : '← ') + (ev.n || 'tool')));
    box.append(el('pre', '', ev.t));
    return box;
  }
  if (ev.k === 'tool') {
    const row = el('p', 'run-tool');
    row.append(el('span', 'run-tool-name', ev.n || 'tool'));
    if (ev.t) row.append(document.createTextNode(' ' + ev.t));
    return row;
  }
  if (ev.k === 'title') return el('p', 'run-title', ev.t);
  return null;
}

// The detail pane's window on the run: the tail of the session transcript
// now, then each step as the run writes it, over a stream the server keeps
// open on that one ticket (helpers/org/web/live.lua). Nothing is drawn for
// an entry no run has ever been on.
function appendRunBox(body, entry) {
  stopRunStream();
  const key = entry.session || (entry.id && state.live.tickets.has(entry.id) ? entry.id : null);
  if (!key) return;

  const box = el('div', 'run-box');
  const head = el('div', 'run-head');
  const stateText = el('span', 'run-state', 'connecting…');
  const title = el('span', 'run-title', '');
  const hide = el('button', '', 'hide');
  hide.type = 'button';
  head.append(el('span', 'live-dot', '●'), stateText, title, hide);
  const log = el('div', 'run-log');
  box.append(head, log);
  body.append(box);

  const stick = () => log.scrollHeight - log.scrollTop - log.clientHeight < 40;
  const trim = () => {
    while (log.childElementCount > 400) log.firstElementChild.remove();
  };
  const bottom = (wasStuck) => {
    if (wasStuck) log.scrollTop = log.scrollHeight;
  };
  // whether the run is standing on a question of its own: the last ask of
  // the log has no answer after it, and the picker in its pane is waiting
  let running = false;
  let asking = false;
  const paint = () => {
    box.classList.toggle('running', running);
    box.classList.toggle('asking', asking);
    stateText.textContent = asking ? 'asking you' : running ? 'live' : 'stopped';
  };
  const draw = (events, wasStuck) => {
    for (const ev of events || []) {
      const node = runEvent(ev);
      if (node) log.append(node);
      if (ev.k === 'ask') asking = true;
      else if (ev.k === 'answer') asking = false;
    }
    trim();
    bottom(wasStuck);
    paint();
  };
  const setState = (isRunning) => {
    running = !!isRunning;
    paint();
  };

  const source = new EventSource('/api/live/stream?key=' + encodeURIComponent(key));
  state.runStream = source;
  source.addEventListener('snapshot', (msg) => {
    const snap = JSON.parse(msg.data);
    const wasStuck = true;
    log.replaceChildren();
    asking = false;
    if (snap.title) title.textContent = snap.title;
    if (!snap.file) {
      log.append(el('p', 'empty', 'This run has not written anything yet.'));
    }
    draw(snap.events, wasStuck);
    setState(snap.running);
  });
  source.addEventListener('reset', (msg) => {
    const snap = JSON.parse(msg.data);
    const wasStuck = stick();
    log.replaceChildren();
    asking = false;
    if (snap.title) title.textContent = snap.title;
    draw(snap.events, wasStuck);
    setState(snap.running);
  });
  source.addEventListener('events', (msg) => {
    const payload = JSON.parse(msg.data);
    log.querySelector('.empty')?.remove();
    draw(payload.events, stick());
    setState(true);
  });
  source.addEventListener('status', (msg) => setState(JSON.parse(msg.data).running));
  source.addEventListener('error', () => setState(false));

  hide.addEventListener('click', () => {
    stopRunStream();
    box.remove();
  });
  log.scrollTop = log.scrollHeight;
}

// ---- capture ------------------------------------------------------------

// The destinations the capture form offers: the entry the view has selected
// (the editor's `c`, a child of that entry), then every project of the rail
// (`^`, which lands the entry under the project's own headline).
function destinations() {
  const out = [];
  const selected = state.selectedEntry;
  if (selected) {
    out.push({
      label: 'under “' + selected.title + '”',
      entry: { file: selected.file, line: selected.line, id: selected.id },
    });
  }
  for (const project of state.data.projects) {
    out.push({ label: 'under ' + project.name, entry: { file: project.path } });
  }
  return out;
}

function openCapture() {
  if (!state.data) return;
  document.querySelectorAll('#capture').forEach((node) => node.remove());
  const options = destinations();
  if (!options.length) {
    showToast('Nothing to capture into');
    return;
  }
  const panel = el('div');
  panel.id = 'capture';
  panel.setAttribute('role', 'dialog');
  panel.setAttribute('aria-label', 'capture');

  const form = document.createElement('form');
  const head = el('header');
  head.append(el('span', '', 'capture'));
  const close = el('button', '', '✕');
  close.type = 'button';
  head.append(close);
  form.append(head);

  const title = document.createElement('input');
  title.className = 'title';
  title.placeholder = 'title';
  title.autocomplete = 'off';
  title.spellcheck = false;
  const body = document.createElement('textarea');
  body.className = 'body';
  body.rows = 5;
  body.placeholder = 'description (optional)';
  form.append(title, body);

  const foot = el('footer');
  const select = document.createElement('select');
  select.className = 'dest';
  options.forEach((option, i) => {
    const node = document.createElement('option');
    node.value = String(i);
    node.textContent = option.label;
    select.append(node);
  });
  const submit = el('button', 'primary', 'capture');
  submit.type = 'submit';
  const hint = el('span', 'hint', 'ctrl+enter');
  foot.append(select, hint, submit);
  form.append(foot);
  panel.append(form);
  document.body.append(panel);
  title.focus();

  close.addEventListener('click', () => panel.remove());
  panel.addEventListener('keydown', (ev) => {
    if (ev.key === 'Escape') {
      ev.preventDefault();
      panel.remove();
    } else if (ev.key === 'Enter' && (ev.ctrlKey || ev.metaKey)) {
      ev.preventDefault();
      form.requestSubmit();
    }
  });
  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const name = title.value.trim();
    if (!name) {
      title.focus();
      return;
    }
    const option = options[Number(select.value)] || options[0];
    submit.disabled = true;
    const res = await post('/api/capture', option.entry, { title: name, body: body.value });
    submit.disabled = false;
    if (!res || res.error) return;
    panel.remove();
    showToast('captured ' + name);
    await load();
  });
}


function refreshSelection() {
  if (!state.selected) return;
  const found = visibleEntries.find(
    (e) => e.file === state.selected.file && e.line === state.selected.line,
  );
  if (found) showDetail(found);
}

async function post(path, entry, extra) {
  try {
    const res = await api(path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ file: entry.file, line: entry.line, id: entry.id, ...(extra || {}) }),
    });
    if (res && res.error) showToast(res.error);
    return res;
  } catch (err) {
    showToast('nvim did not answer');
    return null;
  }
}

// ---- menus --------------------------------------------------------------

function closeMenus() {
  document.querySelectorAll('#menu').forEach((m) => m.remove());
}

function openMenu(anchor, items) {
  closeMenus();
  const menu = el('div');
  menu.id = 'menu';
  for (const item of items) {
    const btn = el('button', item.cls || '', item.label);
    btn.addEventListener('click', () => {
      menu.remove();
      item.run();
    });
    menu.append(btn);
  }
  const rect = anchor.getBoundingClientRect();
  menu.style.left = rect.left + 'px';
  menu.style.top = rect.bottom + 4 + 'px';
  document.body.append(menu);
  const off = (ev) => {
    if (!menu.contains(ev.target)) {
      menu.remove();
      document.removeEventListener('mousedown', off);
    }
  };
  setTimeout(() => document.addEventListener('mousedown', off), 0);
  return menu;
}

function openStateMenu(anchor, entry) {
  const keywords = state.data.keywords || { open: ['TODO'], done: ['DONE'] };
  const items = [];
  for (const kw of [...keywords.open, ...keywords.done]) {
    if (kw === entry.todo) continue;
    items.push({
      label: kw,
      cls: kw,
      run: () => setState(entry, kw),
    });
  }
  items.push({ label: 'no keyword', run: () => setState(entry, '') });
  openMenu(anchor, items);
}

function openPriorityMenu(anchor, entry) {
  const items = [];
  for (const value of ['A', 'B', 'C']) {
    if (value === entry.priority) continue;
    items.push({
      label: '#' + value,
      run: async () => {
        const res = await post('/api/priority', entry, { priority: value });
        if (res && !res.error) {
          showToast(`${entry.title} → #${value}`);
          await reload();
        }
      },
    });
  }
  items.push({
    label: 'no priority',
    run: async () => {
      const res = await post('/api/priority', entry, { priority: '' });
      if (res && !res.error) await reload();
    },
  });
  openMenu(anchor, items);
}

// ---- writes -------------------------------------------------------------

async function reload() {
  await load();
  refreshSelection();
}

async function setState(entry, kw) {
  const res = await post('/api/state', entry, { state: kw });
  if (res && !res.error) {
    showToast(res.warning || `${entry.title} → ${res.state || kw || 'no keyword'}`);
    await reload();
  }
}

function toggleDone(entry) {
  if (!entry) return;
  setState(entry, entry.done ? 'TODO' : 'DONE');
}

async function cycleState(entry) {
  if (!entry) return;
  const res = await post('/api/cycle', entry);
  if (res && !res.error) {
    showToast(`${entry.title} → ${res.state || 'no keyword'}`);
    await reload();
  }
}

async function toggleTag(entry, tag) {
  if (!entry) return;
  const res = await post('/api/tags', entry, { tag });
  if (res && !res.error) {
    showToast(`${':' + tag + ':'} ${(res.tags || []).includes(tag) ? 'on' : 'off'}`);
    await reload();
  }
}

// One line asked for under the list -- the view's prompt, without a browser
// dialog: typing stays inside the page and the keys come back when it closes.
function askLine(question, value) {
  closePrompt();
  return new Promise((resolve) => {
    const box = el('div');
    box.id = 'prompt';
    box.append(el('label', '', question));
    const input = document.createElement('input');
    input.type = 'text';
    input.value = value || '';
    input.spellcheck = false;
    box.append(input);
    document.body.append(box);
    input.focus();
    input.select();
    const finish = (answer) => {
      box.remove();
      resolve(answer);
    };
    input.addEventListener('keydown', (ev) => {
      ev.stopPropagation();
      if (ev.key === 'Enter') {
        ev.preventDefault();
        finish(input.value);
      } else if (ev.key === 'Escape') {
        ev.preventDefault();
        finish(null);
      }
    });
    box.append(
      (() => {
        const go = el('button', '', 'set');
        go.addEventListener('click', () => finish(input.value));
        return go;
      })(),
    );
  });
}

function closePrompt() {
  document.querySelectorAll('#prompt').forEach((box) => box.remove());
}

async function setTags(entry) {
  if (!entry) return;
  const current = (entry.tags || []).join(' ');
  const typed = await askLine(`tags of "${entry.title}"`, current);
  if (typed === null) return;
  const tags = typed.split(/[\s,]+/).filter(Boolean);
  const res = await post('/api/tags', entry, { tags });
  if (res && !res.error) {
    showToast(`tags: ${(res.tags || []).join(' ') || 'none'}`);
    await reload();
  }
}

async function removeEntry(entry) {
  if (!entry) return;
  const res = await post('/api/kill', entry);
  if (res && !res.error) {
    showToast(`${entry.title} → deleted (u undoes it)`);
    closeDetail();
    await reload();
  }
}

async function archiveEntry(entry) {
  if (!entry) return;
  const res = await post('/api/archive', entry);
  if (res && !res.error) {
    showToast(`${entry.title} → archived`);
    closeDetail();
    await reload();
  }
}

async function undoWrite() {
  const entry = state.selected || currentEntry();
  if (!entry) return;
  const res = await post('/api/undo', entry);
  if (res && !res.error) showToast('undone', '');
  await reload();
}

function launchEntry(entry, jump) {
  if (!entry) return;
  post('/api/launch', entry, { jump: !!jump });
  showToast(jump ? 'jumping to the run' : 'launching a run on it');
}

// ---- the entry editor ---------------------------------------------------

async function editEntry(entry) {
  if (!entry) return;
  try {
    const res = await api(
      '/api/text?file=' +
        encodeURIComponent(entry.file) +
        '&line=' +
        entry.line +
        (entry.id ? '&id=' + encodeURIComponent(entry.id) : ''),
    );
    if (!res.text) {
      showToast(res.error || 'could not read the entry');
      return;
    }
    const lines = res.text.lines.slice();
    OrgEditor.open({
      file: entry.file,
      id: entry.id,
      line: res.text.start,
      start: res.text.start,
      text: lines.join('\n'),
      where: '~/' + entry.rel + ':' + res.text.start,
      onSaved: () => reload(),
      onClose: () => refreshSelection(),
    });
  } catch (err) {
    showToast('could not read the entry');
  }
}

// ---- folding ------------------------------------------------------------

const foldKey = (entry) => entry.file + '#' + entry.line;

function cycleFold(entry) {
  if (!entry) return;
  const key = foldKey(entry);
  if (state.folded.has(key)) state.folded.delete(key);
  else state.folded.add(key);
  renderViews();
}

function unfold(entry) {
  if (!entry) return;
  if (state.folded.delete(foldKey(entry))) renderViews();
}

function foldEntry(entry) {
  if (!entry) return;
  if (!state.folded.has(foldKey(entry)) && entry._children) {
    state.folded.add(foldKey(entry));
    renderViews();
  }
}

function cycleAllFolds() {
  const rows = visibleEntries.filter((entry) => entry._children);
  if (!rows.length) return;
  const anyOpen = rows.some((entry) => !state.folded.has(foldKey(entry)));
  for (const entry of rows) {
    if (anyOpen) state.folded.add(foldKey(entry));
    else state.folded.delete(foldKey(entry));
  }
  renderViews();
}

// ---- the keymap ---------------------------------------------------------

// The list reads like the TODO view in nvim: j/k and the half page, gg/G,
// <Tab> to fold an entry, D/T/N/u on the entry at point, dd to delete it,
// `i` to edit its text here, `o` to open it in the editor, and <Space> for
// the leader, where `o` + the view key switches views (ow, oo, of, og, op,
// oy) and `ai` / `aj` launch or jump to a run.
const HELP = [
  ['j / k', 'next / previous entry'],
  ['J / K, <C-d> / <C-u>', 'half a page down / up'],
  ['gg / G', 'first / last entry (with a count: that entry)'],
  ['<Tab> / <S-Tab>', 'fold the entry at point / fold every entry'],
  ['l / h', 'unfold / fold the entry at point'],
  ['<CR>, L', 'open the entry (the detail pane)'],
  ['i', 'edit the entry here, in a modal editor'],
  ['c', 'capture a task under the entry or a project'],
  ['n', 'add a note to the entry here'],
  ['o', 'open the entry in nvim'],
  ['D / T / N', 'toggle done / back to TODO / next keyword'],
  ['u', 'undo the last write to the file'],
  ['t / p', 'set tags / set priority'],
  ['B / F / C', 'toggle :bug: / :feat: / :chore:'],
  ['dd / a', 'delete the entry’s subtree / archive it'],
  ['r', 'refile: then <CR> on the destination'],
  ['/ / ?', 'filter the view / this help'],
  ['<Space>ow / oo / of / og / op / oy', 'board / open / in flight / by state / priorities / wayfinder'],
  ['<Space>ai / <Space>aj', 'launch a run on the entry / jump to it'],
];

function showHelp() {
  let box = $('#help');
  if (box) {
    box.remove();
    return;
  }
  box = el('div');
  box.id = 'help';
  box.append(el('h3', '', 'keys'));
  const list = el('dl');
  for (const [keys, what] of HELP) {
    list.append(el('dt', '', keys));
    list.append(el('dd', '', what));
  }
  box.append(list);
  box.append(el('p', 'note', 'Esc or ? closes this.'));
  document.body.append(box);
}

const prefixLabel = {
  ' ': '<Space>',
  ' o': '<Space>o',
  ' a': '<Space>a',
  ' n': '<Space>n',
  g: 'g',
  d: 'd',
};

function showPending() {
  const cmdline = $('#cmdline');
  if (!cmdline) return;
  let text = '';
  if (state.count) text += state.count;
  if (state.pending) text += prefixLabel[state.pending] || state.pending;
  cmdline.textContent = text;
  cmdline.classList.toggle('on', text !== '' || !!state.refile);
}

function resetKeys() {
  state.count = 0;
  state.pending = '';
  showPending();
}

function setPending(pending) {
  state.pending = pending;
  showPending();
}

function rows() {
  return [...document.querySelectorAll('li.entry')];
}

function currentIndex() {
  const all = rows();
  const selected = document.querySelector('li.entry.selected');
  return Math.max(0, all.indexOf(selected));
}

function currentEntry() {
  const all = rows();
  if (!all.length) return null;
  const idx = all.indexOf(document.querySelector('li.entry.selected'));
  return visibleEntries[idx === -1 ? 0 : idx] || null;
}

function moveToIndex(idx) {
  if (!visibleEntries.length) return;
  idx = Math.max(0, Math.min(visibleEntries.length - 1, idx));
  const entry = visibleEntries[idx];
  if (!entry) return;
  selectEntry(entry);
  document.querySelector('li.entry.selected')?.scrollIntoView({ block: 'nearest' });
}

function move(delta) {
  const all = rows();
  const idx = all.indexOf(document.querySelector('li.entry.selected'));
  moveToIndex(idx === -1 ? (delta > 0 ? 0 : all.length - 1) : idx + delta);
}

function halfPage(dir, times) {
  const step = Math.max(4, Math.round(window.innerHeight / 44)) * (times || 1);
  move(dir * step);
}

function setView(key) {
  const view = state.data.views.find((v) => v.key === key);
  if (!view) return;
  state.view = view.key;
  renderTabs();
  renderViews();
}

const VIEW_KEYS = {
  w: 'board',
  o: 'open',
  f: 'flight',
  g: 'state',
  p: 'priority',
  y: 'wayfinder',
};

async function onKey(ev) {
  if (ev.metaKey) return;
  const key = ev.key;
  const ctrl = ev.ctrlKey;
  const target = ev.target;
  const typing = target && target.closest && target.closest('input, textarea');

  if (typing) {
    // in the filter box only Escape is the list's
    if (key === 'Escape' && target === $('#search')) {
      ev.preventDefault();
      $('#search').value = '';
      state.query = '';
      $('#search').blur();
      renderViews();
      resetKeys();
    }
    return;
  }

  if (ev.key === 'Escape') {
    ev.preventDefault();
    if (state.refile) {
      state.refile = null;
      showPending();
      showToast('refile cancelled');
      return;
    }
    if (state.pending || state.count) {
      resetKeys();
      return;
    }
    closeMenus();
    closePrompt();
    const help = $('#help');
    if (help) {
      help.remove();
      return;
    }
    closeDetail();
    return;
  }

  if (ctrl && (key === 'd' || key === 'u')) {
    ev.preventDefault();
    halfPage(key === 'd' ? 1 : -1, state.count || 1);
    resetKeys();
    return;
  }
  if (ctrl || ev.altKey) return;

  // ---- prefixes ---------------------------------------------------------
  if (state.pending === 'g') {
    resetKeys();
    if (key === 'g') moveToIndex((state.count || 1) - 1);
    else if (key === '?') showHelp();
    return;
  }
  if (state.pending === ' ') {
    if (key === 'o') {
      ev.preventDefault();
      setPending(' o');
      return;
    }
    if (key === 'a') {
      ev.preventDefault();
      setPending(' a');
      return;
    }
    if (key === 'n') {
      ev.preventDefault();
      setPending(' n');
      return;
    }
    resetKeys();
    return;
  }
  if (state.pending === ' o') {
    const view = VIEW_KEYS[key];
    resetKeys();
    if (view) setView(view);
    return;
  }
  if (state.pending === ' n') {
    resetKeys();
    if (key === 'n') selectEntry(currentEntry(), true);
    return;
  }
  if (state.pending === ' a') {
    const entry = currentEntry();
    resetKeys();
    if (key === 'i') launchEntry(entry, false);
    else if (key === 'j') launchEntry(entry, true);
    return;
  }
  if (state.pending === 'd') {
    const entry = currentEntry();
    resetKeys();
    if (key === 'd') removeEntry(entry);
    return;
  }
  if (key === 'd') {
    ev.preventDefault();
    setPending('d');
    return;
  }
  if (key === 'g') {
    ev.preventDefault();
    setPending('g');
    return;
  }
  if (key === ' ') {
    ev.preventDefault();
    setPending(' ');
    return;
  }

  // ---- counts -----------------------------------------------------------
  if (/^[0-9]$/.test(key) && (state.count || key !== '0')) {
    ev.preventDefault();
    state.count = (state.count || 0) * 10 + Number(key);
    showPending();
    return;
  }

  if (key === 'c') {
    ev.preventDefault();
    openCapture();
    return;
  }

  const entry = currentEntry();
  const times = state.count || 1;
  const done = () => resetKeys();

  switch (key) {
    case 'j':
    case 'ArrowDown':
      ev.preventDefault();
      move(times);
      done();
      return;
    case 'k':
    case 'ArrowUp':
      ev.preventDefault();
      move(-times);
      done();
      return;
    case 'J':
      ev.preventDefault();
      halfPage(1, times);
      done();
      return;
    case 'K':
      ev.preventDefault();
      halfPage(-1, times);
      done();
      return;
    case 'G':
      ev.preventDefault();
      moveToIndex(state.count ? state.count - 1 : visibleEntries.length - 1);
      done();
      return;
    case '/':
      ev.preventDefault();
      $('#search').focus();
      done();
      return;
    case '?':
      ev.preventDefault();
      showHelp();
      done();
      return;
    default:
      break;
  }

  if (!entry) {
    done();
    return;
  }

  ev.preventDefault();
  switch (key) {
    case 'Enter':
    case 'L':
      if (state.refile) {
        const src = state.refile;
        state.refile = null;
        showPending();
        post('/api/refile', src, {
          dest: { file: entry.file, line: entry.line, id: entry.id },
        }).then(async (res) => {
          if (res && !res.error) showToast(`${src.title} → ${entry.title}`);
          await reload();
        });
        return;
      }
      selectEntry(entry);
      document.querySelector('li.entry.selected')?.scrollIntoView({ block: 'nearest' });
      break;
    case 'Tab':
      cycleFold(entry);
      break;
    case 'Backtab':
      cycleAllFolds();
      break;
    case 'l':
      unfold(entry);
      break;
    case 'h':
      foldEntry(entry);
      break;
    case 'i':
      editEntry(entry);
      break;
    case 'n':
      selectEntry(entry, true);
      break;
    case 'o':
      post('/api/open', entry);
      break;
    case 'D':
      toggleDone(entry);
      break;
    case 'T':
      setState(entry, 'TODO');
      break;
    case 'N':
      cycleState(entry);
      break;
    case 'u':
      undoWrite();
      break;
    case 't':
      setTags(entry);
      break;
    case 'p':
      openPriorityMenu(document.querySelector('li.entry.selected') || document.body, entry);
      break;
    case 'B':
      toggleTag(entry, 'bug');
      break;
    case 'F':
      toggleTag(entry, 'feat');
      break;
    case 'C':
      toggleTag(entry, 'chore');
      break;
    case 'a':
      archiveEntry(entry);
      break;
    case 'r':
      state.refile = entry;
      showPending();
      showToast('refile: <CR> on the destination, Esc to cancel');
      break;
    case 'q':
      closeDetail();
      break;
    default:
      break;
  }
  done();
}

document.addEventListener('keydown', onKey);

// ---- snippets -----------------------------------------------------------

// A snippet's copy button takes the code it sits over -- what the page shows,
// colours dropped -- and says so for a moment.
document.addEventListener('click', async (ev) => {
  const button = ev.target.closest('.snippet-copy');
  if (!button) return;
  const code = button.closest('.snippet')?.querySelector('pre code');
  if (!code) return;
  try {
    await copyText(code.textContent);
    button.classList.add('copied');
    button.textContent = 'copied';
  } catch (err) {
    button.textContent = 'no clipboard';
  }
  setTimeout(() => {
    button.classList.remove('copied');
    button.textContent = 'copy';
  }, 1600);
});

async function copyText(text) {
  if (navigator.clipboard && window.isSecureContext) {
    await navigator.clipboard.writeText(text);
    return;
  }
  const box = el('textarea');
  box.value = text;
  box.setAttribute('readonly', '');
  box.style.position = 'fixed';
  box.style.opacity = '0';
  document.body.append(box);
  box.select();
  document.execCommand('copy');
  box.remove();
}

// ---- capture ------------------------------------------------------------

$('#capture-open').addEventListener('click', () => openCapture());

// ---- filter -------------------------------------------------------------

$('#search').addEventListener('input', (ev) => {
  state.query = ev.target.value;
  renderViews();
});

// ---- live reload --------------------------------------------------------

const live = new EventSource('/events');
live.addEventListener('change', debounce(async () => {
  await load();
  refreshSelection();
}, 200));
live.addEventListener('open', () => $('#live').classList.add('on'));
live.addEventListener('error', () => $('#live').classList.remove('on'));

load();
