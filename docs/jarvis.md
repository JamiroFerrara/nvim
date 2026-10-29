# J.A.R.V.I.S. — the recording card on the org dashboard

The dashboard's voice control, specified. It is UI in the browser only: the page
draws it (`lua/helpers/org/web/assets/jarvis.css`, `jarvis.js`), and everything
behind it — a voice, a microphone, the `omp` run the words start — lives in
nvim (`lua/helpers/org/voice.lua`, routes `/api/voice`).

The rule the whole design follows: **nothing on screen is invented.** Every
word, level and phase is a state the server reported.

The card replaced the full-screen orb rig. Two reasons, both from using it: the
rings, the floating panels and the graphs were animation the click did not need,
and a listen that took over the whole page hid the board underneath it.

---

## 1. The button

One round button, 46 px, fixed in the bottom-right corner — in the same spot in
every phase, whatever the page is doing.

| | |
|---|---|
| Idle | dark, a sky-coloured outline, the microphone glyph |
| Listening | filled sky, the glyph in the page's darkest ink (`--crust`), `aria-pressed="true"` |
| Working (speaking, transcribing) | greyed, `cursor: progress`; a click answers with the toast "still working — one moment" |
| Error | a red outline, so the failure is visible before the card is read |

Nothing is ever drawn over the button: the card grows upward from it, so the
click that opens and closes a listen lands on the same pixels every time.

## 2. The card

A block above the button, `320px` wide and at most `40vh` tall (it scrolls past
that), hidden until a listen runs. It holds, top to bottom:

| Part | What it says | Where it comes from |
|---|---|---|
| Head | `listening`, `reading it back`, `could not listen`, `ready` | `phase` |
| Dot | the phase colour; it blinks while a listen runs (`steps(2)`), and does not move at all under `prefers-reduced-motion` | `phase` |
| Meter | one 3 px bar, the microphone's own loudness (RMS of each ~100 ms chunk, 0 at −55 dBFS, 1 at full scale) | `level`, `level_db` |
| Words | the sentence as it is being transcribed, then the words it came to | `partial`, `heard` |
| Hint | `click the mic to stop`, `no sound from the microphone`, `handing it to a run`, `click the mic to try again` | `signal`, `at`, `phase`, `stt` |

The card stays up for five seconds after a listen ends, so the last words can be
read, then folds back into the button. An error stays until the next click.

**The words while you speak** are the point of the card. While a listen runs,
nvim re-reads the recording every 1.5 s and publishes what it has made of it so
far as `partial`; the card prints it, so a word the recognizer heard wrong is
visible while the sentence is still being said — stop the listen and say it
again instead of watching the wrong words start a run. One read at a time: a
transcriber slower than the clock skips a turn rather than stacking up.

Colours follow the phase — sky while listening, amber while the words are read,
mauve while the voice speaks, red on a failure — and come from the dashboard's
own palette (`org.css`).

## 3. Voice and sound feedback

| | |
|---|---|
| Voice | **off by default.** The card records and starts a run; it does not talk. `speak = true` in `voice.setup`, or `OMP_VOICE_SPEAK=1`, brings back the local voice: piper, `espeak-ng`, `spd-say`, or Windows' own `System.Speech` voice through `powershell.exe` under WSL |
| Level | the 3 px bar, fed by the loudness nvim measures on the recording itself. A dead microphone keeps it empty — this is the feedback that says whether the microphone is delivering anything at all |
| Dead microphone | while listening, if no chunk has filled part of the bar after a second, the hint says `no sound from the microphone`; a listen that ends with no sound at all ends in the red phase and the error `the microphone delivered no sound` |
| Confirmation | two-note chime (880 Hz then 1318 Hz, sine, WebAudio) and a toast with the words when they leave for a run |
| Errors | a 96 Hz sawtooth buzz, 0.4 s, and the reason on the card |
| Waveform | **not drawn.** The microphone is read by nvim (`parec` on PulseAudio), never by the page, so a waveform here would be animation standing in for data the page never captured. The level bar is real: every value it draws came from the recording |

Voice style (calm, British, "intelligent") is whatever voice the machine has
installed; the module does not ship one.

---

## Interaction model

