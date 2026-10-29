// What a rendered org document can be asked to do (helpers/org/web/clicks):
// the state badge of a headline and the checkbox of a list item both write
// the entry's file through nvim. Loaded by the dashboard and by the preview
// page alike, so a document reads and answers the same on either.
//
// A badge names the headline it stands on -- `data-heading`, its place under
// the entry, or `data-entry` for the entry's own title -- and a box names
// itself by its place in the entry's lists, `data-box`. Both are resolved
// against the entry the document was rendered for, the one `bind` was given.

window.OrgActions = (() => {
  let keywords;

  async function keywordLists() {
    if (keywords) return keywords;
    const fallback = { open: ['TODO'], done: ['DONE'] };
    try {
      const res = await fetch('/api/keywords');
      keywords = (await res.json()).keywords || fallback;
    } catch (e) {
      keywords = fallback;
    }
    if (!keywords.open || !keywords.open.length) keywords = fallback;
    return keywords;
  }

  function toast(text) {
    let box = document.getElementById('toast');
    if (!box) {
      box = document.createElement('div');
      box.id = 'toast';
      document.body.append(box);
    }
    box.textContent = text;
    box.classList.add('on');
    clearTimeout(box._timer);
    box._timer = setTimeout(() => box.classList.remove('on'), 2400);
  }

  async function post(path, body) {
    try {
      const res = await fetch(path, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      const json = await res.json();
      if (json && json.error) toast(json.error);
      if (json && json.warning) toast(json.warning);
      return json;
    } catch (e) {
      toast('nvim did not answer');
      return null;
    }
  }

  // A small list under the thing it was opened from -- the dashboard's own
  // menu, in the words of the states the vault uses.
  function menu(anchor, items) {
    document.querySelectorAll('.state-menu').forEach((m) => m.remove());
    const box = document.createElement('div');
    box.className = 'state-menu';
    for (const item of items) {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = item.cls || '';
      button.textContent = item.label;
      button.addEventListener('click', () => {
        box.remove();
        item.run();
      });
      box.append(button);
    }
    const rect = anchor.getBoundingClientRect();
    box.style.left = rect.left + 'px';
    box.style.top = rect.bottom + 4 + 'px';
    document.body.append(box);
    // a keyword near the right edge or the bottom of a phone would push the
    // menu off the page; its size is only known once it is in the document
    const size = box.getBoundingClientRect();
    const below = rect.bottom + 4;
    box.style.left = Math.max(8, Math.min(rect.left, innerWidth - size.width - 8)) + 'px';
    box.style.top =
      (below + size.height > innerHeight - 8 ? Math.max(8, rect.top - size.height - 4) : below) + 'px';
    const off = (ev) => {
      if (!box.contains(ev.target)) {
        box.remove();
        document.removeEventListener('mousedown', off);
      }
    };
    setTimeout(() => document.addEventListener('mousedown', off), 0);
    return box;
  }

  const entryBody = (entry) => ({
    file: entry.file,
    line: entry.line == null ? undefined : Number(entry.line),
    id: entry.id || undefined,
  });

  async function openStates(anchor, entry) {
    const lists = await keywordLists();
    const current = anchor.dataset.state || '';
    const items = [];
    for (const kw of [...lists.open, ...lists.done]) {
      if (kw === current) continue;
      items.push({ label: kw, cls: kw, run: () => change(anchor, entry, kw) });
    }
    items.push({ label: 'no keyword', run: () => change(anchor, entry, '') });
    menu(anchor, items);
  }

  async function change(anchor, entry, state) {
    const heading = anchor.dataset.heading;
    const res =
      heading == null
        ? await post('/api/state', { ...entryBody(entry), state })
        : await post('/api/header', {
            ...entryBody(entry),
            heading: Number(heading),
            text: anchor.dataset.text || '',
            state,
          });
    if (!res || res.error) return;
    // the class carries the colour: `todo NEXT` before `done DONE` after
    const lists = await keywordLists();
    const rows = [state && (lists.done.includes(state) ? 'done' : 'todo'), state].filter(Boolean);
    anchor.className = ['state', ...rows].join(' ');
    anchor.textContent = state || '—';
    anchor.dataset.state = state;
    toast(state ? '→ ' + state : 'no keyword');
  }

  async function toggleBox(box, entry) {
    const want = box.checked;
    const res = await post('/api/box', {
      ...entryBody(entry),
      box: Number(box.dataset.box),
      text: box.dataset.text || '',
      on: want,
    });
    if (!res || res.error) {
      box.checked = !want;
      return;
    }
    // what the file says, which is not always what was asked: org keeps a box
    // unchecked while a box under it is unchecked
    box.checked = res.box === 'on';
    if (want && !box.checked) toast('a box with boxes under it stays unchecked until they are ticked');
    // the row's own class follows the box until the page refetches
    const row = box.closest('li');
    if (row) {
      row.classList.remove('on', 'off', 'trans');
      row.classList.add(res.box || (box.checked ? 'on' : 'off'));
    }
  }

  // The click of a badge or a box, for the document under `root`. `entry`
  // is what the document was rendered for: file, line, and the id when the
  // entry has one.
  function bind(root, entry) {
    if (!root || !entry || !entry.file) return;
    root.addEventListener('click', (ev) => {
      const badge = ev.target.closest('button.state[data-entry], button.state[data-heading]');
      if (badge) {
        ev.preventDefault();
        openStates(badge, entry);
        return;
      }
      const box = ev.target.closest('input[type=checkbox][data-box]');
      if (box) toggleBox(box, entry);
    });
  }

  return { bind, toggleBox, menu };
})();
