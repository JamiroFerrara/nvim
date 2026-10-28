// J.A.R.V.I.S. -- the orb, the rings, the panels and the graphs the dashboard
// draws for itself. UI only: the voice, the microphone and the run the words
// start live in nvim (helpers/org/voice.lua, through /api/voice).
//
// The five parts of the interface, and where each one gets its state:
//
//   1. the core orb        -- the phase the server reports: idle breathes
//                            cyan, speaking opens mauve, thinking runs amber,
//                            a failure holds red and shakes once
//   2. the three rings     -- decoration over the same state; they spin on
//                            their own clocks, faster while it works, and a
//                            ripple leaves the core on every active phase
//   3. the glass panels    -- numbers read out of the dashboard's own data
//                            (state.data / state.live), one figure each. A
//                            panel turns amber when the thing it counts is
//                            waiting on a person -- tickets in TEST
//   4. voice feedback      -- a level bar under the orb while it listens, fed
//                            by the loudness nvim measures on the recording
//                            itself, so a dead microphone reads as dead; plus
//                            a chime when a run starts and a low buzz when the
//                            machine reports an error. No waveform is drawn:
//                            the browser never sees the microphone
//   5. the graphs          -- the vault's in-flight count sampled over the
//                            session and drawn as bars, plus the same figures
//                            the panels print
//
// The orb does not speak: nvim stays quiet unless the voice is turned on. A
// click starts the listen; a second click cancels it; Escape closes the rig.

