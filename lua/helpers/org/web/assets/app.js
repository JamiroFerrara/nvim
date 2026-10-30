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
  live: { tickets: new Set(), sessions: new Set(), activity: {}, instances: [] }, // runs in flight
  runStream: null, // the open event stream of the run the detail pane shows
  runDetail: null, // the run the detail pane is showing, when it is one
  historyOpen: false, // the detail pane is a history step (a phone's back)
};

const $ = (sel) => document.querySelector(sel);
const isPhone = () =>
  window.matchMedia(
    '(max-width: 720px), (hover: none) and (pointer: coarse), (max-height: 500px) and (hover: none)',
  ).matches;
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

function matchesQuery(entry, query) {
  const q = (query || '').trim().toLowerCase();
  if (!q) return true;
  const haystack = (entry.title + ' ' + (entry.project || '') + ' ' + (entry.tags || []).join(' ')).toLowerCase();
  // every word has to appear somewhere: "ing tree" finds the tree tickets
  return q.split(/\s+/).every((word) => {
    if (word.startsWith('#')) return (entry.tags || []).some((t) => t.toLowerCase().includes(word.slice(1)));
    return haystack.includes(word);
  });
}

function matches(entry) {
  return matchesQuery(entry, state.query);
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

  const doButton = el('button', 'do');
  doButton.type = 'button';
  paintDo(doButton, entry);
  doButton.addEventListener('click', (ev) => {
    ev.stopPropagation();
    launchEntry(entry, !!runKey(entry));
  });
  li.append(doButton);
  li.append(rowActs(entry));

  const key = runKey(entry);
  if (key) {
    li.classList.add('running');
    li.append(el('span', 'live-line', state.live.activity[key] || ''));
  }

  li._entry = entry;
  li.addEventListener('click', () => selectEntry(entry));
  return li;
}

// One line of the agenda: the time it starts at on the left, then the keyword
// and the priority, the headline, its tags and the project -- org's own agenda
// line, in columns, with the row's run button kept. An item no headline
// carries (a diary line) draws the same row with nothing to click.
function agendaRow(entry) {
  const time = entry.agenda && entry.agenda.time;
  const live = !!entry.file && entry.line != null;
  const li = el('li', 'entry agenda-row' + (entry.done ? ' done-entry' : ''));
  if (live) {
    li.dataset.file = entry.file;
    li.dataset.line = entry.line;
  }

  const at = el('span', 'at', time || '');
  if (entry.agenda && entry.agenda.type) at.title = entry.agenda.type;
  li.append(at);

  if (entry.todo) {
    const chip = el('button', 'state ' + entry.todo, entry.todo);
    chip.title = 'Change state';
    chip.addEventListener('click', (ev) => {
      ev.stopPropagation();
      openStateMenu(chip, entry);
    });
    li.append(chip);
  } else {
    li.append(el('span', 'state none', '·'));
  }

  li.append(el('span', 'prio', entry.priority || ''));

  const title = el('span', 'title');
  if (runKey(entry)) title.append(el('span', 'live-dot', '●'));
  title.append(document.createTextNode(entry.title || ''));
  if (live) title.title = entry.rel + ':' + entry.line;
  li.append(title);

  const base = ((entry.rel || '').split('/').pop() || '').replace(/\.org$/, '').toLowerCase();
  const tags = el('span', 'tags');
  for (const tag of entry.tags || []) {
    const lower = tag.toLowerCase();
    if (lower === base || lower === (entry.project || '').toLowerCase()) continue;
    tags.append(el('span', '', tag));
  }
  li.append(tags);

  li.append(el('span', 'project', state.selection === 'all' ? entry.project || '' : ''));

  if (entry.id) {
    const doButton = el('button', 'do');
    doButton.type = 'button';
    paintDo(doButton, entry);
    doButton.addEventListener('click', (ev) => {
      ev.stopPropagation();
      launchEntry(entry, !!runKey(entry));
    });
    li.append(doButton);
  } else {
    li.append(el('span', ''));
  }
  // a diary line is not a ticket: nothing to close and nothing to delete
  li.append(live ? rowActs(entry) : el('span', 'row-acts'));

  const key = runKey(entry);
  if (key) {
    li.classList.add('running');
    li.append(el('span', 'live-line', state.live.activity[key] || ''));
  }

  li._entry = entry;
  if (live) {
    title.addEventListener('click', () => selectEntry(entry));
    li.addEventListener('click', () => selectEntry(entry));
  }
  return li;
}

// The line the current time falls on inside today's section, the way org's
// agenda marks the moment: the time, then a rule across the row.
function nowLine(minutes) {
  const h = Math.floor(minutes / 60);
  const m = String(minutes % 60).padStart(2, '0');
  const li = el('li', 'agenda-now');
  li.append(el('span', 'at', `${h}:${m}`));
  li.append(el('span', 'rule', 'now'));
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
  // the payload follows the vault: a ticket that just opened, closed or lost
  // its title is a different answer to the same search
  const box = $('#tsearch');
  if (box) paintSearch(box.querySelector('input').value);
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
loadShare();
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
  nav.querySelector('button.active')?.scrollIntoView({ block: 'nearest', inline: 'center' });
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
    btn.dataset.view = view.key;
    btn.append(el('span', '', view.icon + ' ' + view.title));
    btn.append(el('span', 'badge', String(view.count ?? viewCount(view))));
    btn.addEventListener('click', () => {
      state.view = view.key;
      renderTabs();
      renderViews();
      // the runs view has no entries to draw from: it is live data, so it
      // asks for it now and keeps asking while it is the view on screen
      if (view.key === 'runs') {
        watchLive();
        pollLive();
      }
    });
    tabs.append(btn);
  }
  // on a phone the row is wider than the screen: the view that is on is the
  // one that has to be visible
  tabs.querySelector('button.active')?.scrollIntoView({ block: 'nearest', inline: 'center' });
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