| Gesture | Result |
|---|---|
| Click the button while idle or failed | a listen starts (`POST /api/voice` with the view's title) |
| Click the button while listening | the listen is cancelled (`{cancel: true}`); the recording is dropped |
| Click the button while speaking (voice on) or transcribing | a toast: "still working — one moment" |
| `Escape` while listening | the same cancel; at any other time the key is left to the page |
| `Tab` / `Enter` | the button is a `<button>`, so the page's own focus order reaches it |

Polling is 300 ms while a listen runs and 1.5 s while idle, so a listen started
from anywhere else in nvim (`:OrgVoice`) shows up on screen within a second and
a half.

## The conversation behind it

1. `POST /api/voice` with `{view, entry}` — the dashboard's current view title,
   and the entry the list has highlighted (its file, line, `:ID:` and title, or
   nothing when none is).
2. nvim (`helpers/org/voice.lua`) records through PulseAudio (`parec`) into a
   16 kHz mono wav, measuring each chunk on the way in and publishing the level
   on `GET /api/voice`; the card draws it as the bar.
3. Every 1.5 s the bytes recorded so far are copied into a whole wav and read
   again by the same transcriber, and the words land on `partial`: the sentence
   shows up as it is said. `OMP_VOICE_PARTIAL` sets that clock (`0` turns the
   re-reads off).
4. When the listening window ends (or a second click stops it), the whole wav
   goes to Handy's own model, to whisper.cpp, to a command of the user's, or to
   Windows' own recognizer run on the file. The transcript is the words the run
   receives. whisper.cpp reads the finished sentence with the best English
   model on the machine (`ggml-small.en.bin` before `ggml-base.en.bin`, and so
   on up to `ggml-medium.en.bin`; `OMP_VOICE_WHISPER_MODEL` or
   `whisper_model` in setup overrides), and the sentence while it is still
   being said with `ggml-base.en.bin` if it is there: reading a recording costs
   the same whatever its length — whisper encodes a fixed thirty seconds — so
   the words on the card come from the quick model and the words that start a
   run come from the accurate one. A read of a sentence takes a few seconds on
   a CPU; it is the only slow part of a listen.
5. The words go to the talking instance (`helpers/org/ai.lua`'s
   `open_prompt`): one `omp`, in its own session (`talk/one`) and one pane, that
   every line from the card, `:OrgVoice` and `:OrgVoiceSay` reaches. A later
   line is typed into that instance rather than starting another one, so "that
   one too" arrives in the conversation the first line started. The words ride
   along with the spec file the instance reads: the view they were said on and,
   when the page had something highlighted, the file and the entry's `:ID:`.

   What the instance does with them is its own rules' business, and the rules
   are written for one shape: a question is answered in the pane, and work is
   filed and started with one command (`ai.talk`) — the `TODO` headline (nested
   under the highlighted entry when there was one, else at the end of the
   project file), its body the words under the capture header, then the same
   drawer (`:ID:`, `:OMP_SESSION:`, `:OMP_LAUNCH:`), the claim to `NEXT`, the
   project checkpoint and the pane any `<leader>ai` launch gives a ticket. The
   file is written before the run is dispatched, so the board shows the work
   started as soon as the words are filed, and the dispatch is what takes the
   time. The card says which entry the words will hang under —
   `ticket under “…” — click the mic to speak`.

   The card's part ends when the words reach the instance: it says where they
   went and folds, because the instance stays up for the next line; the run the
   words became is watched in the runs window (`<leader>ov`). When the voice is
   on, the transcript is spoken back first.

A recording that never rose above the meter's floor is an error, not a listen:
a transcriber asked about silence still answers — whisper makes a word of it,
`you`, or `(crickets chirping)` — and non-speech markers like that are cut from
the words before they are used.

The transcriber is Handy's own model when both halves are there — the Windows
dictation app installed, and `transcribe-cli` (the command line of
[transcribe.cpp](https://github.com/handy-computer/transcribe.cpp), the engine
Handy ships) on `PATH`. Handy keeps its models in the Windows profile's Hugging
Face cache and names the one in use in its settings; the run reads that name, so
whichever model is picked in Handy is the one dictation uses here, and changing
it there changes it here. The model file has to be readable from the Linux side,
and a memory-mapped read straight off the Windows drive is slow enough to turn a
sentence into half a minute, so it is copied once into `~/.cache/omp/voice` and
read from there — until that first copy lands, a listen falls back to whatever
else is installed. (`transcribe-cli` builds with `cmake -B build && cmake
--build build` in that repository; `build/bin/transcribe-cli` is the file to
put on `PATH`.)

Failing that, whisper.cpp when the machine has it — `whisper-cli` on `PATH`, and
a `ggml-*.bin` model in `~/.local/share/whisper`, `~/.cache/whisper` or
`/usr/share/whisper.cpp` — and Windows' own recognizer when it does not. The
Windows one is the reason the model matters: it reads clear speech and then
loses the sentence in room noise (`this is a vocal command test` came back as
`was the motive mom's house`), where Handy's model gets it right on the same
audio.

Overrides, when detection guesses wrong: `OMP_VOICE_SPEAK`, `OMP_VOICE_TTS`,
`OMP_VOICE_STT`, `OMP_VOICE_HANDY_MODEL` (a gguf path),
`OMP_VOICE_WHISPER_MODEL`, `OMP_VOICE_LANG`, `OMP_VOICE_PIPER_MODEL`,
`OMP_VOICE_LISTEN_SECONDS`, `OMP_VOICE_PARTIAL`.
