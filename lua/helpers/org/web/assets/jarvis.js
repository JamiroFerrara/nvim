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
//
// Where the sound comes from depends on where the page is running. A page on
// this machine lets nvim record with the machine's own microphone, which is
// what it has always done. A page on another device -- a phone on the ngrok
// tunnel -- has the microphone the words should come from, so it captures the
// sound here and streams it up as raw 16 kHz mono PCM (`/api/voice/audio`):
// the server writes the same wav either way, so the level, the words so far
// and the transcription are unchanged. `?mic=browser` / `?mic=server` overrides
// the guess, for a machine whose PulseAudio is dead or a page that looks local
// and is not.

(() => {
  const PHASES = ['idle', 'speaking', 'listening', 'thinking', 'sent', 'error'];
  // the phases a capture still belongs to: a spoken ack is the same listen
  const HELD = ['speaking', 'listening'];
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
    // and saying so is what makes the pre-selection visible before the click.
    // Read off the page, not the server, so it follows the cursor.
    const picked = highlighted();
    return (picked && picked.title ? `ticket under “${picked.title}” — ` : '') + 'click the mic to speak';
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
    // the listen is over: the microphone goes with it, so the phone stops
    // showing that it is recording
    if (capture.stream && !capture.holding && !HELD.includes(phase)) closeMic();
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
    // this page's own microphone first, while the click is still the gesture
    // the browser asks permission for; the server is told which half records.
    // `holding` keeps a poll that lands mid-click from letting go of it
    let from = 'server';
    capture.holding = true;
    try {
      if (wanted()) {
        try {
          from = (await openMic()) ? 'browser' : 'server';
        } catch (err) {
          apply({ phase: 'error', error: micProblem(err) });
          return;
        }
      }
      const res = await fetch('/api/voice', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ view: viewTitle(), entry: highlighted(), source: from }),
      });
      const out = await res.json();
      if (out.status) apply(out.status);
      // a listen that never started, or one the machine records itself, has
      // nothing for this page to send: let the microphone go. A spoken ack
      // (`speaking`) is still the same listen, and the microphone stays held
      if (!out.status || out.status.source !== 'browser' || !HELD.includes(out.status.phase)) closeMic();
    } catch (err) {
      closeMic();
      apply({ phase: 'error', error: 'could not reach nvim' });
    } finally {
      capture.holding = false;
    }
  }

  async function cancel() {
    closeMic();
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
    if (capture.stream) {
      // the sentence is over: stop listening to the microphone, then let the
      // last quarter second go up before the server closes the wav
      capture.node.onaudioprocess = null;
      clearInterval(capture.timer);
      capture.timer = null;
      await pump();
    }
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

  // --------------------------------------------------- the page's microphone
  //
  // A page on another device -- a phone on the ngrok tunnel -- records with the
  // microphone that is actually in front of the person speaking, not the one on
  // the machine running nvim. `getUserMedia` hands that microphone over, an
  // AudioContext turns it into the format the server's wav holds (16 kHz, mono,
  // 16-bit PCM), and a quarter second of it goes up at a time: the server
  // measures the level and reads the words as the sound lands, exactly what it
  // does with a recorder of its own.

  const PCM_RATE = 16000; // the wav the server writes, whatever recorded it
  const SEND_MS = 250; // one upload per quarter second: the meter follows closely

  const capture = {
    stream: null, // the microphone's tracks, released when the listen ends
    ctx: null, // the graph that reads them
    node: null,
    gain: null,
    timer: null, // the upload clock
    pending: [], // pieces of PCM not yet uploaded
    floats: [], // samples not yet resampled, and where the read position sits
    pos: 0,
    sending: null, // the upload in flight, so the next one waits for it
    from: 0, // the context's own rate, which is not always the one asked for
    holding: false, // a click is mid-flight: do not let go of the microphone
  };

  // A page on this machine lets nvim record with the machine's microphone; any
  // other address is a device whose own microphone is the right one. A browser
  // that cannot capture (an http address, no permission) falls back to the
  // machine's, which is what it did before. `?mic=browser` / `?mic=server` say
  // it by hand.
  function wanted() {
    const asked = new URLSearchParams(location.search).get('mic');
    if (asked === 'browser') return true;
    if (asked === 'server') return false;
    const host = location.hostname;
    return !(host === 'localhost' || host === '127.0.0.1' || host === '::1' || host === '[::1]');
  }

  function micProblem(err) {
    const name = (err && err.name) || '';
    if (name === 'NotAllowedError' || name === 'SecurityError') return 'the browser refused the microphone';
    if (name === 'NotFoundError' || name === 'DevicesNotFoundError') return 'this device has no microphone';
    return name ? `could not open the microphone (${name})` : 'could not open the microphone';
  }

  // The microphone runs at whatever the device does -- 48 kHz on most phones --
  // and the server's wav names 16 kHz, so the samples are thinned here. Linear
  // interpolation is enough for speech; the fractional position is carried
  // across blocks so the sentence keeps its pitch and its length.
  function resample(input) {
    const step = capture.from / PCM_RATE;
    const held = capture.floats;
    for (let i = 0; i < input.length; i++) held.push(input[i]);
    const out = [];
    let pos = capture.pos;
    while (pos + 1 < held.length) {
      const i = Math.floor(pos);
      const frac = pos - i;
      out.push(held[i] * (1 - frac) + held[i + 1] * frac);
      pos += step;
    }
    const cut = Math.floor(pos);
    if (cut > 0) {
      held.splice(0, cut);
      pos -= cut;
    }
    capture.pos = pos;
    return out;
  }

  // floats between -1 and 1, as the 16-bit little-endian samples the wav
  // holds. Every browser that can run this page is little-endian.
  function pcm(samples) {
    const out = new Int16Array(samples.length);
    for (let i = 0; i < samples.length; i++) {
      out[i] = Math.max(-1, Math.min(1, samples[i])) * 0x7fff;
    }
    return new Uint8Array(out.buffer);
  }

  // One piece at a time: the server appends what arrives, so two uploads in
  // flight together could land out of order and shuffle the sentence.
  function pump() {
    if (capture.sending) return capture.sending;
    const run = (async () => {
      while (capture.pending.length) {
        const body = new Blob(capture.pending);
        capture.pending = [];
        try {
          await fetch('/api/voice/audio', { method: 'POST', body });
        } catch (err) {
          // the nvim behind the page went away; the next poll says so
          capture.pending = [];
          break;
        }
      }
    })();
    capture.sending = run;
    run.finally(() => {
      if (capture.sending === run) capture.sending = null;
    });
    return run;
  }

  // Open this page's microphone. Called from the click itself: a browser that
  // asks permission out of a user gesture refuses it.
  async function openMic() {
    if (capture.stream) return true;
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) return false;
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true, autoGainControl: true },
    });
    let ctx;
    try {
      ctx = new AudioContext({ sampleRate: PCM_RATE });
    } catch (err) {
      // an engine that will not be told its rate: the resampler makes up for it
      ctx = new AudioContext();
    }
    await ctx.resume();
    capture.stream = stream;
    capture.ctx = ctx;
    capture.from = ctx.sampleRate;
    const source = ctx.createMediaStreamSource(stream);
    // 4096 samples is about 85 ms at 48 kHz: short enough for the meter to
    // follow, long enough that the page is not woken every few samples
    const node = ctx.createScriptProcessor(4096, 1, 1);
    node.onaudioprocess = (ev) => {
      // the server is still saying its piece, or already reading back: what
      // the microphone picks up now is not part of the sentence it recorded
      if (status.phase !== 'listening') return;
      capture.pending.push(pcm(resample(ev.inputBuffer.getChannelData(0))));
    };
    source.connect(node);
    // a ScriptProcessor only runs while something listens to its output, and
    // nothing should hear the microphone: a silent gain is the listener
    const gain = ctx.createGain();
    gain.gain.value = 0;
    node.connect(gain).connect(ctx.destination);
    capture.node = node;
    capture.gain = gain;
    capture.pending = [];
    capture.floats = [];
    capture.pos = 0;
    capture.timer = setInterval(pump, SEND_MS);
    return true;
  }

  function closeMic() {
    clearInterval(capture.timer);
    capture.timer = null;
    if (capture.node) capture.node.onaudioprocess = null;
    if (capture.stream) {
      for (const track of capture.stream.getTracks()) track.stop();
    }
    if (capture.ctx && capture.ctx.state !== 'closed') {
      capture.ctx.close().catch(() => {});
    }
    capture.stream = null;
    capture.node = null;
    capture.gain = null;
    capture.ctx = null;
    capture.pending = [];
    capture.floats = [];
    capture.pos = 0;
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
