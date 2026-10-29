// J.A.R.V.I.S. -- the recording card in the corner of the dashboard.
//
// Two things, and nothing else:
//
//   1. the microphone button   -- always in the same spot, always clickable.
//                                A click records; a second click stops.
//   2. the card above it       -- what the server says the listen is doing:
//                                the level of the microphone, and the words
//                                it has made of the sentence so far, so they
//                                can be read while they are still being said.
//
// Nothing here is invented: the phase, the level and the words all come from
// `GET /api/voice` (helpers/org/voice.lua). The card shows itself while a
// listen is running, and stays a few seconds after it ends so the last words
// can be read, then folds back into the button.

(() => {
  const PHASES = ['idle', 'speaking', 'listening', 'thinking', 'sent', 'error'];
  const LINGER = 5000; // how long the finished words stay on screen
  const FAST = 300; // poll while a listen runs: the level and the words move
  const SLOW = 1500; // poll while idle

  const root = document.createElement('div');
  root.id = 'jarvis';
  root.className = 'phase-idle';
  root.innerHTML = `
    <div class="jv-card" aria-live="polite">
      <div class="jv-head"><span class="jv-dot"></span><span class="jv-state">idle</span></div>
      <div class="jv-meter"><span class="jv-meter-fill"></span></div>
      <div class="jv-text"></div>
      <div class="jv-run" hidden></div>
      <div class="jv-hint"></div>
    </div>
    <button class="jv-mic" type="button" aria-label="Record a line for J.A.R.V.I.S." title="click to speak, click again to stop">
      <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
        <path d="M12 3.5a3 3 0 0 1 3 3v5a3 3 0 0 1-6 0v-5a3 3 0 0 1 3-3z" />
        <path d="M5.5 11a6.5 6.5 0 0 0 13 0" />
        <path d="M12 17.5V21" />
      </svg>
    </button>
  `;

  const card = root.querySelector('.jv-card');
  const stateLabel = root.querySelector('.jv-state');
  const textLine = root.querySelector('.jv-text');
  const runLine = root.querySelector('.jv-run');
  const hintLine = root.querySelector('.jv-hint');
  const meter = root.querySelector('.jv-meter');
  const meterFill = root.querySelector('.jv-meter-fill');
  const mic = root.querySelector('.jv-mic');

  let status = {
    phase: 'idle',
    heard: '',
    partial: '',
    error: '',
    at: 0,
    level: 0,
    level_db: null,
    signal: false,
    run: null,
    stt: true,
  };
  let linger = 0; // when the finished words stop showing
  let last = 'idle';
  let timer = null;

  // ---------------------------------------------------------------- drawing

  const WORDS = {
    idle: 'ready',
    speaking: 'speaking',
    listening: 'listening',
    thinking: 'reading it back',
    sent: 'with the run',
    error: 'could not listen',
  };

  function words(s) {
    switch (s.phase) {
      case 'listening':
        return s.partial || (s.signal ? '…' : 'say something');
      case 'thinking':
        return s.heard || s.partial;
      case 'sent':
        return s.heard;
      case 'error':
        return s.error;
      default:
        return s.heard;
    }
  }

  function hint(s) {
    if (s.phase === 'listening') {
      // the meter has had a second to move: if it has not, the microphone is
      // not delivering anything and the hint says so instead of asking the
      // user to speak into a dead device
      if (!s.signal && s.at && Date.now() / 1000 - s.at >= 1) return 'no sound from the microphone';
      return 'click the mic to stop and keep the words';
    }
    if (s.phase === 'thinking') return 'reading it back';
    if (s.phase === 'sent') return 'click the mic to say more';
    if (s.phase === 'error') return 'click the mic to try again';
    if (s.stt === false) return 'no microphone on this machine';
    // the entry the list has highlighted: the words become a ticket under it,
    // and saying so is what makes the pre-selection visible before the click
    const under = s.target && s.target.title ? `under “${s.target.title}”` : '';
    return (under ? `ticket ${under} — ` : '') + 'click the mic to speak';
  }

  // the run holding the words: which pane, and whether it is still working.
  // The server asks tmux, so this is the run's own state, not a guess.
  function runText(s) {
    const run = s.run;
    if (!run || !run.pane) return '';
    return `${run.alive ? '▶' : '■'} run ${run.pane} — ${run.alive ? 'working on it' : 'finished'}`;
  }

  function render() {
    const phase = status.phase;
    const shown = phase !== 'idle' || Date.now() < linger;
    root.className = `phase-${phase}${shown ? ' card-on' : ''}`;

    stateLabel.textContent = WORDS[phase] || phase;
    textLine.textContent = words(status) || '';
    hintLine.textContent = hint(status);

    const run = runText(status);
    runLine.hidden = !shown || run === '';
    runLine.textContent = run;
    runLine.classList.toggle('run-done', Boolean(status.run) && !status.run.alive);

    const level = Math.max(0, Math.min(1, Number(status.level) || 0));
    meterFill.style.transform = `scaleX(${level.toFixed(3)})`;
    meter.hidden = phase !== 'listening';

    mic.title =
      phase === 'listening'
        ? 'click to stop and keep the words'
        : phase === 'thinking' || phase === 'speaking'
          ? 'still working'
          : 'click to speak';
    mic.setAttribute('aria-pressed', phase === 'listening' ? 'true' : 'false');

    // the words sit at the bottom of a box that grows: keep the newest line
    // in view as the sentence gets longer
    card.scrollTop = card.scrollHeight;
  }

  // ------------------------------------------------------------------ state

  function apply(next) {
    const phase = PHASES.includes(next.phase) ? next.phase : 'idle';
    status = { ...status, ...next, phase };

    if (phase !== last) {
      if (phase === 'sent' && status.heard) {
        chime();
        toast(`J.A.R.V.I.S. → ${status.heard}`);
        linger = Date.now() + LINGER;
      }
      if (phase === 'error') {
        buzz();
        linger = Date.now() + LINGER;
      }
      last = phase;
    }
    render();
  }

  function toast(text) {
    if (typeof showToast === 'function') showToast(text);
  }

  async function poll() {
    try {
      const res = await fetch('/api/voice');
      if (res.ok) apply(await res.json());
    } catch (err) {
      // the nvim behind the page went away; the next click says so
    }
  }

  async function start() {
    try {
      const res = await fetch('/api/voice', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ view: viewTitle(), entry: highlighted() }),
      });
      const out = await res.json();
      if (out.status) apply(out.status);
    } catch (err) {
      apply({ phase: 'error', error: 'could not reach nvim' });
    }
  }

  async function cancel() {
    try {
      const res = await fetch('/api/voice', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ cancel: true }),
      });
      const out = await res.json();
      if (out.status) apply(out.status);
    } catch (err) {
      apply({ phase: 'idle' });
    }
  }

  // the second click: finish the recording and keep what it heard
  async function stop() {
    try {
      const res = await fetch('/api/voice', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ stop: true }),
      });
      const out = await res.json();
      if (out.status) apply(out.status);
    } catch (err) {
      // the poll will say what happened
    }
  }

  function viewTitle() {
    if (typeof state === 'undefined' || !state || !state.data) return '';
    const view = (state.data.views || []).find((v) => v.key === state.view);
    return view ? view.title : '';
  }

  // What the list has highlighted: the words become a ticket under it, so the
  // run is pre-selected inside the project the page is showing. A page with
  // nothing highlighted sends none, and the run works the words out itself.
  // Only the identity travels -- the file, the line, the :ID: and the title --
  // and nvim resolves it against the vault (helpers/org/web/actions.lua), so a
  // page cannot name a headline it did not draw.
  function highlighted() {
    if (typeof state === 'undefined' || !state || !state.selectedEntry) return null;
    const entry = state.selectedEntry;
    if (!entry || !entry.file) return null;
    return { file: entry.file, line: entry.line, id: entry.id || '', title: entry.title || '' };
  }

  // ------------------------------------------------------------------- loop

  async function tick() {
    await poll();
    render(); // the linger can run out between two answers
    timer = setTimeout(tick, status.phase === 'idle' ? SLOW : FAST);
  }

  // ------------------------------------------------------------- the sound

  let audio = null;
  function tone(freq, at, dur, type, gain) {
    if (!audio) return;
    const osc = audio.createOscillator();
    const amp = audio.createGain();
    osc.type = type;
    osc.frequency.value = freq;
    amp.gain.setValueAtTime(0, audio.currentTime + at);
    amp.gain.linearRampToValueAtTime(gain, audio.currentTime + at + 0.02);
    amp.gain.exponentialRampToValueAtTime(0.0001, audio.currentTime + at + dur);
    osc.connect(amp).connect(audio.destination);
    osc.start(audio.currentTime + at);
    osc.stop(audio.currentTime + at + dur + 0.05);
  }

  // the confirmation chime of a run that started, and the low buzz of one that
  // did not: the page's own feedback, not a reading of the microphone
  function chime() {
    try {
      audio = audio || new AudioContext();
      tone(880, 0, 0.18, 'sine', 0.05);
      tone(1318, 0.11, 0.28, 'sine', 0.04);
    } catch (err) {
      // no audio context: silent
    }
  }

  function buzz() {
    try {
      audio = audio || new AudioContext();
      tone(96, 0, 0.4, 'sawtooth', 0.05);
    } catch (err) {
      // silent
    }
  }

  // ---------------------------------------------------------------- clicking

  mic.addEventListener('click', () => {
    const phase = status.phase;
    if (phase === 'listening') {
      stop();
      return;
    }
    if (phase === 'speaking' || phase === 'thinking') {
      toast('still working — one moment');
      return;
    }
    start();
  });

  window.addEventListener(
    'keydown',
    (ev) => {
      if (ev.key !== 'Escape' || status.phase !== 'listening') return;
      ev.stopPropagation();
      ev.preventDefault();
      cancel();
    },
    true
  );

  document.body.append(root);
  render();
  tick();
})();