// The button a row carries to act on its ticket at once: a ticket with no
// run is started on the spot, one a run is already on is jumped to. It is
// the two halves `<Space>ai` and `<Space>aj` do, and the row says which it
// will do -- `▸` to start, `●` to the run.
function paintDo(button, entry) {
  const running = !!runKey(entry);
  button.classList.toggle('running', running);
  button.textContent = running ? 'jump' : 'run';
  button.title = running ? 'jump to the run on this ticket' : 'start a run on this ticket now';
}

function setLive(live) {
  live = live || {};
  state.live.tickets = new Set(live.tickets || []);
  state.live.sessions = new Set(live.sessions || []);
  state.live.activity = live.activity || {};
  state.live.instances = live.instances || [];
}

// Patch the drawn rows instead of redrawing them: a redraw would drop the
// selection and the scroll position every couple of seconds.
function applyLive() {
  for (const li of document.querySelectorAll('li.entry')) {
    // the Runs view's rows are patched by `applyRuns`: they are runs, not
    // entries with a run attached
    if (li.dataset.run) continue;
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
    const doButton = li.querySelector('button.do');
    if (doButton) paintDo(doButton, entry);
  }
}

// The Runs view's rows, patched the same way: an activity line that changed,
// an elapsed time that moved. The rows themselves are redrawn when the set of
// runs changes -- one started or ended -- because then there is a row to add
// or drop.
function applyRuns() {
  const list = document.querySelector('#views ul.entries.runs');
  if (!list) return;
  const runs = state.live.instances.filter(runMatches);
  if (list.dataset.keys !== runs.map((run) => run.key).join('|')) {
    renderRuns();
    return;
  }
  for (const li of list.children) {
    const run = runs.find((r) => r.key === li.dataset.run);
    if (!run) continue;
    const line = li.querySelector('.live-line');
    if (line) line.textContent = run.activity || '';
    const when = li.querySelector('.meta');
    if (when) when.textContent = elapsed(run.started);
  }
}

// The Runs tab's count is the number of rows the view would draw, so it only
// moves while that view is on screen.
function syncRunsBadge() {
  const badge = document.querySelector('#tabs button[data-view="runs"] .badge');
  if (badge) badge.textContent = String(state.live.instances.filter(runMatches).length);
}

// While something runs, ask again every few seconds: a run's steps change no
// org file, so the vault's own `change` events do not cover them.
let liveTimer = null;
async function pollLive() {
  // the runs view asks even with nothing in flight: what it shows is a run
  // that started after the last look, and no org file changed to say so
  const any = state.live.tickets.size > 0 || state.live.sessions.size > 0 || state.view === 'runs';
  if (!any) {
    clearInterval(liveTimer);
    liveTimer = null;
    return;
  }
  if (document.hidden) return;
  try {
    setLive(await api('/api/live'));
    applyLive();
    if (state.view === 'runs') {
      applyRuns();
      syncRunsBadge();
    }
    applyRunDetail();
  } catch (err) {
    console.error(err);
  }
}

