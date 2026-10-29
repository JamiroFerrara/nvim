// The vault's graph: a set of nodes and the edges between them, laid out by
// one force pass and then panned, zoomed and dragged. Both pages that draw
// one come here -- the roam notes (roam.js) and the ticket board (app.js) --
// so there is a single layout and a single set of gestures under both.
//
// A node is `{ id, title, r?, class?, tip? }`: the id is what an edge names,
// the class is extra styling the page wants on the circle (a state, "here"),
// and the tip is what a hover says about it. An edge is
// `{ source, target, kind? }`, the kind a class on the line.
//
// Nothing here fetches: the caller hands over the nodes and edges it already
// has, and gets the drawn view back.
window.OrgGraph = (function () {
  const SVG = 'http://www.w3.org/2000/svg';

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

  // A force layout, run once: repulsion between every pair, a spring along
  // every link, a pull toward the middle. Enough for a few hundred nodes and
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

  // Drawing repeatedly is cheap at these sizes and the movement is what makes
  // the graph readable: a node that moves away from its neighbours is a node
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

  // Settled, the nodes keep a slow breath so the picture reads as alive and a
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
    // the whole graph, local or not: the nodes it holds, and nothing cropped
    setViewBox(view, { x: minX - pad, y: minY - pad, w, h });
  }

  function setViewBox(view, box) {
    view.viewBox = box;
    view.svg.setAttribute('viewBox', `${box.x} ${box.y} ${box.w} ${box.h}`);
    updateLabels(view);
  }

  // Labels are noise on a whole graph and the only way to read a close-up:
  // they appear once the view is zoomed in past roughly one unit per pixel --
  // or always, when the page says the labels are the point.
  function updateLabels(view) {
    const scale = (view.pane.clientWidth || 900) / view.viewBox.w;
    view.showAll = view.labelsAll || scale > 1.35;
    for (const [, box] of view.boxes) {
      box.label.classList.toggle('on', view.showAll);
    }
  }

  function wire(view, tip) {
    const svg = view.svg;
    const pane = view.pane;
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
        // a node stays inside the picture: dragged past the edge it would
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
          const text = view.tipText(box.node);
          if (!text) {
            tip.classList.remove('on');
            return;
          }
          tip.textContent = text;
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
        if (!drag.moved) view.open(drag.box.node);
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

  // The hovered node and its neighbours stay bright, the rest falls back.
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

  let current = null;

  /**
   * Draw `opts.nodes` and `opts.edges` in `pane`.
   *
   * opts:
   *   nodes     [{ id, title, label?, r?, class? }]
   *   edges     [{ source, target, kind? }]
   *   here      the id to mark as the one the page is on
   *   hud       [left text, right text]
   *   labelsAll every label on from the start (a small graph is read by name)
   *   query     the search filter to dim what does not match
   *   open      (node) => {} on a click that did not drag
   *   tip       (node) => string, a hover line, or '' for none
   *   empty     what to say when there is nothing to draw
   */
  function draw(pane, opts) {
    if (opts.nodes.length === 0) {
      pane.append(el('p', 'empty', opts.empty || 'Nothing to draw.'));
      return null;
    }
    const width = pane.clientWidth || 900;
    const height = pane.clientHeight || 700;
    const nodes = opts.nodes.map((node) => ({
      ...node,
      r: node.r || 4,
      class: node.class || '',
    }));
    const byId = new Map(nodes.map((node) => [node.id, node]));
    const degree = new Map();
    const edges = [];
    for (const link of opts.edges) {
      const a = byId.get(link.source);
      const b = byId.get(link.target);
      if (!a || !b || a === b) continue;
      edges.push({ a, b, kind: link.kind || '' });
      degree.set(a.id, (degree.get(a.id) || 0) + 1);
      degree.set(b.id, (degree.get(b.id) || 0) + 1);
    }
    // the ring scales with what the node is attached to: a hub reads as one
    for (const node of nodes) {
      if (node.r === 4) node.r = 4 + Math.min(9, Math.sqrt(degree.get(node.id) || 0) * 2.2);
    }

    layout(nodes, edges, { w: width, h: height });
    // the layout settles the nodes where they belong; the graph then starts
    // them from the middle and lets them fly out to that place
    for (const [i, node] of nodes.entries()) {
      node.tx = node.x;
      node.ty = node.y;
      const a = i * 2.399963229728653;
      const r = 30 + 4 * Math.sqrt(i + 1);
      node.x = Math.cos(a) * r;
      node.y = Math.sin(a) * r;
    }

    const svg = svgEl('svg', { class: 'graph-svg' });
    const viewport = svgEl('g');
    const edgeLayer = svgEl('g', { class: 'edges' });
    const nodeLayer = svgEl('g', { class: 'nodes' });
    viewport.append(edgeLayer, nodeLayer);
    svg.append(viewport);
    pane.append(svg);

    const lines = new Map();
    for (const edge of edges) {
      const line = svgEl('line', edge.kind ? { class: edge.kind } : {});
      edgeLayer.append(line);
      lines.set(edge, line);
    }

    const boxes = new Map();
    for (const node of nodes) {
      const group = svgEl('g', { class: 'node' + (node.class ? ' ' + node.class : '') });
      const circle = svgEl('circle', { r: node.r });
      const label = svgEl('text', { class: 'label', x: node.r + 4, y: 3 });
      // a page can hand over a label for the drawing and keep the whole title
      // for the hover: the label is what has to not overlap its neighbours
      label.textContent = node.label || node.title;
      // the browser's own tooltip: a long title is readable without a click
      const full = svgEl('title');
      full.textContent = node.title;
      group.append(full, circle, label);
      if (opts.here && node.id === opts.here) group.classList.add('here');
      nodeLayer.append(group);
      boxes.set(node.id, { group, circle, label, node });
    }

    if (opts.hud) {
      const hud = el('div', 'graph-hud');
      hud.append(el('span', '', opts.hud[0] || ''));
      hud.append(el('span', '', opts.hud[1] || ''));
      pane.append(hud);
    }

    const tip = el('div', 'graph-tip');
    pane.append(tip);

    const view = {
      pane,
      svg,
      viewport,
      nodes,
      edges,
      lines,
      boxes,
      labelsAll: !!opts.labelsAll,
      tipText: opts.tip || (() => ''),
      open: opts.open || (() => {}),
      viewBox: { x: 0, y: 0, w: width, h: height },
    };
    current = view;

    fit(view);
    place(view);
    wire(view, tip);
    filter(opts.query);
    animate(view);
    return view;
  }

  /** Dim every node whose title does not hold every word of `query`. */
  function filter(query) {
    const view = current;
    if (!view) return;
    const words = (query || '').trim().toLowerCase().split(/\s+/).filter(Boolean);
    for (const [, box] of view.boxes) {
      const title = box.node.title.toLowerCase();
      const hit = words.every((word) => title.includes(word));
      box.group.classList.toggle('muted', !hit && words.length > 0);
    }
  }

  return { draw, filter };
})();