(() => {
  const PHASES = ['idle', 'speaking', 'listening', 'thinking', 'error'];
  const RING = [
    { cls: 'r1', r: 46, cx: 50, cy: 50 },
    { cls: 'r2', r: 39, cx: 50, cy: 50 },
    { cls: 'r3', r: 32, cx: 50, cy: 50 },
  ];

  const root = document.createElement('div');
  root.id = 'jarvis';
  root.className = 'phase-idle';
  root.innerHTML = `
    <div class="jv-backdrop"></div>
    <div class="jv-rig">
    <button class="jv-stage" type="button" title="J.A.R.V.I.S. — speak, and a run starts from it" aria-label="Talk to J.A.R.V.I.S.">
      <span class="jv-rings">
        <svg viewBox="0 0 100 100" aria-hidden="true">
          ${RING.map((r) => `<circle class="jv-ring ${r.cls}" cx="${r.cx}" cy="${r.cy}" r="${r.r}" />`).join('')}
          <circle class="jv-ripple" cx="50" cy="50" r="40" />
        </svg>
      </span>
      <span class="jv-filaments"></span>
      <span class="jv-core"></span>
    </button>
    <div class="jv-panels">
      <div class="jv-panel p1"><span class="k">In flight</span><span class="v">—</span><span class="s"></span></div>
      <div class="jv-panel p2"><span class="k">Runs live</span><span class="v">—</span><span class="s"></span></div>
      <div class="jv-panel p3"><span class="k">Next up</span><span class="v">—</span><span class="s"></span></div>
      <div class="jv-panel p4"><span class="k">Vault</span><span class="v">—</span><span class="s"></span></div>
    </div>
    <div class="jv-graph"><canvas width="420" height="88"></canvas></div>
    <div class="jv-meter" aria-hidden="true"><span class="jv-meter-fill"></span></div>
    <div class="jv-caption" aria-live="polite">click to speak</div>
    </div>
  `;

  const stage = root.querySelector('.jv-stage');
  const ripple = root.querySelector('.jv-ripple');
  const caption = root.querySelector('.jv-caption');
  const panels = {
    flight: root.querySelector('.p1'),
    runs: root.querySelector('.p2'),
    next: root.querySelector('.p3'),
    vault: root.querySelector('.p4'),
  };
  const graph = root.querySelector('.jv-graph canvas');
  const meter = root.querySelector('.jv-meter');
  const meterFill = root.querySelector('.jv-meter-fill');

  let open = false;
  let status = { phase: 'idle', heard: '', view: '', error: '', tts: false, stt: false, speak: false, level: 0, level_db: null, signal: false };
  let poller = null;
  let sampler = null;
  let last = 'idle';
  const history = []; // the in-flight count, one sample per tick

  // -------------------------------------------------------------- the data

  // Every entry the page holds, once each: one entry is listed by several
  // views, so the counts are taken over a set keyed on where it lives.
  function entries() {
    const data = typeof state !== 'undefined' && state ? state.data : null;
    if (!data) return [];
    const seen = new Map();
    for (const view of data.views || []) {
      for (const section of view.sections || []) {
        for (const entry of section.items || []) {
          const key = `${entry.file}:${entry.line}:${entry.id || ''}`;
          if (!seen.has(key)) seen.set(key, entry);
        }
      }
    }
    return [...seen.values()];
  }

  function live() {
    if (typeof state === 'undefined' || !state || !state.live) return { tickets: 0, sessions: 0 };
    return { tickets: state.live.tickets.size, sessions: state.live.sessions.size };
  }

  function viewTitle() {
    if (typeof state === 'undefined' || !state || !state.data) return '';
    const view = (state.data.views || []).find((v) => v.key === state.view);
    return view ? view.title : '';
  }

  function setPanel(node, value, sub) {
    node.querySelector('.v').textContent = value;
    node.querySelector('.s').textContent = sub || '';
  }

  function metrics() {
    const all = entries();
    const next = all.filter((e) => e.todo === 'NEXT');
    const wait = all.filter((e) => e.todo === 'TEST');
    const flights = next.length + wait.length;
    const files = new Set(all.map((e) => e.file)).size;
    const runs = live();

    setPanel(panels.flight, String(flights), `${next.length} working · ${wait.length} to check`);
    panels.flight.classList.toggle('alert', wait.length > 0);

    setPanel(panels.runs, String(runs.tickets), runs.sessions ? `${runs.sessions} batch sessions` : 'no batch running');

    const up = next[0];
    setPanel(panels.next, up ? up.title : 'nothing waiting', up ? up.project || up.file : 'the board is clear');
    panels.next.classList.toggle('alert', !up);

    setPanel(panels.vault, String(all.length), `${files} files on the board`);

    history.push(flights);
    if (history.length > 40) history.shift();
    drawGraph();
    return { flights, wait: wait.length };
  }

  function drawGraph() {
    const ctx = graph.getContext('2d');
    const w = graph.width;
    const h = graph.height;
    ctx.clearRect(0, 0, w, h);
    if (!history.length) return;
    const top = Math.max(4, ...history);
    const step = w / Math.max(1, history.length);
    const bar = Math.max(2, step * 0.6);
    const accent = getComputedStyle(root).getPropertyValue('--jv-a').trim() || '#89dceb';
    ctx.fillStyle = accent;
    history.forEach((n, i) => {
      const height = Math.max(2, (n / top) * (h - 12));
      ctx.globalAlpha = i === history.length - 1 ? 0.95 : 0.35;
      ctx.fillRect(i * step + (step - bar) / 2, h - height, bar, height);
    });
    // the floor the bars stand on: one hairline, so an empty vault still reads
    // as a graph rather than a blank box
    ctx.globalAlpha = 0.25;
    ctx.fillRect(0, h - 1, w, 1);
    ctx.globalAlpha = 1;
  }

  // ------------------------------------------------------------ the phases

  function captionFor(s) {
    switch (s.phase) {
      case 'speaking':
        return 'speaking';
      case 'listening':
        // the meter has had a second to move: if it has not, the microphone
        // is not delivering anything and the caption says so instead of
        // asking the user to speak into a dead device
        if (!s.signal && s.at && Date.now() / 1000 - s.at >= 1) return 'listening — no sound from the microphone · click to stop';
        return 'listening — click to stop';
      case 'thinking':
        return 'handing it to a run';
      case 'error':
        return s.error || 'something went wrong';
      default:
        if (s.stt === false) return 'no microphone on this machine';
        return s.heard ? `“${s.heard}”` : 'click to speak';
    }
  }

  function apply(s) {
    const phase = PHASES.includes(s.phase) ? s.phase : 'idle';
    status = { ...status, ...s, phase };
    root.className = `phase-${phase}${open ? ' open' : ''}`;
    caption.textContent = captionFor(status);
    stage.title = phase === 'listening' ? 'J.A.R.V.I.S. — listening, click to stop' : 'J.A.R.V.I.S. — speak, and a run starts from it';

    // the level is the recording's own loudness, polled at 350 ms: the fill
    // rides a transform so the bar costs a composite and not a paint
    const level = Math.max(0, Math.min(1, Number(status.level) || 0));
    meterFill.style.transform = `scaleX(${level.toFixed(3)})`;
    meter.classList.toggle('on', phase === 'listening');
    if (phase !== 'listening') meter.title = '';
    else if (!status.signal) meter.title = 'the microphone is delivering no sound';
    else meter.title = `${Math.round(status.level_db || 0)} dB`;

    ripple.classList.toggle('on', phase === 'speaking' || phase === 'listening' || phase === 'thinking');

    if (phase !== last) {
      if (phase === 'idle' && last === 'thinking' && status.heard) {
        chime();
        flash();
        if (typeof showToast === 'function') showToast(`J.A.R.V.I.S. → ${status.heard}`);
      }
      if (phase === 'error') buzz();
      last = phase;
    }
  }

  async function poll() {
    try {
      const res = await fetch('/api/voice');
      if (!res.ok) return;
      apply(await res.json());
    } catch (err) {
      // the nvim behind the page went away; the orb says so on the next click
    }
  }

  async function start() {
    try {
      const res = await fetch('/api/voice', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ view: viewTitle() }),
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
  // did not: both are the page's own feedback, made with the audio the page
  // already has, not a reading of the microphone
  function chime() {
    try {
      audio = audio || new AudioContext();
      tone(880, 0, 0.18, 'sine', 0.05);
      tone(1318, 0.11, 0.28, 'sine', 0.04);
    } catch (err) {
      // no audio context (a page without a gesture yet): silent
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

  function flash() {
    root.classList.add('flash');
    setTimeout(() => root.classList.remove('flash'), 750);
  }

  // ---------------------------------------------------------- the opening

  function setOpen(next) {
    open = next;
    root.classList.toggle('open', open);
    if (open) {
      if (!poller) poller = setInterval(poll, 350);
      if (!sampler) sampler = setInterval(metrics, 2000);
      poll();
      metrics();
    } else {
      clearInterval(poller);
      poller = null;
      clearInterval(sampler);
      sampler = null;
    }
  }

  stage.addEventListener('click', (ev) => {
    ev.stopPropagation();
    if (status.phase === 'listening') {
      cancel();
      return;
    }
    if (status.phase === 'speaking' || status.phase === 'thinking') {
      if (typeof showToast === 'function') showToast('still working — one moment');
      return;
    }
    if (!open) setOpen(true);
    start();
  });

  root.querySelector('.jv-backdrop').addEventListener('click', () => setOpen(false));

  // Escape closes the rig and nothing else: the dashboard's own Escape must
  // still work when the orb is shut
  window.addEventListener(
    'keydown',
    (ev) => {
      if (ev.key !== 'Escape' || !open) return;
      ev.stopPropagation();
      ev.preventDefault();
      setOpen(false);
    },
    true
  );

  document.body.append(root);
  poll();

  // the dashboard reloads its data itself (load() after a write, the live
  // stream while runs are out); the panels follow it on their own clock so a
  // keyword changed in the list shows up in the figures too
  setInterval(() => {
    if (typeof state !== 'undefined' && state && state.data) metrics();
  }, 4000);
})();
