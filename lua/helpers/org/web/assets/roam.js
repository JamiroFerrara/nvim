// The roam mode's client: the note rail, one rendered note, and the graph of
// the links between notes. The notes and links come from /api/roam (the
// plugin's own roam index, in Lua); a note's body is the org HTML export with
// its `id:` links pointed back at this page (/api/roam/note). Routes are the
// hash: #n=<id> a note, #g the whole graph, #g=<id> the graph around a note.

const SVG = 'http://www.w3.org/2000/svg';

const state = {
  data: null,
  query: '',
  token: 0,
  view: null, // the drawn graph: { svg, viewport, nodes, lines, boxes }
};

const $ = (sel) => document.querySelector(sel);

const el = (tag, cls, text) => {
  const node = document.createElement(tag);
  if (cls) node.className = cls;
  if (text !== undefined && text !== null) node.textContent = text;
  return node;
};

const svgEl = (tag, attrs) => {
  const node = document.createElementNS(SVG, tag);
  for (const [key, value] of Object.entries(attrs || {})) node.setAttribute(key, value);
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
      btn.addEventListener('click', () => go('n=' + note.id));
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

// A force layout, run once: repulsion between every pair, a spring along
// every link, a pull toward the middle. Enough for a few hundred notes and
// gone in a moment; the graph then holds still and pans and zooms.
function layout(nodes, edges, size) {
  const n = nodes.length;
  const k = Math.sqrt((size.w * size.h) / Math.max(n, 1));
  for (let i = 0; i < n; i++) {
    const a = i * 2.399963229728653; // the golden angle: an even ring
    const r = 8 * Math.sqrt(i + 1);
    nodes[i].x = Math.cos(a) * r;
    nodes[i].y = Math.sin(a) * r;
    nodes[i].vx = 0;
    nodes[i].vy = 0;
  }
  const iterations = n > 600 ? 120 : 260;
  for (let step = 0; step < iterations; step++) {
    const alpha = 1 - step / iterations + 0.05;
    for (let i = 0; i < n; i++) {
      const a = nodes[i];
      for (let j = i + 1; j < n; j++) {
        const b = nodes[j];
        let dx = a.x - b.x;
        let dy = a.y - b.y;
        let d2 = dx * dx + dy * dy;
        if (d2 < 0.01) {
          dx = (i % 7) / 7 - 0.5;
          dy = (j % 7) / 7 - 0.5;
          d2 = dx * dx + dy * dy;
        }
        const d = Math.sqrt(d2);
        const force = ((k * k) / d) * alpha * 0.4 / d;
        a.vx += dx * force;
        a.vy += dy * force;
        b.vx -= dx * force;
        b.vy -= dy * force;
      }
    }
    for (const edge of edges) {
      const a = edge.a;
      const b = edge.b;
      const dx = b.x - a.x;
      const dy = b.y - a.y;
      const d = Math.hypot(dx, dy) || 0.001;
      const force = (d / k) * 0.7 * alpha;
      a.vx += (dx / d) * force;
      a.vy += (dy / d) * force;
      b.vx -= (dx / d) * force;
      b.vy -= (dy / d) * force;
    }
    for (const node of nodes) {
      node.vx -= node.x * 0.012 * alpha;
      node.vy -= node.y * 0.012 * alpha;
      node.x += node.vx;
      node.y += node.vy;
      node.vx *= 0.6;
      node.vy *= 0.6;
    }
  }
  // The forces settle the shape, not its size: rescale the result so the
  // whole graph sits in the pane at a readable size whatever the node count.
  let minX = Infinity;
  let maxX = -Infinity;
  let minY = Infinity;
  let maxY = -Infinity;
  for (const node of nodes) {
    minX = Math.min(minX, node.x);
    maxX = Math.max(maxX, node.x);
    minY = Math.min(minY, node.y);
    maxY = Math.max(maxY, node.y);
  }
  const span = Math.max(maxX - minX, maxY - minY) || 1;
  const scale = (Math.min(size.w, size.h) * 0.92) / span;
  const cx = (minX + maxX) / 2;
  const cy = (minY + maxY) / 2;
  for (const node of nodes) {
    node.x = (node.x - cx) * scale;
    node.y = (node.y - cy) * scale;
  }
}

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
  if (notes.length === 0) {
    pane.append(el('p', 'empty', 'No note to draw.'));
    return;
  }

  const width = pane.clientWidth || 900;
  const height = pane.clientHeight || 700;
  const nodes = notes.map((note) => ({ id: note.id, title: note.title, note, r: 4 }));
  const byId = new Map(nodes.map((node) => [node.id, node]));
  const degree = new Map();
  const edges = [];
  for (const link of links) {
    const a = byId.get(link.source);
    const b = byId.get(link.target);
    if (!a || !b) continue;
    edges.push({ a, b });
    degree.set(a.id, (degree.get(a.id) || 0) + 1);
    degree.set(b.id, (degree.get(b.id) || 0) + 1);
  }
  for (const node of nodes) node.r = 4 + Math.min(9, Math.sqrt(degree.get(node.id) || 0) * 2.2);

  layout(nodes, edges, { w: width, h: height });
  // the layout settles the notes where they belong; the graph then starts
  // them from the middle and lets them fly out to that place
  for (const [i, node] of nodes.entries()) {
    node.tx = node.x;
    node.ty = node.y;
    const a = i * 2.399963229728653;
    const r = 30 + 4 * Math.sqrt(i + 1);
    node.x = Math.cos(a) * r;
    node.y = Math.sin(a) * r;
  }

  const svg = svgEl('svg', { id: 'graph' });
  const viewport = svgEl('g');
  const edgeLayer = svgEl('g', { class: 'edges' });
  const nodeLayer = svgEl('g', { class: 'nodes' });
  viewport.append(edgeLayer, nodeLayer);
  svg.append(viewport);
  pane.append(svg);

  const lines = new Map();
  for (const edge of edges) {
    const line = svgEl('line', {});
    edgeLayer.append(line);
    lines.set(edge, line);
  }

  const boxes = new Map();
  for (const node of nodes) {
    const group = svgEl('g', { class: 'node' });
    const circle = svgEl('circle', { r: node.r });
    const label = svgEl('text', { class: 'label', x: node.r + 4, y: 3 });
    label.textContent = node.title;
    group.append(circle, label);
    if (focusId && node.id === focusId) group.classList.add('here');
    nodeLayer.append(group);
    boxes.set(node.id, { group, circle, label, node });
  }

  const hud = el('div');
  hud.id = 'hud';
  hud.append(el('span', '', `${nodes.length} notes · ${edges.length} links`));
  const hint = el('span', '', focusId ? 'local graph · 2 links out' : 'click a note · drag to pan · scroll to zoom');
  hud.append(hint);
  pane.append(hud);

  const tip = el('div');
  tip.id = 'tip';
  pane.append(tip);

  const view = {
    svg,
    viewport,
    nodes,
    edges,
    lines,
    boxes,
    viewBox: { x: 0, y: 0, w: width, h: height },
  };
  state.view = view;

  fit(view);
  place(view);
  wire(view, pane, tip);
  applyFilter(view);
  animate(view);
}

