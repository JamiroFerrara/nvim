# J.A.R.V.I.S. — the orb on the org dashboard

The dashboard's voice orb, specified. It is UI in the browser only: the page
draws it (`lua/helpers/org/web/assets/jarvis.css`, `jarvis.js`), and everything
behind it — a voice, a microphone, the `omp` run the words start — lives in
nvim (`lua/helpers/org/voice.lua`, routes `/api/voice`).

The rule the whole design follows: **nothing on screen is invented.** Every
number, colour and ripple is a state the server reported or a figure read from
the board. Where the brief below asks for something a browser cannot honestly
do, the section says so instead of faking it.

---

## 1. Central core (orb) — the brain

| | |
|---|---|
| Shape | one circle, `inset: 24%` of the rig; the rig opens to `min(58vmin, 500px)` |
| Surface | crystal: a white highlight at 33%/27%, a teal under-glow at 64%/70%, a dark body; a hard 1px rim (`::after`) so it reads as glass, not as a blur |
| Idle | pulses at 2 s, opacity 0.86 → 1, scale 1 → 1.05 |
| Speaking | size up 1px of inset, pulse 1.2 s, colour mauve → sky |
| Listening | pulse 1.1 s, colour sky → lavender, the body opens (inset 21%) |
| Thinking | pulse 0.9 s, colour amber → peach: the "puff" of a command being taken |
| Error | red → peach, a slow 1.8 s pulse, and one shake of 3 px each way |
| Ripple | a stroke circle scaled 0.35 → 1.25 and faded on every active phase (`--jv-ripple`, 2.2 s at rest: 1.4 s listening, 1 s thinking) |
| Filaments | a conic sweep masked to a ring at 58–74 % radius, spinning at half the ring clock — the "motion lines focusing toward" the core |
| Flash | one bright flash (`brightness 2.4`, scale 1.18) when a run starts |

The pulse is CSS `transform`/`opacity` only: no canvas, no per-frame work in
JS, and `prefers-reduced-motion` turns every animation off. Nothing here
animates `filter` or `box-shadow`, and the rings, the filament sweep and the
core carry `will-change` so they ride the compositor instead of being repainted
every frame.

## 2. Holographic data rings

Three concentric SVG rings around the orb, each on its own clock, all dashed so
rotation is legible:

| Ring | Radius (viewBox 100) | Stroke | Dash | Clock | Reads |
|---|---|---|---|---|---|
| inner `r1` | 46 | 0.35 | 2 6 | `--jv-spin` (9 s idle, 3 s listening, 1.8 s thinking) | locked to the orb's own colour |
| middle `r2` | 39 | 0.3 | 14 10 | `0.6 ×` the inner, reversed | the second colour of the phase |
| outer `r3` | 32 | 0.22 | 30 22 | `0.32 ×` the inner | faintest, so the outer band never competes with the core |

Speed is the processing indicator: the phase variables `--jv-spin` and
`--jv-ripple` are the only thing that changes, so rings, ripple and pulse stay
in one tempo without any JS animation loop. Colour comes from `--jv-a` /
`--jv-b`, set by the phase class, so the whole rig shifts palette in one place.

## 3. Floating panels

Four glass rectangles, one figure each, `172px` wide, a translucent gradient
fill (no `backdrop-filter`: blurring what sits behind them, while they float,
cost a repaint every frame), a 1px border at 22 % of the phase colour, and a
7 s float of 5 px with staggered delays. Hidden while the orb is shut, faded in
with the rig.

| Panel | Figure | Sub-line | Data |
|---|---|---|---|
| In flight | entries in `NEXT` + `TEST` | `n working · n to check` | `state.data` |
| Runs live | tickets with a run on them | batch sessions, or "no batch running" | `state.live` |
| Next up | title of the first `NEXT` | its project, or "the board is clear" | `state.data` |
| Vault | entries on the board | files they live in | `state.data` |

