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
    render();
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

function selectEntry(entry) {
  state.selected = { file: entry.file, line: entry.line, id: entry.id };
  for (const li of document.querySelectorAll('li.entry.selected')) li.classList.remove('selected');
  const row = document.querySelector(
    `li.entry[data-file="${CSS.escape(entry.file)}"][data-line="${entry.line}"]`,
  );
  if (row) row.classList.add('selected');
  showDetail(entry);
}

async function showDetail(entry) {
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
    const title = el('h2', 'detail-title');
    if (entry.todo) title.append(el('span', (entry.done ? 'done ' : 'todo ') + entry.todo, entry.todo));
    if (entry.priority) title.append(el('span', 'priority', '[#' + entry.priority + '] '));
    title.append(document.createTextNode(entry.title));
    if (entry.cookie) title.append(el('span', 'cookie', ' ' + entry.cookie));
    const tags = el('span', 'tag');
    for (const tag of entry.tags || []) tags.append(el('span', '', tag));
    if ((entry.tags || []).length) title.append(tags);
    const org = el('div', 'org');
    org.innerHTML = res.html || '<p class="empty">No body.</p>';
    body.append(title, org);
  } catch (err) {
    body.replaceChildren(el('p', 'empty', 'Could not render the entry.'));
  }
}

function closeDetail() {
  state.selected = null;
  $('#detail').hidden = true;
  document.body.classList.remove('detail-open');
  for (const li of document.querySelectorAll('li.entry.selected')) li.classList.remove('selected');
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

async function setTags(entry) {
  if (!entry) return;
  const current = (entry.tags || []).join(' ');
  const typed = window.prompt(`Tags of "${entry.title}"`, current);
  if (typed === null) return;
  const tags = typed.split(/[\s,]+/).filter(Boolean);
  const res = await post('/api/tags', entry, { tags });
  if (res && !res.error) await reload();
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

async function editEntry(entry, opts) {
  if (!entry) return;
  opts = opts || {};
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
    let lines = res.text.lines.slice();
    if (opts.child) {
      // `c` in the view: a new child headline under the entry, typed where
      // the capture would leave the cursor
      const stars = '*'.repeat((res.text.level || entry.level || 1) + 1);
      lines = lines.concat(['', stars + ' TODO ']);
    }
    OrgEditor.open({
      file: entry.file,
      id: entry.id,
      line: res.text.start,
      start: res.text.start,
      text: lines.join('\n'),
      where: '~/' + entry.rel + ':' + res.text.start,
      insertAtEnd: !!opts.child,
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
  ['c', 'capture a child of the entry here'],
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
    if (key === 'Escape') {
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
    resetKeys();
    return;
  }
  if (state.pending === ' o') {
    const view = VIEW_KEYS[key];
    resetKeys();
    if (view) setView(view);
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
    case 'c':
      editEntry(entry, { child: true });
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
