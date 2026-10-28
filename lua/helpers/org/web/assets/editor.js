// The modal editor behind the browser org views.
//
// It opens on one entry's own lines -- the headline through the end of its
// subtree, the same range the view's entry scratch shows -- and reads like
// vim: normal mode moves with h j k l w b e 0 ^ $ gg G and takes counts, i a
// I A o O type, x dd dw D erase, u undoes, and `:w` writes the text back into
// the entry's file through nvim (`/api/text`, which saves it the way a view
// action does). The page owns the rest of the keys.
//
// One textarea holds the text -- it needs a caret, and it is the only way to
// get an IME, clipboard and undo-free editing for nothing -- and the modes
// decide who reads the keystrokes: normal mode keeps it readOnly and moves
// the selection itself, insert mode hands it back to the browser.

(function () {
  const el = (tag, cls, text) => {
    const node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text !== undefined && text !== null) node.textContent = text;
    return node;
  };

  const isWord = (ch) => ch !== undefined && /[A-Za-z0-9_\-]/.test(ch);
  const isBlank = (ch) => ch === undefined || /\s/.test(ch);

  function create(spec) {
    const root = el('div', 'editor');
    root.setAttribute('role', 'dialog');
    root.setAttribute('aria-label', 'entry editor');

    const head = el('header', 'editor-head');
    const where = el('span', 'editor-where', spec.where || '');
    head.append(where);
    const actions = el('span', 'editor-actions');
    const saveBtn = el('button', '', 'write');
    saveBtn.title = ':w  write the entry back';
    const closeBtn = el('button', '', '✕');
    closeBtn.title = 'q  close';
    actions.append(saveBtn, closeBtn);
    head.append(actions);
    root.append(head);

    const ta = document.createElement('textarea');
    ta.className = 'editor-text';
    ta.spellcheck = false;
    ta.autocapitalize = 'off';
    ta.setAttribute('autocomplete', 'off');
    ta.setAttribute('wrap', 'off');
    root.append(ta);

    const status = el('footer', 'editor-status');
    const modeChip = el('span', 'editor-mode', 'NORMAL');
    const at = el('span', 'editor-at', '');
    const note = el('span', 'editor-note', '');
    status.append(modeChip, at, note);
    root.append(status);

    let mode = 'normal';
    let pos = 0;
    let count = '';
    let pending = '';
    let dirty = false;
    let savedText = spec.text;
    let start = spec.start || 1;
    let undoStack = [];
    let message = '';

    ta.readOnly = true;

    const lineCount = () => ta.value.split('\n').length;
    const lineStart = (idx) => {
      const text = ta.value;
      let n = 0;
      for (let i = 0; i < text.length; i++) {
        if (n === idx) return i;
        if (text[i] === '\n') n++;
      }
      return idx > 0 && n < idx ? text.length : 0;
    };
    const lineEnd = (idx) => {
      const text = ta.value;
      const from = lineStart(idx);
      const nl = text.indexOf('\n', from);
      return nl === -1 ? text.length : nl;
    };
    const lineOf = (at) => {
      let n = 0;
      for (let i = 0; i < at && i < ta.value.length; i++) if (ta.value[i] === '\n') n++;
      return n;
    };
    const lineLen = (idx) => lineEnd(idx) - lineStart(idx);
    const colOf = (at) => at - lineStart(lineOf(at));

    function draw() {
      const line = lineOf(pos);
      const col = colOf(pos);
      at.textContent = ` ${line + 1}:${col + 1} `;
      modeChip.textContent = mode.toUpperCase();
      modeChip.className = 'editor-mode ' + mode;
      note.textContent = (message ? message + '  ' : '') + (dirty ? '● unsaved' : '');
      if (mode === 'normal') {
        const end = Math.min(pos + 1, ta.value.length);
        ta.setSelectionRange(pos, end > pos ? end : pos);
      }
      const lineHeight = parseFloat(getComputedStyle(ta).lineHeight) || 20;
      const lineTop = line * lineHeight;
      const viewTop = ta.scrollTop;
      const viewBottom = viewTop + ta.clientHeight;
      if (lineTop < viewTop) ta.scrollTop = lineTop;
      else if (lineTop + lineHeight > viewBottom) ta.scrollTop = lineTop + lineHeight - ta.clientHeight;
    }

    function setText(value) {
      ta.value = value;
      pos = Math.max(0, Math.min(pos, ta.value.length));
      dirty = true;
      draw();
    }

    function snapshot() {
      undoStack.push({ text: ta.value, pos });
      if (undoStack.length > 200) undoStack.shift();
    }

    function enterInsert(at) {
      snapshot();
      mode = 'insert';
      pos = at === undefined ? pos : Math.max(0, Math.min(at, ta.value.length));
      ta.readOnly = false;
      ta.focus();
      ta.setSelectionRange(pos, pos);
      draw();
    }

    function enterNormal(at) {
      mode = 'normal';
      pos = at === undefined ? ta.selectionStart : at;
      ta.readOnly = true;
      ta.focus();
      draw();
    }

    // ---- motions ----------------------------------------------------------

    function nextWord(at) {
      const text = ta.value;
      let i = at;
      while (i < text.length && isWord(text[i])) i++;
      while (i < text.length && isBlank(text[i])) i++;
      return Math.min(i, Math.max(0, text.length - 1));
    }

    function prevWord(at) {
      const text = ta.value;
      let i = Math.max(0, at - 1);
      while (i > 0 && isBlank(text[i])) i--;
      while (i > 0 && isWord(text[i - 1])) i--;
      return i;
    }

    function wordEnd(at) {
      const text = ta.value;
      let i = at;
      while (i < text.length && !isWord(text[i])) i++;
      while (i < text.length && isWord(text[i])) i++;
      return Math.max(0, Math.min(i - 1, text.length - 1));
    }

    function moveTo(target, times) {
      let i = pos;
      for (let n = 0; n < (times || 1); n++) i = target(i);
      pos = Math.max(0, Math.min(i, Math.max(0, ta.value.length - 1)));
      draw();
    }

    function vertical(delta) {
      const line = lineOf(pos);
      const col = colOf(pos);
      const want = Math.max(0, Math.min(lineCount() - 1, line + delta));
      const max = Math.max(0, lineLen(want) - 1);
      pos = lineStart(want) + Math.min(col, max);
      draw();
    }

    // ---- edits ------------------------------------------------------------

    function splice(from, to, insert) {
      snapshot();
      const text = ta.value;
      ta.value = text.slice(0, from) + insert + text.slice(to);
      pos = from;
      dirty = true;
      draw();
    }

    function deleteChar(times) {
      let n = 0;
      while (n < times && pos < ta.value.length && ta.value[pos] !== '\n') {
        splice(pos, pos + 1, '');
        n++;
      }
    }

    function deleteLine(times) {
      const line = lineOf(pos);
      const last = Math.min(lineCount() - 1, line + times - 1);
      let from = lineStart(line);
      let to = Math.min(ta.value.length, lineEnd(last) + 1);
      // a line at the end of the text carries no newline of its own: the one
      // before it goes with it, the way vim's dd leaves no empty line
      if (to >= ta.value.length && from > 0) from -= 1;
      splice(from, to, '');
      pos = Math.min(pos, Math.max(0, ta.value.length - 1));
      draw();
    }

    function deleteWord(times) {
      const to = ta.value;
      let end = pos;
      for (let n = 0; n < times; n++) end = nextWord(end);
      splice(pos, end, '');
    }

    function deleteToEnd() {
      splice(pos, lineEnd(lineOf(pos)), '');
    }

    function openLine(below) {
      const line = lineOf(pos);
      const at = below ? lineEnd(line) : lineStart(line);
      snapshot();
      ta.value = ta.value.slice(0, at) + '\n' + ta.value.slice(at);
      dirty = true;
      pos = below ? at + 1 : at;
      mode = 'insert';
      ta.readOnly = false;
      ta.focus();
      ta.setSelectionRange(pos, pos);
      draw();
    }

    function insertAt(kind) {
      const line = lineOf(pos);
      const from = lineStart(line);
      if (kind === 'a' && pos < lineEnd(line)) enterInsert(pos + 1);
      else if (kind === 'a') enterInsert(lineEnd(line));
      else if (kind === 'I') {
        let i = from;
        while (i < lineEnd(line) && /[ \t]/.test(ta.value[i])) i++;
        enterInsert(i);
      } else if (kind === 'A') enterInsert(lineEnd(line));
      else enterInsert(pos);
    }

    function undo() {
      const last = undoStack.pop();
      if (!last) {
        message = 'already at the oldest change';
        draw();
        return;
      }
      ta.value = last.text;
      pos = Math.min(last.pos, Math.max(0, ta.value.length - 1));
      dirty = ta.value !== savedText;
      message = '';
      draw();
    }

    // ---- writing ----------------------------------------------------------

    async function write() {
      const lines = ta.value.split('\n');
      try {
        const res = await fetch('/api/text', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            file: spec.file,
            id: spec.id,
            line: start,
            lines,
          }),
        });
        const json = await res.json();
        if (json.error) {
          message = json.error;
          draw();
          return false;
        }
        if (json.text && json.text.start) start = json.text.start;
        savedText = ta.value;
        dirty = false;
        message = 'written';
        draw();
        if (spec.onSaved) spec.onSaved(lines);
        return true;
      } catch (err) {
        message = 'nvim did not answer';
        draw();
        return false;
      }
    }

    function close(force) {
      if (dirty && !force) {
        message = 'unsaved changes (:q! to discard)';
        draw();
        return;
      }
      if (spec.onClose) spec.onClose();
    }

    // ---- the command line -------------------------------------------------

    const cmd = el('div', 'editor-cmd');
    cmd.hidden = true;
    const cmdInput = document.createElement('input');
    cmdInput.type = 'text';
    cmdInput.spellcheck = false;
    cmd.append(el('span', '', ':'), cmdInput);
    root.append(cmd);

    function commandLine() {
      mode = 'command';
      cmd.hidden = false;
      cmdInput.value = '';
      cmdInput.focus();
      draw();
    }

    async function runCommand(text) {
      const name = text.trim();
      cmd.hidden = true;
      if (name === 'w') {
        await write();
        enterNormal(pos);
      } else if (name === 'wq' || name === 'x') {
        if (await write()) {
          dirty = false;
          close(true);
        } else {
          enterNormal(pos);
        }
      } else if (name === 'q') {
        enterNormal(pos);
        close(false);
      } else if (name === 'q!') {
        dirty = false;
        close(true);
      } else {
        message = 'no such command: ' + name;
        enterNormal(pos);
      }
    }

    cmdInput.addEventListener('keydown', (ev) => {
      ev.stopPropagation();
      if (ev.key === 'Enter') {
        ev.preventDefault();
        runCommand(cmdInput.value);
      } else if (ev.key === 'Escape') {
        ev.preventDefault();
        cmd.hidden = true;
        enterNormal(pos);
      }
    });

    // ---- keys -------------------------------------------------------------

    const step = {
      h: (i) => (colOf(i) > 0 ? i - 1 : i),
      l: (i) => (colOf(i) < Math.max(0, lineLen(lineOf(i)) - 1) ? i + 1 : i),
      w: nextWord,
      b: prevWord,
      e: wordEnd,
    };

    ta.addEventListener('input', () => {
      dirty = ta.value !== savedText;
      pos = ta.selectionStart;
      draw();
    });

    ta.addEventListener('keydown', (ev) => {
      if (mode === 'insert') {
        if (ev.key === 'Escape') {
          ev.preventDefault();
          enterNormal(Math.max(0, ta.selectionStart - 1));
        }
        return;
      }
      if (mode !== 'normal') return;
      ev.preventDefault();
      const key = ev.key;
      const times = count === '' ? 1 : parseInt(count, 10);

      if (pending === 'g') {
        pending = '';
        if (key === 'g') {
          const line = times > 1 ? Math.min(lineCount(), times) - 1 : 0;
          pos = lineStart(line);
          count = '';
          draw();
          return;
        }
        count = '';
        return;
      }
      if (pending === 'd') {
        pending = '';
        if (key === 'd') deleteLine(times);
        else if (key === 'w') deleteWord(times);
        else if (key === '$') deleteToEnd();
        count = '';
        return;
      }
      if (/^[1-9]$/.test(key) || (key === '0' && count !== '')) {
        count += key;
        draw();
        return;
      }
      if (key === 'g' || key === 'd') {
        pending = key;
        return;
      }
      if (key === 'j') {
        vertical(times);
        count = '';
        return;
      }
      if (key === 'k') {
        vertical(-times);
        count = '';
        return;
      }
      if (step[key]) {
        moveTo(step[key], times);
        count = '';
        return;
      }
      if (key === '0') {
        pos = lineStart(lineOf(pos));
        count = '';
        draw();
        return;
      }
      if (key === '^') {
        const line = lineOf(pos);
        let i = lineStart(line);
        while (i < lineEnd(line) && /[ \t]/.test(ta.value[i])) i++;
        pos = i;
        count = '';
        draw();
        return;
      }
      if (key === '$') {
        pos = Math.max(lineStart(lineOf(pos)), lineEnd(lineOf(pos)) - 1);
        count = '';
        draw();
        return;
      }
      if (key === 'G') {
        const line = count === '' ? lineCount() - 1 : Math.min(lineCount(), times) - 1;
        pos = lineStart(line);
        count = '';
        draw();
        return;
      }
      if (key === 'i' || key === 'a' || key === 'I' || key === 'A') {
        count = '';
        insertAt(key);
        return;
      }
      if (key === 'o' || key === 'O') {
        count = '';
        openLine(key === 'o');
        return;
      }
      if (key === 'x') {
        deleteChar(times);
        count = '';
        return;
      }
      if (key === 'D') {
        deleteToEnd();
        count = '';
        return;
      }
      if (key === 'u') {
        count = '';
        undo();
        return;
      }
      if (key === ':') {
        count = '';
        commandLine();
        return;
      }
      if (key === 'q') {
        count = '';
        close(false);
        return;
      }
      if (key === 'Insert') {
        enterInsert(pos);
        return;
      }
      count = '';
      draw();
    });

    saveBtn.addEventListener('click', () => write());
    closeBtn.addEventListener('click', () => close(false));

    root.addEventListener('mousedown', (ev) => {
      if (ev.target === root) close(false);
    });

    ta.value = spec.text;
    savedText = spec.text;
    dirty = false;
    pos = 0;
    if (spec.insertAtEnd) {
      // a capture starts where the text ends, in insert mode
      enterInsert(ta.value.length === 0 ? 0 : ta.value.length - 1);
      ta.setSelectionRange(ta.value.length, ta.value.length);
      pos = ta.value.length;
    } else {
      ta.focus();
      draw();
    }

    return {
      root,
      focus: () => ta.focus(),
      isDirty: () => dirty,
      write,
      close: () => close(true),
    };
  }

  async function fetchText(opts) {
    const query =
      '/api/text?file=' +
      encodeURIComponent(opts.file) +
      '&line=' +
      encodeURIComponent(opts.line === undefined || opts.line === null ? '' : opts.line) +
      (opts.id ? '&id=' + encodeURIComponent(opts.id) : '');
    const res = await fetch(query);
    const json = await res.json();
    return json.text || null;
  }

  async function open(opts) {
    const existing = document.querySelector('.editor-wrap');
    if (existing) existing.remove();
    let text = opts.text;
    let start = opts.start;
    if (typeof text !== 'string') {
      const got = await fetchText(opts);
      if (!got) {
        if (opts.onMissing) opts.onMissing('could not read the entry');
        return null;
      }
      text = got.lines.join('\n');
      start = got.start;
    }
    const wrap = el('div', 'editor-wrap');
    const editor = create({
      file: opts.file,
      id: opts.id,
      line: opts.line,
      start: start,
      text: text,
      where: opts.where,
      insertAtEnd: opts.insertAtEnd,
      onSaved: opts.onSaved,
      onClose: () => {
        wrap.remove();
        if (opts.onClose) opts.onClose();
      },
    });
    wrap.append(editor.root);
    document.body.append(wrap);
    editor.focus();
    return editor;
  }

  window.OrgEditor = { open };
})();