**Attention.** A panel turns amber (`--peach`, a fixed glow — it used to pulse,
but any animation on that panel made the browser redo style and layout on every
frame, and the pulse is not worth the whole rig's frame rate)
when the thing it counts is waiting on a person: *In flight* while any ticket
sits in `TEST` (a change nobody validated yet), *Next up* when nothing is
waiting at all. There is no red state on a panel: red belongs to a failed
conversation, and painting a panel red for a server error would misattribute
it to the board.

## 4. Voice and sound feedback

| | |
|---|---|
| Voice | **off by default.** The orb listens and starts a run; it does not talk. `speak = true` in `voice.setup`, or `OMP_VOICE_SPEAK=1`, brings back the local voice: piper, `espeak-ng`, `spd-say`, or Windows' own `System.Speech` voice through `powershell.exe` under WSL |
| Level | a 3 px bar under the orb, filled from the loudness nvim measures on the recording itself (RMS of each ~100 ms chunk, 0 at −55 dBFS and below, 1 at full scale), polled with the rest of the status. A dead microphone keeps it empty — this is the feedback that says whether the microphone is delivering anything at all |
| Dead microphone | while listening, if no chunk has passed a tenth of the meter after a second, the caption says `listening — no sound from the microphone`; a listen that ends with no sound at all ends in the red phase and the error `the microphone delivered no sound` |
| Sync | the orb is sky while listening, amber while the transcription and the hand-over run; the caption prints the same words |
| Confirmation | two-note chime (880 Hz then 1318 Hz, sine, WebAudio) and one flash of the rig when the heard words leave for a run |
| Errors | a 96 Hz sawtooth buzz, 0.4 s, and the reason on the caption |
| Waveform | **not drawn.** The microphone is read by nvim (`parec` on PulseAudio), never by the page, so a waveform here would be animation standing in for data the page never captured. The level bar is real: every value it draws came from the recording |

Voice style (calm, British, "intelligent") is whatever voice the machine has
installed; the module does not ship one. `OMP_VOICE_RATE` is honoured by the
Windows backend, which is the only one that exposes a rate control.

## 5. Real-time visualisation

Below the orb, a 40-column bar graph of the in-flight count, sampled every 2 s
for as long as the page is open, newest bar at full opacity, the rest at 35 %,
on a hairline floor. It is the vault's own count over the session — it starts
empty with the page, which is why it is short at first and grows toward the
right. Colour follows `--jv-a`, so a graph drawn while the orb thinks is amber.

The same figures are in the panels; the graph exists to show *movement* — a
ticket moving to `DONE` steps the count down, two new `NEXT` entries step it up.

---

## Interaction model

| Gesture | Result |
|---|---|
| Click the shut orb (bottom right, 84 px) | the rig opens in the middle of the page and the microphone opens |
| Click the orb while listening | the listen is cancelled (`{cancel: true}`) |
| Click the orb while speaking (voice on) or thinking | a toast: "still working — one moment" |
| Click the orb while idle (rig open) | another conversation |
| Click the backdrop, or `Escape` | the rig shuts; a listen already running keeps running and still ends in a run |
| Hover | the stage scales 1.04 |
| Keyboard | `Escape` only; the orb is a `<button>`, so `Tab`/`Enter` work through the page's own focus order |

Polling is 350 ms while the rig is open, and stops the moment it shuts; the
inspection at load is a single request. That poll only moves the phase, the
caption and the level bar: it does not rebuild the panels or the graph, which
read the dashboard's data on their own clock (every 2 s while the rig is open,
every 4 s behind it, and once as it opens), so a keyword changed in the list
shows up in them without a full recompute three times a second.

## What the medium rules out

- **A sphere or 3D depth.** The orb is a circle with layered radial gradients
  and a rim; no WebGL, so it holds its frame rate on a laptop while the vault
  is being walked in the background.
- **AR/UI touch on the rings.** The rings are decorative; the only interactive
  element is the orb.
- **Weather radar, health diagnostics, energy levels.** There is no such data
  here, so there are no panels for it. The four panels show the four things the
  dashboard actually knows.
- **A live microphone waveform.** See §4.

---

## The conversation behind it

1. `POST /api/voice` with `{view}` — the dashboard's current view title.
2. nvim (`helpers/org/voice.lua`) records through PulseAudio (`parec`) into a
   16 kHz mono wav, measuring each chunk on the way in and publishing the level
   on `GET /api/voice`; the orb draws it as the bar.
3. When the listening window ends (or a second click stops it), the wav goes to
   whisper.cpp, to a command of the user's, or to Windows' own recognizer run on
   the file. The transcript is the words the run receives.
4. The words go to a fresh `omp` pane (`helpers/org/ai.lua`'s `open_prompt`),
   carrying one line of context — that they were said on the dashboard, the
   view's name, and where the vault is. From there the run decides what to do
   inside the org system; the orb's part ends. When the voice is on, the
   transcript is spoken back first.
5. The page polls `GET /api/voice` for the phase, the level, the words heard
   and any error, and draws them.

Overrides, when detection guesses wrong: `OMP_VOICE_SPEAK`, `OMP_VOICE_TTS`,
`OMP_VOICE_STT`, `OMP_VOICE_WHISPER_MODEL`, `OMP_VOICE_LANG`,
`OMP_VOICE_PIPER_MODEL`, `OMP_VOICE_LISTEN_SECONDS`.