// Drawing repeatedly is cheap at these sizes and the movement is what makes
// the graph readable: a note that moves away from its neighbours is a note
// whose links just went quiet.
const reducedMotion = window.matchMedia?.('(prefers-reduced-motion: reduce)')?.matches;

function animate(view) {
  if (reducedMotion) {
    for (const node of view.nodes) {
      node.x = node.tx;
      node.y = node.ty;
    }
    place(view);
    return;
  }
  const start = performance.now();
  for (const node of view.nodes) {
    node.sx = node.x;
    node.sy = node.y;
  }
  const settle = (now) => {
    if (!view.svg.isConnected) return; // the pane moved on
    const t = Math.min(1, (now - start) / 900);
    const eased = 1 - Math.pow(1 - t, 3);
    for (const node of view.nodes) {
      if (node.dragged) continue;
      node.x = node.sx + (node.tx - node.sx) * eased;
      node.y = node.sy + (node.ty - node.sy) * eased;
    }
    place(view);
    view.raf = requestAnimationFrame(t < 1 ? settle : (next) => drift(view, next));
  };
  view.raf = requestAnimationFrame(settle);
}

// Settled, the notes keep a slow breath so the picture reads as alive and a
// click never lands on something that looked dead.
function drift(view, now) {
  if (!view.svg.isConnected) return;
  const t = now / 1000;
  for (let i = 0; i < view.nodes.length; i++) {
    const node = view.nodes[i];
    if (node.dragged) continue;
    node.x = node.tx + Math.sin(t * 0.7 + i * 1.7) * 5;
    node.y = node.ty + Math.cos(t * 0.55 + i * 2.3) * 5;
  }
  place(view);
  view.raf = requestAnimationFrame((next) => drift(view, next));
}

