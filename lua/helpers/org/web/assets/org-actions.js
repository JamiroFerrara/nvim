// What a rendered org document can be asked to do (helpers/org/web/clicks):
// the state badge of a headline and the checkbox of a list item both write
// the entry's file through nvim. Loaded by the dashboard and by the preview
// page alike, so a document reads and answers the same on either.
//
// A badge names the headline it stands on -- `data-heading`, its place under
// the entry, or `data-entry` for the entry's own title -- and a box names
// itself by its place in the entry's lists, `data-box`. Both are resolved
// against the entry the document was rendered for, the one `bind` was given.
//
// Every headline that can be written also gets two little buttons at its far
// end: `✓` closes the ticket in one click (and `↺` opens it again when it is
// closed), `✕` deletes it after a second click that says what it will do.
// They are drawn here, not by the exporter, so the page and the editor answer
// the same and a phone needs no keyboard.

window.OrgActions = (() => {
  let keywords;
  // the entry the page's document was rendered for, for the buttons that
  // carry no place of their own -- the ones drawn beside a badge
  let rendered;

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
    // the little button beside it says what the next click would do
    flipLabel(anchor.closest('.headline'), lists);
    toast(state ? '→ ' + state : 'no keyword');
    // the list behind the pane, and the cookie of the entry above the one
    // just closed, follow the file: both are drawn again from it
    document.dispatchEvent(new CustomEvent('org:reload', { detail: { entry: false } }));
  }

  // The `✓` / `↺` of a headline says the state the next click lands on: a
  // ticket is closed by one click and opened again by one, the way `D` in the
  // editor toggles it -- only the two words, no menu in between.
  function flipLabel(headline, lists) {
    const flip = headline && headline.querySelector('.headline-acts .flip');
    if (!flip) return;
    const badge = headline.querySelector('button.state[data-entry], button.state[data-heading]');
    const state = (badge && badge.dataset.state) || '';
    const closed = lists.done.includes(state);
    const target = closed ? lists.open[0] || 'TODO' : lists.done[0] || 'DONE';
    flip.dataset.state = state;
    flip.textContent = closed ? '↺' : '✓';
    flip.title = closed ? 'back to ' + target : 'mark ' + target;
    flip.classList.toggle('closed', closed);
  }

  async function flip(button) {
    const headline = button.closest('.headline');
    const badge = headline && headline.querySelector('button.state[data-entry], button.state[data-heading]');
    if (!badge || !rendered) return;
    const lists = await keywordLists();
    const state = badge.dataset.state || '';
    const target = lists.done.includes(state) ? lists.open[0] || 'TODO' : lists.done[0] || 'DONE';
    await change(badge, rendered, target);
  }

  // `✕` deletes the ticket and everything under it. The first click only says
  // what the second one does, so a thumb on a list of tickets cannot delete
  // one by itself, and the button goes quiet again if it is left alone.
  async function kill(button) {
    const headline = button.closest('.headline');
    const badge = headline && headline.querySelector('button.state[data-entry], button.state[data-heading]');
    if (!badge || !rendered) return;
    if (!button.dataset.armed) {
      button.dataset.armed = '1';
      button.textContent = 'delete?';
      button.classList.add('armed');
      clearTimeout(button._disarm);
      button._disarm = setTimeout(() => {
        delete button.dataset.armed;
        button.textContent = '✕';
        button.classList.remove('armed');
      }, 4000);
      return;
    }
    const heading = badge.dataset.heading;
    const body =
      heading == null
        ? entryBody(rendered)
        : { ...entryBody(rendered), heading: Number(heading), text: badge.dataset.text || '' };
    const res = await post('/api/kill', body);
    if (!res || res.error) return;
    // the entry itself is gone: the page has nothing left to show of it
    document.dispatchEvent(new CustomEvent('org:reload', { detail: { entry: heading == null } }));
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

  // The two buttons of a headline the page may write: drawn here rather than
  // exported, so a document redrawn after a write gets them back, and called
  // again on the same document finds the ones already there.
  async function decorate(root) {
    const lists = await keywordLists();
    const headlines = [...(root.matches && root.matches('.headline') ? [root] : [])];
    for (const hl of root.querySelectorAll('.headline')) headlines.push(hl);
    for (const hl of headlines) {
      const badge = hl.querySelector('button.state[data-entry], button.state[data-heading]');
      // a contents line is a link to a headline, and a headline with no badge
      // is one the page cannot write: neither gets the buttons
      if (!badge || hl.closest('#table-of-contents')) continue;
      if (hl.querySelector('.headline-acts')) {
        flipLabel(hl, lists);
        continue;
      }
      const acts = document.createElement('span');
      acts.className = 'headline-acts';
      const flipButton = document.createElement('button');
      flipButton.type = 'button';
      flipButton.className = 'flip';
      const killButton = document.createElement('button');
      killButton.type = 'button';
      killButton.className = 'kill';
      killButton.textContent = '✕';
      killButton.title = 'delete this ticket and everything under it';
      acts.append(flipButton, killButton);
      hl.append(acts);
      flipLabel(hl, lists);
    }
  }

  // The click of a badge, a box or one of the two buttons, for the document
  // under `root`. `entry` is what the document was rendered for: file, line,
  // and the id when the entry has one. One listener serves every document the
  // page draws, so binding a redrawn document again costs nothing.
  let listening = false;

  function bind(root, entry) {
    if (!root || !entry || !entry.file) return;
    rendered = entry;
    if (!listening) {
      listening = true;
      document.addEventListener('click', (ev) => {
        const flipButton = ev.target.closest('.headline-acts .flip');
        if (flipButton) {
          ev.preventDefault();
          flip(flipButton);
          return;
        }
        const killButton = ev.target.closest('.headline-acts .kill');
        if (killButton) {
          ev.preventDefault();
          kill(killButton);
          return;
        }
        const badge = ev.target.closest('button.state[data-entry], button.state[data-heading]');
        if (badge) {
          ev.preventDefault();
          openStates(badge, rendered);
          return;
        }
        const box = ev.target.closest('input[type=checkbox][data-box]');
        if (box) toggleBox(box, rendered);
      });
    }
    decorate(root);
  }

  return { bind, toggleBox, menu };
})();
