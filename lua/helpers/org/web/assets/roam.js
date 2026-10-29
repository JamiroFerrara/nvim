// The roam mode's client: the note rail, one rendered note, and the graph of
// the links between notes. The notes and links come from /api/roam (the
// plugin's own roam index, in Lua); a note's body is the org HTML export with
// its `id:` links pointed back at this page (/api/roam/note). Routes are the
// hash: #n=<id> a note, #g the whole graph, #g=<id> the graph around a note.

const state = {
  data: null,
  query: '',
  token: 0, // which pane fill is current: a slower one must not win
};

const $ = (sel) => document.querySelector(sel);

const el = (tag, cls, text) => {
  const node = document.createElement(tag);
  if (cls) node.className = cls;
  if (text !== undefined && text !== null) node.textContent = text;
  return node;
};

async function api(path, opts) {
  const res = await fetch(path, opts);
  if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
  return res.json();
}

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

function debounce(fn, ms) {
  let t;
  return (...args) => {
    clearTimeout(t);
    t = setTimeout(() => fn(...args), ms);
  };
}

// ---- routes --------------------------------------------------------------

function route() {
  const hash = location.hash.replace(/^#/, '');
  if (hash.startsWith('n=')) return { kind: 'note', id: hash.slice(2) };
  if (hash === 'g') return { kind: 'graph', id: null };
  if (hash.startsWith('g=')) return { kind: 'graph', id: hash.slice(2) };
  if (hash === '') return { kind: 'graph', id: null };
  return null; // an in-page anchor (#org…), not a route
}

function go(hash) {
  if (location.hash === '#' + hash) render();
  else location.hash = hash;
}

function renderTabs(current) {
  const context = current.kind === 'note' ? current.id : current.kind === 'graph' ? current.id : null;
  const graph = $('#tab-graph');
  graph.classList.toggle('active', current.kind === 'graph' && !current.id);
  graph.onclick = () => go('g');
  const local = $('#tab-local');
  local.hidden = !context;
  local.classList.toggle('active', current.kind === 'graph' && !!current.id);
  local.onclick = context ? () => go('g=' + context) : null;
}

// ---- the rail ------------------------------------------------------------

function matches(note) {
  const q = state.query.trim().toLowerCase();
  if (!q) return true;
  const haystack = [note.title, note.rel, ...(note.aliases || []), ...(note.tags || [])]
    .join(' ')
    .toLowerCase();
  return q.split(/\s+/).every((word) => haystack.includes(word));
}

// The folder under the roam directory: topics, people, documentation… the
// way the notes were filed, which is what the rail groups by.
function groupOf(note) {
  const rel = note.rel.replace(/^.*?\/?roam\//, '');
  const parts = rel.split('/');
  if (parts.length < 2) return 'Roam';
  const name = parts[0].replace(/[-_]/g, ' ');
  return name.charAt(0).toUpperCase() + name.slice(1);
}

// ---- the drawer ----------------------------------------------------------

// On a phone the rail is a drawer behind the burger in the top bar; on a wide
// screen the stylesheet keeps the rail in place and the class does nothing.
const railToggle = $('#rail-toggle');
const railOpen = () => document.body.classList.contains('rail-open');

function setRail(open) {
  document.body.classList.toggle('rail-open', open);
  railToggle.setAttribute('aria-expanded', String(open));
}

function renderRail(current) {
  const nav = $('#notes');
  nav.replaceChildren();
  const notes = (state.data?.notes || []).filter(matches);
  const groups = new Map();
  const titles = new Map();
  for (const note of notes) {
    const name = groupOf(note);
    if (!groups.has(name)) groups.set(name, []);
    groups.get(name).push(note);
    titles.set(note.title, (titles.get(note.title) || 0) + 1);
  }
  for (const name of [...groups.keys()].sort()) {
    nav.append(el('div', 'group', name));
    for (const note of groups.get(name)) {
      const btn = el('button', note.id === current?.id ? 'active' : '');
      btn.append(el('span', 'title', note.title));
      // two notes can share a title (a file and a headline in it), so a
      // repeated title names the file it lives in
      const where = titles.get(note.title) > 1 ? note.rel.replace(/^.*roam\//, '') : '';
      const hint = [note.backlinks ? `${note.backlinks}←` : '', note.tags?.length ? note.tags.join(' ') : '', where]
        .filter(Boolean)
        .join('  ');
      btn.append(el('span', 'hint', hint || note.rel.replace(/^.*roam\//, '')));
      btn.title = note.rel;
      btn.addEventListener('click', () => {
        go('n=' + note.id);
        setRail(false); // a phone: the note picked is the page now
      });
      nav.append(btn);
    }
  }
  if (notes.length === 0) {
    nav.append(el('div', 'group', state.data?.available ? 'No note matches' : 'org-roam is not configured'));
  }
  const stats = $('#stats');
  stats.replaceChildren();
  if (state.data?.available) {
    stats.append(el('span', '', `${state.data.stats.nodes} notes`));
    stats.append(el('span', '', `${state.data.stats.links} links`));
  }
}

// ---- one note ------------------------------------------------------------

function relPath(note) {
  return note.rel + (note.level > 0 ? ':' + note.lnum : '');
}

function linkList(title, notes) {
  const box = el('section', 'backlinks');
  box.append(el('h2', '', `${title} (${notes.length})`));
  const list = el('ul');
  for (const item of notes) {
    const li = el('li');
    const anchor = el('a', '', item.title);
    anchor.href = '#n=' + item.id;
    li.append(anchor);
    li.append(el('span', 'rel', item.rel.replace(/^.*roam\//, '')));
    list.append(li);
  }
  box.append(list);
  return box;
}

async function showNote(id) {
  const pane = $('#pane');
  pane.classList.add('scroll');
  pane.replaceChildren(el('p', 'empty', 'Loading…'));
  const token = ++state.token;
  let res;
  try {
    res = await api('/api/roam/note?id=' + encodeURIComponent(id));
  } catch (err) {
    if (token === state.token) pane.replaceChildren(el('p', 'empty', 'Could not read this note: ' + err.message));
    return;
  }
  if (token !== state.token) return;
  pane.replaceChildren();
  if (!res.note) {
    pane.append(el('p', 'empty', res.error || 'No such note.'));
    return;
  }
  const note = res.note;
  const article = el('article', 'note');
  const header = el('header');
  if (note.olp?.length) header.append(el('div', 'crumbs', note.olp.join(' / ')));
  header.append(el('h1', '', note.title));
  const meta = el('div', 'meta');
  meta.append(el('span', 'path', relPath(note)));
  for (const tag of note.tags || []) meta.append(el('span', 'tag', tag));
  const actions = el('span', 'actions');
  const local = el('button', '', '◎ graph');
  local.title = 'The graph around this note';
  local.addEventListener('click', () => go('g=' + note.id));
  const edit = el('button', '', 'edit');
  edit.title = 'Open this note in nvim';
  edit.addEventListener('click', async () => {
    try {
      await api('/api/open', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ file: note.file, line: note.lnum }),
      });
      showToast('Opened in nvim');
    } catch (err) {
      showToast('Could not open it in nvim');
    }
  });
  actions.append(local, edit);
  meta.append(actions);
  header.append(meta);
  article.append(header);

  const body = el('div', 'org body');
  body.innerHTML = note.html || '<p class="empty">This note has no body.</p>';
  // an anchor to a headline of this same note scrolls; every other hash is a
  // route and the browser already handles it
  for (const anchor of body.querySelectorAll('a[href^="#org"]')) {
    anchor.addEventListener('click', (ev) => {
      const target = document.getElementById(anchor.getAttribute('href').slice(1));
      if (target) {
        ev.preventDefault();
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    });
  }
  article.append(body);
  if (note.outbound?.length) article.append(linkList('Links to', note.outbound));
  if (note.backlinks?.length) article.append(linkList('Linked from', note.backlinks));
  pane.append(article);
  pane.scrollTop = 0;
}

// ---- the graph -----------------------------------------------------------

function adjacents(links) {
  const adj = new Map();
  for (const link of links) {
    if (!adj.has(link.source)) adj.set(link.source, []);
    if (!adj.has(link.target)) adj.set(link.target, []);
    adj.get(link.source).push(link.target);
    adj.get(link.target).push(link.source);
  }
  return adj;
}

// The notes within `distance` links of `id`, both ways, the way obsidian's
// local graph reads: the note and its neighbourhood, not just what it points at.
function neighbourhood(links, id, distance) {
  if (!id) return null;
  const adj = adjacents(links);
  const keep = new Set([id]);
  let frontier = [id];
  for (let step = 0; step < distance && frontier.length; step++) {
    const next = [];
    for (const node of frontier) {
      for (const other of adj.get(node) || []) {
        if (!keep.has(other)) {
          keep.add(other);
          next.push(other);
        }
      }
    }
    frontier = next;
  }
  return keep;
}

// The notes the page draws as a graph: all of them, or the ones within two
// links of `focusId`. The layout and the gestures are the shared engine's
// (assets/graph.js); what a note is, this page's.
function drawGraph(focusId) {
  // a note still loading must not land on top of the graph: the graph wins
  // the pane whenever it is asked for
  state.token++;
  const pane = $('#pane');
  pane.classList.remove('scroll');
  pane.replaceChildren();
  const data = state.data;
  if (!data?.available) {
    pane.append(el('p', 'empty', 'org-roam is not configured, or its index is empty.'));
    return;
  }
  const keep = neighbourhood(data.links, focusId, 2);
  const notes = keep ? data.notes.filter((note) => keep.has(note.id)) : data.notes;
  const ids = new Set(notes.map((note) => note.id));
  const links = data.links.filter((link) => ids.has(link.source) && ids.has(link.target));
  const byNote = new Map(notes.map((note) => [note.id, note]));
  OrgGraph.draw(pane, {
    nodes: notes.map((note) => ({ id: note.id, title: note.title })),
    edges: links,
    here: focusId,
    hud: [
      `${notes.length} notes · ${links.length} links`,
      focusId ? 'local graph · 2 links out' : 'click a note · drag to pan · scroll to zoom',
    ],
    query: state.query,
    open: (node) => go('n=' + node.id),
    tip: (node) => {
      const note = byNote.get(node.id);
      return note ? `${node.title} — ${note.backlinks} in, ${note.links} out` : node.title;
    },
  });
}

// ---- the shell -----------------------------------------------------------

function render() {
  const current = route();
  if (!current) return; // an in-page anchor: leave the note where it is
  renderTabs(current);
  renderRail(current);
  if (current.kind === 'note') showNote(current.id);
  else drawGraph(current.id);
}

async function load() {
  try {
    const data = await api('/api/roam');
    // the vault saves constantly, and most of it is not a note: redraw the
    // graph only when the notes or their links actually changed, so a
    // sibling's save does not set the picture moving again
    const same = state.data && JSON.stringify(data) === JSON.stringify(state.data);
    state.data = data;
    if (same && route()?.kind === 'graph') {
      renderTabs(route());
      renderRail(route());
      $('#live').classList.add('on');
      setTimeout(() => $('#live').classList.remove('on'), 900);
      return;
    }
    render();
    $('#live').classList.add('on');
    setTimeout(() => $('#live').classList.remove('on'), 900);
  } catch (err) {
    console.error(err);
    showToast('Could not read the roam index');
  }
}

window.addEventListener('hashchange', render);

railToggle.addEventListener('click', () => setRail(!railOpen()));
$('#scrim').addEventListener('click', () => setRail(false));

$('#search').addEventListener('input', (ev) => {
  state.query = ev.target.value;
  const current = route();
  renderRail(current || { kind: 'graph', id: null });
  OrgGraph.filter(state.query);
});

document.addEventListener('keydown', (ev) => {
  if (ev.metaKey || ev.ctrlKey || ev.altKey) return;
  const typing = /^(INPUT|TEXTAREA)$/.test(ev.target.tagName);
  if (ev.key === '/' && !typing) {
    ev.preventDefault();
    $('#search').focus();
    $('#search').select();
  } else if (ev.key === 'Escape' && typing) {
    ev.target.blur();
  } else if (ev.key === 'Escape' && railOpen()) {
    setRail(false);
  } else if ((ev.key === 'g' || ev.key === 'G') && !typing) {
    const current = route();
    if (current?.kind === 'note') go('g=' + current.id);
    else if (current?.kind === 'graph' && current.id) go('g');
  }
});

// The vault follows the page: one save, one re-read, the note or the graph
// redrawn where it stands. A change to the site's own files loads the page
// again, so an asset or a renderer module edited while it is open shows up
// without a refresh -- and so does one edited while a phone had the page away:
// the stream reconnects afterwards, and the page then loads itself again.
let dropped = false;
const live = new EventSource('/events');
live.addEventListener('change', debounce(load, 250));
live.addEventListener('reload', () => location.reload());
live.addEventListener('error', () => {
  dropped = true;
});
live.addEventListener('open', () => {
  const missed = dropped;
  dropped = false;
  if (missed) location.reload();
});

load();
