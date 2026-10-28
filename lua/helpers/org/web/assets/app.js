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
    drawn += items.length;
    const box = el('section', 'view-section' + (section.rule ? ' rule' : ''));
    const head = el('h2');
    head.append(el('span', '', (section.icon ? section.icon + ' ' : '') + section.title));
    head.append(el('span', 'n', String(items.length)));
    if (section.note) head.append(el('span', 'note', section.note));
    box.append(head);
    const list = el('ul', 'entries');
    for (const entry of items) {
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
  const open = el('button', '', 'open in editor');
  open.title = 'Reveal the entry in nvim';
  open.addEventListener('click', () => post('/api/open', entry));
  const close = el('button', '', '✕');
  close.addEventListener('click', () => closeDetail());
  actions.append(open, close);
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

function openStateMenu(anchor, entry) {
  document.querySelectorAll('#menu').forEach((m) => m.remove());
  const menu = el('div');
  menu.id = 'menu';
  const rect = anchor.getBoundingClientRect();
  menu.style.left = rect.left + 'px';
  menu.style.top = rect.bottom + 4 + 'px';
  const keywords = state.data.keywords || { open: ['TODO'], done: ['DONE'] };
  const states = [...keywords.open, ...keywords.done];
  for (const kw of states) {
    if (kw === entry.todo) continue;
    const btn = el('button', kw, kw);
    btn.addEventListener('click', async () => {
      menu.remove();
      const res = await post('/api/state', entry, { state: kw });
      if (res && !res.error) {
        showToast(res.warning || `${entry.title} → ${res.state || kw}`);
        await load();
        refreshSelection();
      }
    });
    menu.append(btn);
  }
  const clear = el('button', '', 'no keyword');
  clear.addEventListener('click', async () => {
    menu.remove();
    const res = await post('/api/state', entry, { state: '' });
    if (res && !res.error) {
      await load();
      refreshSelection();
    }
  });
  menu.append(clear);
  document.body.append(menu);
  const off = (ev) => {
    if (!menu.contains(ev.target)) {
      menu.remove();
      document.removeEventListener('mousedown', off);
    }
  };
  setTimeout(() => document.addEventListener('mousedown', off), 0);
}

// ---- filter -------------------------------------------------------------

$('#search').addEventListener('input', (ev) => {
  state.query = ev.target.value;
  renderViews();
});

// ---- keys ---------------------------------------------------------------

document.addEventListener('keydown', (ev) => {
  const typing = ev.target === $('#search');
  if (typing && ev.key !== 'Escape') return;
  if (ev.key === '/') {
    ev.preventDefault();
    $('#search').focus();
    return;
  }
  if (ev.key === 'Escape') {
    if (typing) {
      $('#search').value = '';
      state.query = '';
      $('#search').blur();
      renderViews();
    } else {
      closeDetail();
    }
    return;
  }
  if (ev.key === 'j' || ev.key === 'ArrowDown') {
    ev.preventDefault();
    move(1);
    return;
  }
  if (ev.key === 'k' || ev.key === 'ArrowUp') {
    ev.preventDefault();
    move(-1);
    return;
  }
  if (ev.key === 'Enter' && visibleEntries.length) {
    ev.preventDefault();
    const entry = visibleEntries[currentIndex()];
    if (entry) {
      selectEntry(entry);
      document.querySelector('li.entry.selected')?.scrollIntoView({ block: 'nearest' });
    }
    return;
  }
  const idx = currentIndex();
  const entry = visibleEntries[idx];
  if (!entry) return;
  if (ev.key === 'd') {
    ev.preventDefault();
    const target = entry.done ? 'TODO' : 'DONE';
    post('/api/state', entry, { state: target }).then(async (res) => {
      if (res && !res.error) {
        showToast(res.warning || `${entry.title} → ${target}`);
        await load();
        refreshSelection();
      }
    });
  } else if (ev.key === 'o') {
    ev.preventDefault();
    post('/api/open', entry);
  } else if (/^[1-6]$/.test(ev.key)) {
    const view = state.data.views[Number(ev.key) - 1];
    if (view) {
      state.view = view.key;
      renderTabs();
      renderViews();
    }
  }
});

function currentIndex() {
  const rows = [...document.querySelectorAll('li.entry')];
  const selected = document.querySelector('li.entry.selected');
  return Math.max(0, rows.indexOf(selected));
}

function move(delta) {
  if (!visibleEntries.length) return;
  const rows = [...document.querySelectorAll('li.entry')];
  const selected = document.querySelector('li.entry.selected');
  let idx = rows.indexOf(selected);
  idx = idx === -1 ? (delta > 0 ? 0 : rows.length - 1) : idx + delta;
  idx = Math.max(0, Math.min(rows.length - 1, idx));
  const entry = visibleEntries[idx];
  if (!entry) return;
  selectEntry(entry);
  document.querySelector('li.entry.selected')?.scrollIntoView({ block: 'nearest' });
}

// ---- live reload --------------------------------------------------------

const live = new EventSource('/events');
live.addEventListener('change', debounce(async () => {
  await load();
  refreshSelection();
}, 200));
live.addEventListener('open', () => $('#live').classList.add('on'));
live.addEventListener('error', () => $('#live').classList.remove('on'));

load();