function place(view) {
  for (const edge of view.edges) {
    const line = view.lines.get(edge);
    line.setAttribute('x1', edge.a.x);
    line.setAttribute('y1', edge.a.y);
    line.setAttribute('x2', edge.b.x);
    line.setAttribute('y2', edge.b.y);
  }
  for (const [, box] of view.boxes) {
    box.group.setAttribute('transform', `translate(${box.node.x},${box.node.y})`);
  }
}

function fit(view) {
  let minX = Infinity;
  let maxX = -Infinity;
  let minY = Infinity;
  let maxY = -Infinity;
  for (const node of view.nodes) {
    minX = Math.min(minX, node.tx - node.r);
    maxX = Math.max(maxX, node.tx + node.r);
    minY = Math.min(minY, node.ty - node.r);
    maxY = Math.max(maxY, node.ty + node.r);
  }
  const pad = Math.max(30, (maxX - minX) * 0.08);
  const w = Math.max(40, maxX - minX + pad * 2);
  const h = Math.max(40, maxY - minY + pad * 2);
  // the whole graph, local or not: the notes it holds, and nothing cropped
  setViewBox(view, { x: minX - pad, y: minY - pad, w, h });
}

function setViewBox(view, box) {
  view.viewBox = box;
  view.svg.setAttribute('viewBox', `${box.x} ${box.y} ${box.w} ${box.h}`);
  updateLabels(view);
}

// Labels are noise on a whole graph and the only way to read a close-up: they
// appear once the view is zoomed in past roughly one unit per pixel.
function updateLabels(view) {
  const pane = $('#pane');
  const scale = (pane.clientWidth || 900) / view.viewBox.w;
  view.showAll = scale > 1.35;
  for (const [, box] of view.boxes) {
    box.label.classList.toggle('on', view.showAll);
  }
}