// The run the detail pane is showing, brought up to date from the last look:
// its elapsed time, its activity, and whether it is still one of the runs.
// A run that has ended keeps its log on screen -- the last steps are what it
// did -- and the line says it has stopped.
function applyRunDetail() {
  const shown = state.runDetail;
  if (!shown) return;
  const meta = document.querySelector('#detail .run-meta');
  if (!meta) return;
  const run = (state.live.instances || []).find((r) => r.key === shown.key);
  if (run) {
    state.runDetail = run;
    if (run.title) shown.title = run.title;
    meta.textContent = runMeta(run);
  } else {
    meta.textContent = runMeta(shown) + '  ·  ended';
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
  const view = state.data.views.find((v) => v.key === state.view) || state.data.views[0];
  if (!view) return;
  // the graph decides for itself whether it has to be drawn again, so it
  // clears the pane on its own terms
  if (view.key === 'graph') {
    renderGraph();
    return;
  }
  container.classList.remove('graphing');
  container.replaceChildren();
  visibleEntries = [];
  if (view.key === 'runs') {
    renderRuns();
    return;
  }
  let drawn = 0;
  for (const section of view.sections) {
    const items = section.items.filter(matches);
    if (items.length === 0 && section.day == null) continue;
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
    if (shown.length === 0 && section.day == null) continue;
    drawn += shown.length;
    const box = el('section', 'view-section' + (section.rule ? ' rule' : '') + (section.today ? ' today' : ''));
    if (section.day != null && shown.length === 0) box.classList.add('empty-day');
    const head = el('h2');
    // a day of the agenda names its weekday and date, the way org's agenda
    // header does; every other view keeps its own title
    if (section.label) {
      head.append(el('span', 'dow', section.label.dow));
      head.append(el('span', 'day-date', section.label.date));
    } else {
      head.append(el('span', '', (section.icon ? section.icon + ' ' : '') + section.title));
    }
    if (section.day == null || items.length > 0) head.append(el('span', 'n', String(items.length)));
    if (section.note) head.append(el('span', 'note', section.note));
    box.append(head);
    const list = el('ul', 'entries' + (view.key === 'agenda' ? ' agenda' : ''));
    // where today's "now" line goes: before the first entry still to come,
    // and after the last one when the day is over
    let nowAt = -1;
    if (section.now != null) {
      nowAt = shown.findIndex((entry) => entry.at != null && entry.at > section.now);
      if (nowAt === -1) nowAt = shown.length;
    }
    shown.forEach((entry, i) => {
      if (i === nowAt) list.append(nowLine(section.now));
      list.append(view.key === 'agenda' ? agendaRow(entry) : entryRow(entry));
      visibleEntries.push(entry);
    });
    if (nowAt === shown.length) list.append(nowLine(section.now));
    box.append(list);
    container.append(box);
  }
  if (drawn === 0) {
    container.append(el('p', 'empty', state.query ? 'Nothing matches the filter.' : 'Nothing here.'));
  }
}

// ---- the ticket graph ----------------------------------------------------
//
// The board as a picture (/api/graph): every open ticket a node, and two kinds
// of edge -- the nesting a ticket sits in (the child is what blocks the
// parent) and the `[[id:…]]` links its body wrote. A closed ticket an open one
// points back at is drawn too, drained of colour, so a trace runs past the
// work already done.
//
// The layout, the panning and the zooming are the shared engine's
// (assets/graph.js), the same one the roam notes are drawn by; this function
// only says what a ticket is and what a click on one does.

let graphToken = 0;
let graphKey = null; // the payload the drawn picture was made from

async function renderGraph() {
  const container = $('#views');
  container.classList.add('graphing');
  if (!container.querySelector('svg.graph-svg')) {
    container.replaceChildren(el('p', 'empty', 'Laying the tickets out…'));
  }
  const token = ++graphToken;
  let data;
  try {
    data = await api('/api/graph?file=' + encodeURIComponent(state.selection));
  } catch (err) {
    if (token === graphToken) container.replaceChildren(el('p', 'empty', 'Could not read the ticket graph.'));
    return;
  }
  // the rail or the vault moved on while this was in flight
  if (token !== graphToken || state.view !== 'graph') return;
  // the vault is saved constantly and most of it is not a ticket: a picture
  // that did not change must not set itself moving again on every save
  const key = JSON.stringify(data);
  if (key === graphKey && container.querySelector('svg.graph-svg')) {
    OrgGraph.filter(state.query);
    return;
  }
  graphKey = key;
  container.replaceChildren();
  if (data.nodes.length === 0) {
    container.append(el('p', 'empty', 'No open ticket to draw here.'));
    return;
  }
  // the engine draws an `id`; the ticket behind it is what a click opens. The
  // node's own `:ID:` rides along as `entryId`, because the engine's id is the
  // key -- the `:ID:` itself, or the place a ticket without one sits.
  const nodes = data.nodes.map((node) => ({
    ...node,
    entryId: node.id,
    id: node.key,
    // a whole ticket title is a sentence: the picture takes its head, the
    // hover and the detail pane take the rest
    label: node.title.length > 30 ? node.title.slice(0, 29).trimEnd() + '…' : node.title,
    class: ['state-' + (node.todo || 'none'), node.done ? 'done' : '', runKey(node) ? 'running' : ''].join(' ').trim(),
  }));
  OrgGraph.draw(container, {
    nodes,
    edges: data.edges,
    hud: [
      `${data.stats.open} open · ${data.stats.nodes - data.stats.open} closed · ${data.stats.edges} edges`,
      'click a ticket · drag to pan · scroll to zoom',
    ],
    // a ticket is read by its name: the dots say the shape, the names say
    // which ticket, and a zoom is what makes room for the long ones
    labelsAll: true,
    query: state.query,
    open: (node) => selectEntry({ ...node, id: node.entryId }),
    tip: (node) => {
      const parts = [node.todo || '—', node.project].filter(Boolean);
      if (node.links) parts.push(node.links + '→');
      if (node.backlinks) parts.push(node.backlinks + '←');
      return node.title + ' — ' + parts.join(' · ');
    },
  });
}

// ---- the Runs view -------------------------------------------------------
//
// A run is a tmux pane the launcher opened and marked: a ticket's :ID: in
// `@omp_ticket`, a project's session key (or the talking instance's) in
// `@omp_orchestrator`. Its own transcript says what it is doing now
// (helpers/org/web/live.lua), and the server pairs each one with the ticket's
// entry when the vault still holds that ticket.

// How long a run has been going, the way the editor's own window says it.
function elapsed(started) {
  if (!started) return '';
  const secs = Math.max(0, Math.floor(Date.now() / 1000 - started));
  if (secs < 60) return secs + 's';
  if (secs < 3600) return Math.floor(secs / 60) + 'm ' + String(secs % 60).padStart(2, '0') + 's';
  return Math.floor(secs / 3600) + 'h ' + String(Math.floor((secs % 3600) / 60)).padStart(2, '0') + 'm';
}

function runMatches(run) {
  const q = state.query.trim().toLowerCase();
  if (!q) return true;
  const entry = run.entry || {};
  const haystack = [run.title, run.activity, entry.project, entry.todo, ...(entry.tags || [])]
    .filter(Boolean)
    .join(' ')
    .toLowerCase();
  return q.split(/\s+/).every((word) => haystack.includes(word.replace(/^#/, '')));
}

function runRow(run) {
  const entry = run.entry;
  const li = el('li', 'entry run-row running');
  li.dataset.run = run.key;
  if (entry) {
    li.dataset.file = entry.file;
    li.dataset.line = entry.line;
  }
  const chip = el('span', 'state ' + ((entry && entry.todo) || ''), (entry && entry.todo) || '·');
  chip.title = entry ? 'the ticket this run is on' : 'a session run, no ticket';
  li.append(chip);
  li.append(el('span', 'prio', (entry && entry.priority) || ''));
  li.append(el('span', 'fold empty'));
  const title = el('span', 'title');
  title.append(el('span', 'live-dot', '●'));
  title.append(document.createTextNode(run.title));
  title.title = entry ? entry.rel + ':' + entry.line : 'tmux pane ' + run.pane;
  li.append(title);
  li.append(el('span', 'tags'));
  li.append(el('span', 'meta', elapsed(run.started)));
  li.append(el('span', 'project', state.selection === 'all' ? (entry && entry.project) || '' : ''));
  // the way out of a run that is going nowhere: the pane goes, and the omp
  // inside it with it. Armed like the ticket row's `✕` -- the first click
  // says what the second will do.
  const acts = el('span', 'row-acts');
  const cancel = el('button', 'kill', '✕');
  cancel.type = 'button';
  cancel.title = 'cancel this run';
  cancel.addEventListener('click', (ev) => {
    ev.stopPropagation();
    if (!cancel.dataset.armed) {
      cancel.dataset.armed = '1';
      cancel.textContent = 'cancel?';
      cancel.classList.add('armed');
      clearTimeout(cancel._disarm);
      cancel._disarm = setTimeout(() => {
        delete cancel.dataset.armed;
        cancel.textContent = '✕';
        cancel.classList.remove('armed');
      }, 4000);
      return;
    }
    cancelRun(run);
  });
  acts.append(cancel);
  li.append(acts);
  li.append(el('span', 'live-line', run.activity || ''));
  // the row opens the run itself -- what the instance is doing, step by step
  // -- whether or not it is on a ticket; a ticket's title is the way to the
  // entry the run is working on
  li.addEventListener('click', () => showRun(run));
  if (entry) {
    title.addEventListener('click', (ev) => {
      ev.stopPropagation();
      selectEntry(entry);
    });
  }
  return li;
}

// The click of a run's `✕`: the server kills the pane, and the row goes at
// once -- no waiting on the next poll to say the run is over.
async function cancelRun(run) {
  const res = await post('/api/cancel', {}, { pane: run.pane });
  if (res && !res.error) {
    state.live.instances = state.live.instances.filter((r) => r.pane !== run.pane);
    for (const key of [run.ticket, run.key]) {
      if (key) {
        state.live.tickets.delete(key);
        state.live.sessions.delete(key);
      }
    }
    showToast(`${run.title} → cancelled`);
    renderRuns();
    syncRunsBadge();
  }
}

function renderRuns() {
  const container = $('#views');
  const runs = (state.live.instances || []).filter(runMatches);
  container.replaceChildren();
  visibleEntries = [];
  if (runs.length === 0) {
    container.append(
      el('p', 'empty', state.query ? 'Nothing matches the filter.' : 'No omp instance is running.'),
    );
    return;
  }
  const box = el('section', 'view-section');
  const head = el('h2');
  head.append(el('span', '', '● Running'));
  head.append(el('span', 'n', String(runs.length)));
  box.append(head);
  const list = el('ul', 'entries runs');
  list.dataset.keys = runs.map((run) => run.key).join('|');
  for (const run of runs) {
    list.append(runRow(run));
    if (run.entry) visibleEntries.push(run.entry);
  }
  box.append(list);
  container.append(box);
}

function selectEntry(entry, focusNote) {
  state.selected = { file: entry.file, line: entry.line, id: entry.id };
  state.selectedEntry = entry;
  state.runDetail = null;
  for (const li of document.querySelectorAll('li.entry.selected')) li.classList.remove('selected');
  const row = document.querySelector(
    `li.entry[data-file="${CSS.escape(entry.file)}"][data-line="${entry.line}"]`,
  );
  if (row) row.classList.add('selected');
  showDetail(entry, focusNote);
}

// One line about the run: the pane it is in, how long it has been going, the
// ticket it is on (if any) and the session it writes.
function runMeta(run) {
  const parts = ['pane ' + run.pane];
  if (run.started) parts.push(elapsed(run.started) + ' going');
  if (run.ticket) parts.push('ticket ' + run.ticket.slice(0, 8));
  else parts.push('no ticket');
  if (run.key && run.key !== run.ticket) parts.push(run.key);
  return parts.join('  ·  ');
}

// The detail pane's window on a run itself, from the Runs view: what the
// instance is doing, step by step, as it writes it. Works for a run that is on
// a ticket and for one that is not (the talking instance, a batch's
// orchestrator) -- the transcript is the run's own, and it is the same stream
// the entry's box follows. A ticket's title on the row still opens the entry;
// here its `ticket` button does.
function showRun(run) {
  stopRunStream();
  const detail = $('#detail');
  detail.hidden = false;
  document.body.classList.add('detail-open');
  detail.scrollTop = 0;
  state.detailEntry = { run: run.key };
  state.runDetail = run;
  // nothing of the list is selected while a run is on screen, so a reload
  // does not draw an entry over the run being watched
  state.selected = null;
  state.selectedEntry = null;
  for (const li of document.querySelectorAll('li.entry.selected')) li.classList.remove('selected');
  if (isPhone() && !state.historyOpen) {
    state.historyOpen = true;
    history.pushState({ orgDetail: true }, '');
  }
  detail.replaceChildren();

  const header = el('header');
  header.append(el('span', 'where', 'run · pane ' + run.pane));
  const actions = el('span');
  if (run.entry) {
    const ticket = el('button', '', 'ticket');
    ticket.type = 'button';
    ticket.title = 'open the entry this run is on';
    ticket.addEventListener('click', () => selectEntry(run.entry));
    actions.append(ticket);
  }
  // the way out of a run that is going nowhere, armed like the row's `✕`
  const cancel = el('button', 'kill', 'cancel');
  cancel.type = 'button';
  cancel.title = 'cancel this run: the pane goes, and the omp inside it';
  cancel.addEventListener('click', async () => {
    if (!cancel.dataset.armed) {
      cancel.dataset.armed = '1';
      cancel.textContent = 'cancel?';
      cancel.classList.add('armed');
      clearTimeout(cancel._disarm);
      cancel._disarm = setTimeout(() => {
        delete cancel.dataset.armed;
        cancel.textContent = 'cancel';
        cancel.classList.remove('armed');
      }, 4000);
      return;
    }
    await cancelRun(run);
    closeDetail();
  });
  const close = el('button', '', '✕');
  close.type = 'button';
  close.title = 'q  close';
  close.addEventListener('click', () => closeDetail());
  actions.append(cancel, close);
  header.append(actions);
  detail.append(header);

  const body = el('div', 'body');
  const title = el('h2', 'detail-title headline');
  title.append(el('span', 'title', run.title || run.key));
  const meta = el('p', 'run-meta', runMeta(run));
  body.append(title, meta);
  detail.append(body);
  appendRunLog(body, run.key, {});
}

async function showDetail(entry, focusNote) {
  state.runDetail = null;
  const detail = $('#detail');
  detail.hidden = false;
  document.body.classList.add('detail-open');
  // a pane that was scrolled for the last entry starts at the top for this
  // one, while a live update of the entry being read keeps its place
  const same =
    state.detailEntry && state.detailEntry.file === entry.file && state.detailEntry.line === entry.line;
  if (!same) detail.scrollTop = 0;
  state.detailEntry = { file: entry.file, line: entry.line };
  // the back button and the back gesture are how a phone leaves a screen:
  // open the entry as one, so either of them closes it
  if (isPhone() && !state.historyOpen) {
    state.historyOpen = true;
    history.pushState({ orgDetail: true }, '');
  }
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

function closeDetail(fromHistory) {
  state.selected = null;
  state.selectedEntry = null;
  state.detailEntry = null;
  state.runDetail = null;
  stopRunStream();
  $('#detail').hidden = true;
  document.body.classList.remove('detail-open');
  for (const li of document.querySelectorAll('li.entry.selected')) li.classList.remove('selected');
  if (state.historyOpen) {
    state.historyOpen = false;
    // the entry was opened as a history step; closing it by the button or `q`
    // takes that step back, so a later back press does not close nothing
    if (!fromHistory) history.back();
  }
  // an entry opened from the search leaves the search where it found it, so
  // the next ticket is one keystroke away rather than a fresh query
  if (!fromHistory && searchReturn) {
    searchReturn = false;
    openTicketSearch(true);
  }
}

// the phone's back button and back gesture land here
window.addEventListener('popstate', () => {
  if (state.historyOpen) closeDetail(true);
});

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
    showToast(
      res.launched
        ? 'note added, the ticket was launched'
        : res.delivered
          ? 'note added, sent to the running run'
          : 'note added'
    );
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
// question, and the answers it offered with their tradeoffs, the one it leans
// on marked. Clicking an answer answers the run: the server types it into the
// picker the run is standing on (`/api/answer`, helpers/org/web/picker.lua),
// which is the only door a waiting run has. A question that takes several
// answers toggles them and sends them together; the box under a question is
// for an answer of your own words.
//
// `settle` is for the log: once the run has its answer the card is history,
// and its controls stop taking clicks.
function askCard(ev, key) {
  const card = el('div', 'run-ask');
  const controls = [];
  const settle = () => {
    for (const node of controls) node.disabled = true;
    card.classList.add('settled');
  };
  const send = async (q, body, ...nodes) => {
    for (const node of nodes) node.disabled = true;
    card.classList.add('sending');
    const fail = (message) => {
      showToast(message);
      for (const node of nodes) node.disabled = false;
    };
    try {
      const res = await api('/api/answer', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ key, question: q.q, ...body }),
      });
      if (res && res.error) fail(res.error);
      else settle();
    } catch (err) {
      fail('nvim did not answer');
    }
    card.classList.remove('sending');
  };

  if (ev.t) card.append(el('p', 'run-ask-intent', ev.t));
  for (const q of ev.q || []) {
    const item = el('div', 'run-ask-item');
    if (q.h) item.append(el('span', 'run-ask-header', q.h));
    item.append(el('p', 'run-ask-text', q.q || ''));
    if (q.m) item.append(el('span', 'run-ask-any', 'pick any'));
    const chosen = new Set();
    let sendAll = null;
    const list = el('ol', 'run-ask-options');
    (q.o || []).forEach((opt, i) => {
      const row = el('li', 'run-ask-option' + (q.r === i ? ' recommended' : ''));
      const button = el('button', 'run-ask-pick');
      button.type = 'button';
      button.append(el('span', 'run-ask-label', opt.l || ''));
      if (opt.d) button.append(el('span', 'run-ask-desc', opt.d));
      button.addEventListener('click', () => {
        if (!q.m) {
          send(q, { label: opt.l || '' }, button);
          return;
        }
        if (chosen.has(i)) chosen.delete(i);
        else chosen.add(i);
        row.classList.toggle('chosen', chosen.has(i));
        if (sendAll) sendAll.disabled = chosen.size === 0;
      });
      row.append(button);
      list.append(row);
      controls.push(button);
    });
    item.append(list);
    if (q.m) {
      sendAll = el('button', 'primary run-ask-send', 'send these');
      sendAll.type = 'button';
      sendAll.disabled = true;
      sendAll.addEventListener('click', () => {
        const labels = (q.o || []).filter((_, i) => chosen.has(i)).map((opt) => opt.l || '');
        send(q, { labels }, ...controls);
      });
      item.append(sendAll);
      controls.push(sendAll);
    }
    const say = el('div', 'run-ask-say');
    const words = document.createElement('input');
    words.type = 'text';
    words.placeholder = 'answer in your own words';
    words.autocomplete = 'off';
    const sayGo = el('button', '', 'say it');
    sayGo.type = 'button';
    const go = () => {
      const text = words.value.trim();
      if (!text) {
        words.focus();
        return;
      }
      send(q, { custom: text }, ...controls);
    };
    sayGo.addEventListener('click', go);
    words.addEventListener('keydown', (ev2) => {
      if (ev2.key === 'Enter') {
        ev2.preventDefault();
        go();
      }
    });
    say.append(words, sayGo);
    item.append(say);
    controls.push(words, sayGo);
    card.append(item);
  }
  return { card, settle };
}

// One event of the run, drawn as what it is: the agent speaking, a step of
// thought, a tool it reached for, what the tool answered, and your answer to
// what it asked. (A question is a turn of yours, not a line of the log: the
// log draws it itself, `draw`.)
function runEvent(ev) {
  if (ev.k === 'say') return el('p', 'run-say', ev.t);
  if (ev.k === 'think') return el('p', 'run-think', ev.t);
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
  const key = entry.session || (entry.id && state.live.tickets.has(entry.id) ? entry.id : null);
  if (!key) return;
  appendRunLog(body, key, { hide: true });
}

// One run's live log, drawn in `body` and followed over the stream the server
// keeps open on its key -- a ticket's :ID:, or a batch's session key (the
// talking instance's `talk/one`). A `hide` button takes the box away without
// leaving the pane; without it the box is the pane.
function appendRunLog(body, key, opts) {
  opts = opts || {};
  stopRunStream();

  const box = el('div', 'run-box');
  const head = el('div', 'run-head');
  const stateText = el('span', 'run-state', 'connecting…');
  const title = el('span', 'run-title', '');
  head.append(el('span', 'live-dot', '●'), stateText, title);
  const hide = opts.hide ? el('button', '', 'hide') : null;
  if (hide) {
    hide.type = 'button';
    head.append(hide);
  }
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
  let openAsk = null;
  const paint = () => {
    box.classList.toggle('running', running);
    box.classList.toggle('asking', asking);
    stateText.textContent = asking ? 'asking you' : running ? 'live' : 'stopped';
  };
  const settleAsk = () => {
    if (openAsk) openAsk.settle();
    openAsk = null;
  };
  const draw = (events, wasStuck) => {
    for (const ev of events || []) {
      if (ev.k === 'ask') {
        settleAsk();
        openAsk = askCard(ev, key);
        log.append(openAsk.card);
        asking = true;
      } else {
        const node = runEvent(ev);
        if (node) log.append(node);
        if (ev.k === 'answer') {
          settleAsk();
          asking = false;
        }
      }
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
    openAsk = null;
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
    openAsk = null;
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

  if (hide) {
    hide.addEventListener('click', () => {
      stopRunStream();
      box.remove();
    });
  }
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
  // near the edge of a narrow screen the menu would open off the page: the
  // width is known once it is in the document, so place it again after that
  const box = menu.getBoundingClientRect();
  const left = Math.max(8, Math.min(rect.left, innerWidth - box.width - 8));
  const below = rect.bottom + 4;
  const top =
    below + box.height > innerHeight - 8 ? Math.max(8, rect.top - box.height - 4) : below;
  menu.style.left = left + 'px';
  menu.style.top = top + 'px';
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

// The two buttons a row carries, the pair a rendered headline carries in the
// pane and on the `O` page: `✓` closes the ticket in one click and `↺` opens
// it again, `✕` deletes it after a second click that says what it will do.
// Drawn here rather than in the exported document, so a ticket is finished or
// dropped from the list itself, without opening it first.
function rowActs(entry) {
  const lists = (state.data && state.data.keywords) || { open: ['TODO'], done: ['DONE'] };
  const open = lists.open[0] || 'TODO';
  const done = lists.done[0] || 'DONE';
  const closed = (lists.done || []).includes(entry.todo);

  const acts = el('span', 'row-acts');

  const flip = el('button', 'flip' + (closed ? ' closed' : ''), closed ? '↺' : '✓');
  flip.type = 'button';
  flip.title = closed ? 'back to ' + open : 'mark ' + done;
  flip.addEventListener('click', (ev) => {
    ev.stopPropagation();
    setState(entry, closed ? open : done);
  });

  const kill = el('button', 'kill', '✕');
  kill.type = 'button';
  kill.title = 'delete this ticket and everything under it';
  kill.addEventListener('click', (ev) => {
    ev.stopPropagation();
    if (!kill.dataset.armed) {
      kill.dataset.armed = '1';
      kill.textContent = 'delete?';
      kill.classList.add('armed');
      clearTimeout(kill._disarm);
      kill._disarm = setTimeout(() => {
        delete kill.dataset.armed;
        kill.textContent = '✕';
        kill.classList.remove('armed');
      }, 4000);
      return;
    }
    removeEntry(entry);
  });

  acts.append(flip, kill);
  return acts;
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
  showToast(jump ? 'jumping to the run' : 'starting a run on it');
  if (jump) return;
  // the pane the launcher opens is what turns the row's button into "jump",
  // and only a look at /api/live can say it is there: look again while it
  // lands, a few times over the first seconds
  for (const wait of [1000, 3000, 6000]) setTimeout(pollLive, wait);
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

// ---- search every ticket ------------------------------------------------
//
// The rail, the tabs and the filter all narrow what is on screen, and a
// ticket from another project is a rail click and a scroll away. Ctrl-P is
// the way out of that: one box over every ticket of the vault -- whichever
// project, whichever state, closed ones too -- and the one picked opens on
// its own screen. It is the key a file finder takes in a terminal, so it is
// the key the board gives it; the browser's print dialog is what it replaces.

// the entry on screen was opened from the search: closing it goes back
let searchReturn = false;
// what was typed: coming back from a ticket the search opened keeps the query,
// so the next match is one Enter away. A fresh <C-p> never does -- it starts
// the box empty, over every ticket.
let searchQuery = '';

// open tickets first, in the order a run looks at them, then the closed ones
const SEARCH_RANK = { NEXT: 0, TEST: 1, WARN: 2, PEND: 3, TODO: 4 };
const SEARCH_LIMIT = 200;

function searchHits(query) {
  const all = (state.data && state.data.tickets) || [];
  const hits = all.filter((entry) => matchesQuery(entry, query));
  hits.sort((a, b) => {
    const done = (a.done ? 1 : 0) - (b.done ? 1 : 0);
    if (done) return done;
    const rank = (SEARCH_RANK[a.todo] ?? 5) - (SEARCH_RANK[b.todo] ?? 5);
    if (rank) return rank;
    return (a.title || '').localeCompare(b.title || '');
  });
  return hits;
}

function searchRow(entry) {
  const li = el('li', entry.done ? 'done-entry' : '');
  li.append(el('span', 'state ' + (entry.todo || ''), entry.todo || '—'));
  const title = el('span', 'title', entry.title || '');
  if (entry.cookie) title.append(el('span', 'cookie', ' ' + entry.cookie));
  li.append(title);
  const base = ((entry.rel || '').split('/').pop() || '').replace(/\.org$/, '').toLowerCase();
  const tags = el('span', 'tags');
  for (const tag of entry.tags || []) {
    const lower = tag.toLowerCase();
    if (lower === base || lower === (entry.project || '').toLowerCase()) continue;
    tags.append(el('span', '', tag));
  }
  li.append(tags);
  li.append(el('span', 'project', entry.project || ''));
  li._entry = entry;
  li.addEventListener('click', () => chooseSearch(entry));
  return li;
}

function paintSearch(query) {
  const box = $('#tsearch');
  if (!box) return;
  const list = box.querySelector('.results');
  const hits = searchHits(query);
  list.replaceChildren();
  for (const entry of hits.slice(0, SEARCH_LIMIT)) list.append(searchRow(entry));
  if (hits.length === 0) list.append(el('li', 'none', 'No ticket matches that.'));
  else if (hits.length > SEARCH_LIMIT) {
    list.append(el('li', 'none', `and ${hits.length - SEARCH_LIMIT} more: type to narrow`));
  }
  list.firstElementChild?.classList.add('sel');
}

function moveSearch(delta) {
  const list = $('#tsearch .results');
  if (!list) return;
  const rows = [...list.children].filter((li) => li._entry);
  if (!rows.length) return;
  const at = rows.findIndex((li) => li.classList.contains('sel'));
  const next = at === -1 ? (delta > 0 ? 0 : rows.length - 1) : Math.min(Math.max(at + delta, 0), rows.length - 1);
  for (const li of rows) li.classList.remove('sel');
  rows[next].classList.add('sel');
  rows[next].scrollIntoView({ block: 'nearest' });
}

function chooseSearch(entry) {
  $('#tsearch')?.remove();
  searchReturn = true;
  selectEntry(entry);
}

// A press of <C-p> always starts the box empty; only the way back from a
// ticket the search opened (`keep`) brings the query along.
function openTicketSearch(keep) {
  const open = $('#tsearch');
  if (open) {
    // <C-p> again starts the search over: the box left open keeps what was
    // typed for the ticket it sent you to, not for the next press
    const input = open.querySelector('input');
    if (input.value) {
      input.value = '';
      searchQuery = '';
      paintSearch('');
    }
    input.focus();
    return;
  }
  closeMenus();
  closePrompt();
  const box = el('div');
  box.id = 'tsearch';
  const panel = el('div', 'panel');
  const input = document.createElement('input');
  input.type = 'text';
  input.placeholder = 'Search every ticket';
  input.setAttribute('autocomplete', 'off');
  input.setAttribute('aria-label', 'Search every ticket');
  input.spellcheck = false;
  const list = el('ul', 'results');
  panel.append(input, list, el('p', 'hint', '↑ ↓ move · Enter open · C-p clear · Esc close'));
  box.append(panel);
  document.body.append(box);
  input.addEventListener('input', () => {
    searchQuery = input.value;
    paintSearch(searchQuery);
  });
  input.addEventListener('keydown', (ev) => {
    if (ev.key === 'Escape') {
      ev.preventDefault();
      closeTicketSearch();
    } else if (ev.key === 'Enter') {
      ev.preventDefault();
      const row = list.querySelector('li.sel');
      if (row && row._entry) chooseSearch(row._entry);
    } else if (ev.key === 'ArrowDown' || ev.key === 'Tab' || (ev.ctrlKey && ev.key === 'n')) {
      ev.preventDefault();
      moveSearch(ev.shiftKey ? -1 : 1);
    } else if (ev.key === 'ArrowUp') {
      ev.preventDefault();
      moveSearch(-1);
    } else if (ev.ctrlKey && ev.key === 'p') {
      // <C-p> again starts over: the query goes and every ticket comes back,
      // wherever the box is handed to you
      ev.preventDefault();
      input.value = '';
      searchQuery = '';
      paintSearch('');
    }
  });
  box.addEventListener('mousedown', (ev) => {
    if (ev.target === box) closeTicketSearch();
  });
  searchQuery = keep ? searchQuery : '';
  input.value = searchQuery;
  paintSearch(searchQuery);
  input.focus();
}

function closeTicketSearch() {
  $('#tsearch')?.remove();
  searchReturn = false;
  searchQuery = '';
}

// ---- the keymap ---------------------------------------------------------

// The list reads like the TODO view in nvim: j/k and the half page, gg/G,
// <Tab> to fold an entry, D/T/N/u on the entry at point, dd to delete it,
// `i` to edit its text here, `o` to open it in the editor, and <Space> for
// the leader, where `o` + the view key switches views (ow, oa, oo, of, og, op,
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
  ['<C-p>', 'search every ticket of the vault'],
  ['<Space>ow / oa / oo / of / og / op / oy', 'board / agenda / open / in flight / by state / priorities / wayfinder'],
  ['<Space>ai / <Space>aj', 'launch a run on the entry / jump to it'],
  ['the run button on a row', 'start a run on that ticket; jump goes to the run it has'],
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
  a: 'agenda',
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
      // the graph is drawn once and dimmed in place: refiltering it would
      // throw the layout away for nothing
      if (state.view === 'graph') OrgGraph.filter('');
      else renderViews();
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
  // every ticket of the vault, whatever the rail and the tab are showing
  if (ctrl && (key === 'p' || key === 'P')) {
    ev.preventDefault();
    openTicketSearch();
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

// A rendered ticket in the detail pane closed itself with `✓`, or was deleted
// with `✕` (assets/org-actions.js). The board is drawn again, and `reload`
// draws the pane over the entry as the file now has it; a ticket that is gone
// takes the pane with it.
document.addEventListener('org:reload', async (ev) => {
  if (ev.detail && ev.detail.entry) closeDetail();
  await reload();
});

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
  if (state.view === 'graph') OrgGraph.filter(state.query);
  else renderViews();
});

// ---- phone door ---------------------------------------------------------

// The tunnel's address and the QR of it. It starts beside the server, so the
// first fetch usually has it; while the agent is still coming up the page asks
// again instead of showing nothing.
let shareTimer = null;

function renderShare(share) {
  const card = $('#share');
  if (!card) return;
  card.hidden = false;
  const label = $('#share-label');
  const body = $('#share-body');
  const note = $('#share-note');
  const link = $('#share-url');

  if (shareTimer) {
    clearInterval(shareTimer);
    shareTimer = null;
  }

  const qrBox = $('#share-qr');
  const power = $('#share-off');

  if (share.status === 'up' && share.url) {
    label.textContent = '◲ phone ready';
    card.classList.add('on');
    // a new tunnel comes with a new address, and its code has to follow it
    if (share.qr && qrBox.dataset.url !== share.url) {
      qrBox.innerHTML = share.qr;
      qrBox.dataset.url = share.url;
    }
    link.href = share.url;
    link.textContent = share.url.replace(/^https?:\/\//, '');
    note.textContent = 'Scan with your phone camera, or open the link.';
    power.textContent = 'stop';
    body.hidden = false;
    // the address changes when the tunnel has to be made again, so the code
    // on screen follows it instead of waiting for the card to be reopened
    shareTimer = setInterval(loadShare, 10000);
    return;
  }

  card.classList.remove('on');
  label.textContent = '◲ phone';
  body.hidden = false;
  power.textContent = 'share';
  qrBox.replaceChildren();
  delete qrBox.dataset.url;
  link.removeAttribute('href');
  link.textContent = '';
  if (share.status === 'starting') {
    note.textContent = share.error
      ? 'putting a public address up… (' + share.error + ')'
      : 'putting a public address up…';
    shareTimer = setInterval(loadShare, 1200);
  } else if (share.status === 'error') {
    note.textContent = 'no public address: ' + (share.error || 'ngrok failed');
    // the agent is brought back on its own while the door is wanted; a page
    // left open follows it instead of staying on the error
    shareTimer = setInterval(loadShare, 6000);
  } else {
    note.textContent = 'sharing is off';
  }
}

async function loadShare() {
  try {
    renderShare(await api('/api/share'));
  } catch (err) {
    console.error(err);
  }
}

$('#share-toggle').addEventListener('click', () => {
  $('#share').classList.toggle('open');
  if ($('#share').classList.contains('open')) loadShare();
});

$('#share-copy').addEventListener('click', async () => {
  const link = $('#share-url');
  if (!link.href) return;
  await copyText(link.href);
  showToast('link copied');
});

// The one switch: stop the tunnel while it is up, put it back when it is not.
$('#share-off').addEventListener('click', async () => {
  const up = $('#share').classList.contains('on');
  try {
    renderShare(await api('/api/share', { method: 'POST', body: JSON.stringify({ on: !up }) }));
    showToast(up ? 'phone door closed' : 'putting a public address up…');
  } catch (err) {
    showToast('could not reach nvim');
  }
});

// ---- live reload --------------------------------------------------------

// `change` is the vault; `reload` is the site's own files, an asset or a
// renderer module edited while the page is open. The page loads itself again
// and the asset it asks for next is the new one -- unless it is holding work
// only the page has, which a reload would throw away.
function busy() {
  if (document.querySelector('.editor')) return true;
  const voice = document.querySelector('#jarvis');
  if (voice && /phase-(speaking|listening|thinking|review)/.test(voice.className)) return true;
  const field = document.querySelector('textarea');
  return !!(field && field.value.trim());
}

const live = new EventSource('/events');
live.addEventListener('change', debounce(async () => {
  await load();
  refreshSelection();
}, 200));
live.addEventListener('reload', () => {
  if (!busy()) location.reload();
});
// A phone puts the page away -- the screen locks, another app comes forward --
// and the stream dies with it, then reconnects by itself. Whatever the site
// was edited to while the page was away is only in the file now, so the page
// that comes back loads itself again rather than show yesterday's code.
let dropped = false;
live.addEventListener('open', () => {
  $('#live').classList.add('on');
  const missed = dropped;
  dropped = false;
  if (missed && !busy()) location.reload();
});
live.addEventListener('error', () => {
  dropped = true;
  $('#live').classList.remove('on');
});

load();
loadShare();