function wire(view, pane, tip) {
  const svg = view.svg;
  const pointOf = (ev) => {
    const box = svg.getBoundingClientRect();
    return {
      x: view.viewBox.x + ((ev.clientX - box.left) / box.width) * view.viewBox.w,
      y: view.viewBox.y + ((ev.clientY - box.top) / box.height) * view.viewBox.h,
    };
  };

  let pan = null;
  let drag = null;

  svg.addEventListener('pointerdown', (ev) => {
    if (ev.button !== 0) return;
    const target = ev.target.closest?.('g.node');
    if (target) {
      const id = [...view.boxes.entries()].find(([, box]) => box.group === target)?.[0];
      const box = id && view.boxes.get(id);
      if (box) {
        box.node.dragged = true;
        drag = { box, start: pointOf(ev), moved: false, from: { x: box.node.tx, y: box.node.ty } };
        svg.setPointerCapture(ev.pointerId);
      }
      return;
    }
    pan = { start: pointOf(ev), box: { ...view.viewBox } };
    svg.classList.add('panning');
    svg.setPointerCapture(ev.pointerId);
  });

  svg.addEventListener('pointermove', (ev) => {
    if (drag) {
      const now = pointOf(ev);
      const dx = now.x - drag.start.x;
      const dy = now.y - drag.start.y;
      if (Math.abs(dx) + Math.abs(dy) > 2) drag.moved = true;
      // a note stays inside the picture: dragged past the edge it would
      // vanish, and the graph is meant to be looked at
      const box = view.viewBox;
      const node = drag.box.node;
      node.tx = Math.min(box.x + box.w - node.r - 6, Math.max(box.x + node.r + 6, drag.from.x + dx));
      node.ty = Math.min(box.y + box.h - node.r - 6, Math.max(box.y + node.r + 6, drag.from.y + dy));
      node.x = node.tx;
      node.y = node.ty;
      place(view);
      return;
    }
    if (pan) {
      const now = pointOf(ev);
      setViewBox(view, {
        x: pan.box.x - (now.x - pan.start.x),
        y: pan.box.y - (now.y - pan.start.y),
        w: pan.box.w,
        h: pan.box.h,
      });
      return;
    }
    const hovered = ev.target.closest?.('g.node');
    if (hovered) {
      const entry = [...view.boxes.entries()].find(([, box]) => box.group === hovered);
      if (entry) {
        light(view, entry[0]);
        const box = entry[1];
        tip.textContent = `${box.node.title} — ${box.node.note.backlinks} in, ${box.node.note.links} out`;
        const rect = pane.getBoundingClientRect();
        tip.style.left = ev.clientX - rect.left + 'px';
        tip.style.top = ev.clientY - rect.top + 'px';
        tip.classList.add('on');
      }
    } else {
      light(view, null);
      tip.classList.remove('on');
    }
  });

  svg.addEventListener('pointerleave', () => {
    light(view, null);
    tip.classList.remove('on');
  });

  const release = (ev) => {
    light(view, null);
    tip.classList.remove('on');
    if (drag) {
      drag.box.node.dragged = false;
      if (!drag.moved) go('n=' + drag.box.node.id);
      drag = null;
    }
    pan = null;
    svg.classList.remove('panning');
    if (ev?.pointerId !== undefined && svg.hasPointerCapture?.(ev.pointerId)) {
      svg.releasePointerCapture(ev.pointerId);
    }
  };
  svg.addEventListener('pointerup', release);
  svg.addEventListener('pointercancel', release);

  svg.addEventListener('wheel', (ev) => {
    ev.preventDefault();
    const before = pointOf(ev);
    const factor = Math.exp(ev.deltaY * 0.0015);
    const box = view.viewBox;
    const w = Math.min(40000, Math.max(120, box.w * factor));
    const h = (w / box.w) * box.h;
    setViewBox(view, {
      x: before.x - ((before.x - box.x) * w) / box.w,
      y: before.y - ((before.y - box.y) * h) / box.h,
      w,
      h,
    });
  });
}

// The hovered note and its neighbours stay bright, the rest falls back.
function light(view, id) {
  for (const edge of view.edges) {
    const line = view.lines.get(edge);
    line.classList.toggle('lit', !!id && (edge.a.id === id || edge.b.id === id));
  }
  const near = new Set();
  if (id) {
    near.add(id);
    for (const edge of view.edges) {
      if (edge.a.id === id) near.add(edge.b.id);
      if (edge.b.id === id) near.add(edge.a.id);
    }
  }
  for (const [nodeId, box] of view.boxes) {
    box.group.classList.toggle('lit', near.has(nodeId) && nodeId !== id);
    box.group.classList.toggle('muted', !!id && !near.has(nodeId));
  }
  for (const [nodeId, box] of view.boxes) {
    box.label.classList.toggle('on', !id ? view.showAll : near.has(nodeId));
  }
}

function applyFilter(view) {
  const q = state.query.trim().toLowerCase();
  for (const [, box] of view.boxes) {
    const hit = !q || box.node.title.toLowerCase().includes(q);
    box.group.classList.toggle('muted', !hit && !!q);
  }
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

$('#search').addEventListener('input', (ev) => {
  state.query = ev.target.value;
  const current = route();
  renderRail(current || { kind: 'graph', id: null });
  if (state.view) applyFilter(state.view);
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
  } else if ((ev.key === 'g' || ev.key === 'G') && !typing) {
    const current = route();
    if (current?.kind === 'note') go('g=' + current.id);
    else if (current?.kind === 'graph' && current.id) go('g');
  }
});

// The vault follows the page: one save, one re-read, the note or the graph
// redrawn where it stands.
const live = new EventSource('/events');
live.addEventListener('change', debounce(load, 250));

load();
