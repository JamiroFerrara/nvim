-- The voice buddy's engine: what sits behind the recording card on the org
-- dashboard (lua/helpers/org/web/assets/jarvis.js, served by helpers/org/web/).
--
-- The card is UI and lives in the browser; this is the part that needs the
-- machine. A click comes in as `POST /api/voice` (helpers/org/web/init.lua)
-- and the conversation runs here:
--
--   1. listen -- record through PulseAudio and report the level as it goes,
--      so a machine whose microphone is dead looks dead instead of silent
--      -- or, when the click came from a page running on a device that has a
--      microphone of its own (a phone on the ngrok tunnel), from that
--      microphone: the page captures the sound and streams it up
--      (`POST /api/voice/audio`), and what lands here is the same raw PCM a
--      local recorder would have written. Speaking into the computer from
--      across the room was the one thing this card could not do. The listen
--      has no clock of its own: it runs until the mic is clicked again,
--      because the person talking is the only one who knows when the sentence
--      is over, and a line cut at ten seconds was a line they had to start
--      again. A listen nobody ends records until `M.cancel` reaches it
--   2. read the recording back into words -- the sentence so far, a piece at
--      a time while it is still being said, then all of it at the end. On a
--      machine whose only transcriber is Windows' own, one recognizer stays
--      open for the whole listen (`reader_start`), because starting it costs
--      more than reading a few seconds of audio does
--   3. hold the words on the card until the button under them is clicked
--      (`M.send`): a transcript read back is a transcript a wrong word cannot
--      send, and the recording is gone by now, so what waits is one line of
--      text and nothing else. Escape throws it away (`M.cancel`); clicking the
--      mic throws it away and listens again
--   4. hand the words to the one talking instance
--      (`helpers.org.ai.open_prompt`, the session `talk/one`): that instance
--      decides what they are inside the org system -- an answer here, or work
--      it files as a ticket and starts the run on -- and the buddy only
--      carries them. There is one instance and one conversation, so "that one
--      too" reaches what the last line said
--
-- The click also carries what the dashboard had highlighted (`state.target`):
-- the entry under the cursor in the list. The talking instance is told, and
-- the ticket it files hangs under that entry, so a spoken command lands in the
-- project the user was reading. A listen with nothing highlighted carries no
-- target, and the board is the one the words name ('in the ing project'), else
-- the project nvim is working in: the words go where a capture from that
-- directory would, so the instance is never left asking which file they belong
-- to.
--
-- The instance answers; it never asks. A line that leaves something open is
-- read the plainest way and the reply says what was taken, because a question
-- from the bot is a whole second listen from the user.
--
-- One selected entry is not the talking instance's: a ticket a run already
-- holds (`@omp_ticket`, or the orchestrator that batch-launched it) hears the
-- words itself -- `ai.open_prompt` types them into that instance and writes
-- them into the entry's body as the user's turn. Speech about a ticket in
-- flight is the ticket's, not a new conversation over the same headline.
--
-- `:OrgVoice` and `:OrgVoiceSay` take their selection from the editor the way
-- a click takes it from the page: the headline at point (`ai.entry_at_point`),
-- so speech started on a ticket in the agenda or an org buffer is about that
-- ticket.
--
-- A click while listening stops the recording and reads it back (`M.stop`);
-- throwing it away is `M.cancel`, the card's escape key.
--
-- The card is silent: speaking is off unless asked for (`OMP_VOICE_SPEAK=1`,
-- or `speak = true` in setup), because the voice was getting in the way of
-- the conversation. `:OrgVoiceSpeak` still says a line on demand.
--
-- Everything is local. Each half is picked from what the machine has, and a
-- missing speaker or transcriber degrades instead of breaking:
--
--   text -> speech |  piper, espeak-ng, spd-say, or Windows' own voice
--                  |  (System.Speech, through powershell.exe under WSL)
--   recording     |  parec on PulseAudio (`/mnt/wslg/PulseServer` under WSLg),
--                  |  or the page's own microphone when the page runs on
--                  |  another device (its sound arrives as raw PCM, so both
--                  |  halves write one wav and nothing downstream can tell
--                  |  them apart)
--   speech -> text |  Handy's own model through transcribe.cpp
--                  |  (`transcribe-cli`), whisper.cpp (`whisper-cli`),
--                  |  Windows' own recognizer on the recorded wav, or a
--                  |  command of the user's
--
-- Overrides, when the detection guesses wrong: `OMP_VOICE_TTS` (a shell
-- command, the words on stdin), `OMP_VOICE_STT` (a shell command, the wav
-- path as `$1`), `OMP_VOICE_HANDY_MODEL` (a gguf path), `OMP_VOICE_WHISPER_MODEL`,
-- `OMP_VOICE_LANG`, `OMP_VOICE_PIPER_MODEL`, `OMP_VOICE_SPEAK`,
-- `OMP_VOICE_PARTIAL` (seconds between two reads of a sentence being said; `0`
-- turns them off).
--
-- The browser polls `GET /api/voice` for `M.status()`: the phase is what the
-- card draws (idle, speaking, listening, thinking, review, sent, error),
-- `partial` the words it has made of a sentence still being said, `heard` the
-- words the finished recording produced -- and, in `review`, the words the
-- approve button would send -- and `run` the pane the words went to and
-- whether it is still working.

local M = {}

local uv = vim.uv or vim.loop

local function notify(msg, level)
  require('org.utils').notify(msg, level)
end

local function exe(name)
  return vim.fn.executable(name) == 1
end

--- Is this a WSL distro, with Windows' own speech available through interop?
--- Read once: /proc/version does not change under a running nvim.
local wsl
local function windows()
  if wsl == nil then
    wsl = false
    if exe 'powershell.exe' then
      local ok, text = pcall(vim.fn.readfile, '/proc/version')
      wsl = ok and text and text[1] ~= nil and text[1]:lower():find('microsoft', 1, true) ~= nil
    end
  end
  return wsl
end

local tts_backend, stt_backend

local opts = {
  partial_seconds = 0.4,
  lang = nil,
  tts = nil,
  stt = nil,
  whisper_model = nil,
  handy_model = nil,
  speak = false,
}

--- What the card draws. `phase` is the state machine's, `heard` the words the
--- last listen produced, `view` the dashboard view the click came from and
--- `error` what went wrong, if anything. `level` is the microphone's loudness
--- a moment ago (0 empty, 1 full), `level_db` the raw reading it came from and
--- `signal` whether any sound at all has arrived in this listen. `partial` is
--- what the transcriber has made of the recording so far, refreshed while the
--- sentence is still being said. `source` is the half that records: `server`
--- is this machine's microphone (`parec`), `browser` the page's own, which is
--- the one a phone should speak into.
local state = {
  phase = 'idle',
  heard = '',
  partial = '',
  view = '',
  target = nil,
  source = 'server',
  error = '',
  at = 0,
  level = 0,
  level_db = nil,
  signal = false,
}

--- What the dashboard had highlighted when the mic was clicked: the entry the
--- list's cursor sits on (`{ file, line, id, title }`, as helpers/org/web/
--- data.lua draws it). Kept as sent, minus anything that is not a file path
--- and a line -- a request from a page cannot write the vault through it, but
--- a malformed one should not be carried into a launch either.
---@param entry any
---@return { file: string, line: integer|nil, id: string|nil, title: string|nil }|nil
local function target_of(entry)
  if type(entry) ~= 'table' or type(entry.file) ~= 'string' or entry.file == '' then
    return nil
  end
  local id = type(entry.id) == 'string' and entry.id ~= '' and entry.id or nil
  local title = type(entry.title) == 'string' and entry.title ~= '' and entry.title or nil
  return { file = entry.file, line = tonumber(entry.line), id = id, title = title }
end

--- Where the last words went: the pane of the talking instance, what it stands
--- for and when the words reached it. The card says that much and no more --
--- the instance outlives the words, so the card stops asking after `SETTLE`
--- seconds instead of waiting for a pane that is meant to stay.
local run = { pane = '', title = '', at = 0 }

--- How long the card keeps asking about the words' pane, in seconds. The
--- talking instance answers and files within a turn or two; after that the
--- card has nothing to add, and the run the words became is the runs window's
--- (helpers/org/runs.lua).
local SETTLE = 20

--- Asked of tmux, once the words have gone (the run section below).
local run_alive

--- The timer that watches that run's pane (the run section below).
local run_timer

local function set_phase(phase, extra)
  state.phase = phase
  state.at = os.time()
  if extra then
    for k, v in pairs(extra) do
      state[k] = v
    end
  end
end

---@return table
function M.status()
  return {
    phase = state.phase,
    heard = state.heard,
    partial = state.partial,
    view = state.view,
    source = state.source,
    error = state.error,
    at = state.at,
    level = state.level,
    level_db = state.level_db,
    signal = state.signal,
    run = { pane = run.pane, title = run.title, at = run.at, alive = run.pane ~= '' and run_alive(run.pane) or false },
    speak = opts.speak and tts_backend() ~= nil,
    tts = tts_backend() ~= nil,
    stt = stt_backend() ~= nil,
  }
end

-- ------------------------------------------------------------------- talking

--- The speaking half: the first program that can make a sound on this
--- machine. `piper` needs a voice file, so it is only picked when one is
--- named (`OMP_VOICE_PIPER_MODEL`); `espeak-ng` and `spd-say` speak out of the
--- box; Windows' own voice always exists under WSL and is what makes this
--- work on a WSL install with no Linux engine at all.
---@return string|nil backend
function tts_backend()
  if opts.tts and opts.tts ~= '' then
    return 'custom'
  end
  if exe 'piper' and vim.env.OMP_VOICE_PIPER_MODEL then
    return 'piper'
  end
  if exe 'espeak-ng' then
    return 'espeak'
  end
  if exe 'spd-say' then
    return 'spd'
  end
  if windows() then
    return 'windows'
  end
end

--- Windows' own voice, driven through interop: the text arrives on stdin (so
--- no quoting of the user's words), and `Speak` returns when the sentence is
--- done, which is the order the conversation needs anyway.
local PS_SPEAK = table.concat({
  'Add-Type -AssemblyName System.Speech;',
  '$s = New-Object System.Speech.Synthesis.SpeechSynthesizer;',
  'if ($env:OMP_VOICE_RATE) { $s.Rate = [int]$env:OMP_VOICE_RATE };',
  '$t = [Console]::In.ReadToEnd();',
  'if ($t.Trim()) { $s.Speak($t.Trim()) };',
  '$s.Dispose()',
}, ' ')

--- Say `text` out loud, then run `done` — the callback is what carries the
--- conversation from speaking to listening, so a missing speaker must still
--- call it. Returns false when there is no speaker at all.
---@param text string
---@param done? fun()
---@return boolean speaking
local function speak(text, done)
  done = done or function() end
  local backend = tts_backend()
  if not backend then
    done()
    return false
  end
  local lang = opts.lang or vim.env.OMP_VOICE_LANG or 'en'
  local cmd
  local input = text
  if backend == 'custom' then
    cmd = { 'sh', '-c', opts.tts }
  elseif backend == 'windows' then
    cmd = { 'powershell.exe', '-NoProfile', '-NonInteractive', '-Command', PS_SPEAK }
    input = text:gsub('[\r\n]+', ' ')
  elseif backend == 'espeak' then
    cmd = { 'espeak-ng', '-v', lang, '-s', '165' }
  elseif backend == 'spd' then
    cmd = { 'spd-say', '-w', '-l', lang }
  elseif backend == 'piper' then
    -- piper writes raw samples; pacat is the PulseAudio player that takes
    -- them without a file in between
    cmd = {
      'sh',
      '-c',
      ('piper -m %s -f - --output-raw | pacat --playback --raw --rate 22050 --channels 1'):format(vim.fn.shellescape(vim.env.OMP_VOICE_PIPER_MODEL)),
    }
  end
  local ok = pcall(vim.system, cmd, { stdin = input, text = true }, function()
    vim.schedule(done)
  end)
  if not ok then
    done()
    return false
  end
  return true
end

-- ---------------------------------------------------------------- listening

--- The PulseAudio server WSLg runs for the distro. `parec` needs it named:
--- nothing sets PULSE_SERVER in a WSL shell, so a recorder would find no
--- source without this.
local function audio_env()
  if vim.env.PULSE_SERVER and vim.env.PULSE_SERVER ~= '' then
    return nil
  end
  local sock = '/mnt/wslg/PulseServer'
  local ok, stat = pcall(uv.fs_stat, sock)
  if ok and stat then
    return { PULSE_SERVER = 'unix:' .. sock }
  end
  return nil
end

--- The directories a whisper model is looked for in, and the English models in
--- the order they are wanted: the words are what the run acts on, so the
--- better model wins. Only the `.en` models are named -- the rest are picked up
--- by the glob when a machine has nothing else.
local WHISPER_DIRS = { '~/.local/share/whisper', '~/.cache/whisper', '/usr/share/whisper.cpp' }
local WHISPER_MODELS = {
  'ggml-medium.en.bin',
  'ggml-small.en.bin',
  'ggml-small.en-q5_1.bin',
  'ggml-base.en.bin',
  'ggml-base.en-q5_1.bin',
}

--- The first readable path among `names` under the whisper directories.
---@param names string[]
---@return string|nil
local function whisper_find(names)
  for _, name in ipairs(names) do
    for _, dir in ipairs(WHISPER_DIRS) do
      local path = vim.fn.expand(dir .. '/' .. name)
      if vim.fn.filereadable(path) == 1 then
        return path
      end
    end
  end
end

--- Where whisper.cpp's model lives, if the machine has one: the explicit
--- setting first (opts, then the environment), then the English models in
--- order of what they hear best, then any `ggml-*.bin` under the usual share
--- directories.
local model -- found once: a glob per status poll would walk the share dirs 3x a second
local function whisper_model()
  if model ~= nil then
    return model ~= '' and model or nil
  end
  local explicit = { opts.whisper_model, vim.env.OMP_VOICE_WHISPER_MODEL }
  for _, path in ipairs(explicit) do
    if path and path ~= '' and vim.fn.filereadable(path) == 1 then
      model = path
      return model
    end
  end
  model = whisper_find(WHISPER_MODELS) or ''
  if model == '' then
    for _, dir in ipairs(WHISPER_DIRS) do
      local found = vim.fn.glob(vim.fn.expand(dir) .. '/ggml-*.bin', false, true)[1]
      if found then
        model = found
        break
      end
    end
  end
  return model ~= '' and model or nil
end

--- The model a sentence still being said is read with: the quicker one, so the
--- words reach the card while there is still time to read them. Reading a
--- recording costs the same whatever its length -- whisper encodes a fixed
--- thirty seconds -- so the sentence being said is the place to spend less.
local peek_model
local function whisper_peek_model()
  if peek_model ~= nil then
    return peek_model ~= '' and peek_model or nil
  end
  peek_model = whisper_find { 'ggml-base.en.bin', 'ggml-base.en-q5_1.bin' } or whisper_model() or ''
  return peek_model ~= '' and peek_model or nil
end

--- Handy is the dictation app the user runs on the Windows side, and the model
--- it transcribes with is a gguf read by `transcribe-cli` -- the command line
--- of transcribe.cpp, the engine Handy ships. Handy keeps its models in the
--- Windows profile's Hugging Face cache and names the one in use in its
--- settings, so sharing the model is a matter of reading that name: whichever
--- model is picked in Handy is the one this reads with.
local HANDY_SETTINGS = '/AppData/Roaming/com.pais.handy/settings_store.json'
local HANDY_MODELS = '/AppData/Roaming/com.pais.handy/models'
local HANDY_CACHE = '~/.cache/omp/voice'

--- A whole file as a string, read through libuv so the same call works on
--- either side of the Windows share.
---@param path string
---@return string|nil
local function slurp(path)
  local fd = uv.fs_open(path, 'r', 384)
  if not fd then
    return nil
  end
  local stat = uv.fs_fstat(fd)
  local data = stat and stat.size > 0 and uv.fs_read(fd, stat.size, 0) or nil
  uv.fs_close(fd)
  return type(data) == 'string' and data or nil
end

--- The names in `dir`, or an empty list when it cannot be read. libuv's
--- readdir rather than `vim.fn.glob`: the Windows drive answers one directory
--- listing quickly and every extra stat through the 9p share slowly, and the
--- glob has to stat each entry it hands back. Looking for Handy is a walk of
--- four such directories, so the reading is what decides whether the search is
--- felt at launch.
---@param dir string
---@return string[]
local function listdir(dir)
  local names = {}
  local handle = uv.fs_scandir(dir)
  if not handle then
    return names
  end
  while true do
    local name = uv.fs_scandir_next(handle)
    if not name then
      return names
    end
    names[#names + 1] = name
  end
end

--- Handy's model as the Windows drive names it, or nil when Handy is not on
--- this machine. `selected_model` reads `org/repo/file.gguf`; the cache spells
--- the repo `models--org--repo` and puts the file in a snapshot directory of
--- its own, and an older Handy kept them under its own models directory.
--- `src` is that path once it has been looked for: nil until then, empty when
--- there is none, so a machine without Handy is not searched twice.
local handy = { src = nil, model = nil, copying = false, warned = false }

---@return string|nil
local function handy_source()
  if handy.src ~= nil then
    return handy.src ~= '' and handy.src or nil
  end
  for _, path in ipairs { opts.handy_model, vim.env.OMP_VOICE_HANDY_MODEL } do
    if path and path ~= '' and uv.fs_stat(path) then
      handy.src = path
      return handy.src
    end
  end
  for _, name in ipairs(listdir '/mnt/c/Users') do
    local user = '/mnt/c/Users/' .. name
    local found = {}
    local selected = (slurp(user .. HANDY_SETTINGS) or ''):match '"selected_model"%s*:%s*"([^"]+)"'
    local org, repo, file = (selected or ''):match '^([^/]+)/([^/]+)/(.+)$'
    if org then
      local hub = ('%s/.cache/huggingface/hub/models--%s--%s'):format(user, org, repo)
      for _, snap in ipairs(listdir(hub .. '/snapshots')) do
        found[#found + 1] = ('%s/snapshots/%s/%s'):format(hub, snap, file)
      end
      found[#found + 1] = ('%s%s/%s/%s'):format(user, HANDY_MODELS, org, repo, file)
    end
    if #found == 0 then
      -- no settings to read, or a selection whose file is gone: any model
      -- Handy itself downloaded is still a better read than none
      local hub = user .. '/.cache/huggingface/hub'
      for _, repo_name in ipairs(listdir(hub)) do
        if repo_name:match '^models%-%-handy%-computer%-%-' then
          local snapshots = hub .. '/' .. repo_name .. '/snapshots'
          for _, snap in ipairs(listdir(snapshots)) do
            for _, entry in ipairs(listdir(snapshots .. '/' .. snap)) do
              if entry:sub(-5) == '.gguf' then
                found[#found + 1] = ('%s/%s/%s'):format(snapshots, snap, entry)
              end
            end
          end
        end
      end
    end
    for _, path in ipairs(found) do
      if uv.fs_stat(path) then
        handy.src = path
        return handy.src
      end
    end
  end
  handy.src = ''
  return nil
end

--- Handy's model, readable from this side. A model read straight off the
--- Windows drive is memory-mapped through the 9p share, and that is the whole
--- difference between a sentence taking a second and taking half a minute: the
--- file is copied across once, into the Linux cache, and read from there after
--- that. Until the copy lands there is nothing to read with, so the listen
--- falls back to the transcriber that was there before.
---@return string|nil
local function handy_model()
  if handy.model then
    return handy.model
  end
  local src = handy_source()
  if not src then
    return nil
  end
  if src:sub(1, 5) ~= '/mnt/' then
    handy.model = src
    return src
  end
  local dir = vim.fn.expand(HANDY_CACHE)
  vim.fn.mkdir(dir, 'p')
  local dst = dir .. '/' .. vim.fn.fnamemodify(src, ':t')
  local there, here = uv.fs_stat(src), uv.fs_stat(dst)
  if there and here and there.size == here.size then
    handy.model = dst
    return dst
  end
  if not handy.copying then
    handy.copying = true
    -- a copy that lands half way is worse than none: it goes beside the file
    -- and is renamed over it only once it is whole, and it is detached so
    -- quitting nvim does not cut it in the middle
    pcall(vim.system, {
      'sh',
      '-c',
      'cp -f "$1" "$2.part" && mv -f "$2.part" "$2"',
      'sh',
      src,
      dst,
    }, { detach = true }, function(obj)
      handy.copying = false
      if obj and (obj.code or 1) == 0 then
        handy.model = dst
      elseif not handy.warned then
        handy.warned = true
        vim.schedule(function()
          notify("voice: could not copy Handy's model to " .. dir, vim.log.levels.WARN)
        end)
      end
    end)
  end
  return nil
end

--- The listening half's transcriber: Handy's model through `transcribe-cli`
--- (the dictation the user already trusts, and the model they already have),
--- then whisper.cpp when the machine has both the binary and a model, else
--- Windows' own recognizer on the recorded wav.
---@return string|nil backend
function stt_backend()
  if opts.stt and opts.stt ~= '' then
    return 'custom'
  end
  if exe 'transcribe-cli' and handy_model() then
    return 'handy'
  end
  if (exe 'whisper-cli' or exe 'main') and whisper_model() then
    return 'whisper'
  end
  if windows() then
    return 'windows'
  end
end

--- Windows' own recognizer, run on the wav this module recorded: one recording
--- path for every transcriber, so the level meter and the words always come
--- from the same capture. The path is substituted into the script (a
--- PowerShell single-quoted string) because WSL interop does not hand Linux
--- environment variables to a Windows process.
local PS_RECOGNIZE = table.concat({
  'Add-Type -AssemblyName System.Speech;',
  '$r = New-Object System.Speech.Recognition.SpeechRecognitionEngine;',
  '$r.LoadGrammar((New-Object System.Speech.Recognition.DictationGrammar));',
  "$r.SetInputToWaveFile('__WAV__');",
  '$out = @();',
  'while ($true) {',
  '  try { $x = $r.Recognize() } catch { break };',
  '  if ($null -eq $x) { break };',
  '  $out += $x.Text',
  '};',
  "[Console]::Out.Write(($out -join ' '))",
}, ' ')

--- The level below which the meter reads empty. A live microphone sits
--- around -50 dBFS of room noise; digital silence is `-inf`, which the meter
--- must show as nothing at all rather than as a quiet room.
local METER_FLOOR = 55

--- The recording's format, fixed: 16 kHz mono, 16-bit, which is what every
--- transcriber this module knows how to drive expects.
local PCM = { rate = 16000, channels = 1, bits = 16 }

local function u16(n)
  return string.char(n % 256, math.floor(n / 256) % 256)
end

local function u32(n)
  return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end

--- A RIFF header over `bytes` of PCM data at the module's fixed format. The
--- recorder writes one with a zero length first and patches the two sizes when
--- it stops, so the file is a valid wav at every moment the process is alive.
---@param bytes integer
---@return string
local function wav_header(bytes)
  local block = PCM.channels * PCM.bits / 8
  return 'RIFF'
    .. u32(36 + bytes)
    .. 'WAVEfmt '
    .. u32(16)
    .. u16(1)
    .. u16(PCM.channels)
    .. u32(PCM.rate)
    .. u32(PCM.rate * block)
    .. u16(block)
    .. u16(PCM.bits)
    .. 'data'
    .. u32(bytes)
end

--- The loudness of one chunk of the recording, as the card draws it: the RMS
--- of the samples turned into dBFS, then squashed into 0..1 between
--- `METER_FLOOR` and full scale. Digital silence stays at zero, which is what
--- makes a dead microphone visible.
---@param data string
local function level_of(data)
  local n = #data - (#data % 2)
  if n == 0 then
    return
  end
  local total = 0
  for i = 1, n, 2 do
    local lo, hi = data:byte(i, i + 1)
    local v = lo + hi * 256
    if v >= 32768 then
      v = v - 65536
    end
    total = total + v * v
  end
  local rms = math.sqrt(total / (n / 2)) / 32768
  local db = rms > 0 and 20 * math.log(rms) / math.log(10) or -math.huge
  if db == -math.huge then
    state.level = 0
    state.level_db = nil
    return
  end
  state.level = math.max(0, math.min(1, (db + METER_FLOOR) / METER_FLOOR))
  state.level_db = db
  -- one tenth of the meter, about -49 dBFS: a microphone delivering dither
  -- and the odd electrical click is not a microphone anyone can talk into
  if state.level >= 0.1 then
    state.signal = true
  end
end

--- The words a program printed, or nothing when it failed. `text = true`
--- hands the output back as one string; a list is accepted all the same.
---@param obj table
---@return string
local function text_of(obj)
  if (obj.code or 0) ~= 0 then
    return ''
  end
  local out = obj.stdout or ''
  if type(out) == 'table' then
    return table.concat(out, ' ')
  end
  return out
end

--- The running child of this listen, so a second click (or `M.cancel`) can
--- cut it short. One listen at a time: the phase is the lock. A recording made
--- by the page's own microphone has no child at all -- `finish` is what ends
--- it, where `proc` is the process the local recorder is signalled through.
local job = { proc = nil, wav = nil, fd = nil, bytes = 0, finish = nil, ended = false }

--- The words of the sentence so far, read again every `partial_seconds` while
--- the recording runs, so the screen can show what was heard while it is still
--- being said. One read at a time: a transcriber slower than the clock skips a
--- turn instead of piling up behind itself. `proc` is the read in flight, so
--- the whole sentence's own read does not have to wait for a guess about half
--- of it: that read is cut short when the sentence ends.
local partial = { timer = nil, busy = false, proc = nil }

local function drop_partial()
  if partial.timer then
    pcall(partial.timer.stop, partial.timer)
    pcall(partial.timer.close, partial.timer)
    partial.timer = nil
  end
  if partial.proc then
    local handle = partial.proc
    partial.proc = nil
    pcall(handle.kill, handle, 'sigterm')
  end
end

--- The open recognizer's parts, filled in below ("the open recognizer"): the
--- end of a listen closes it, so the names have to exist by then.
local reader_start, reader_stop, reader_exit, reader_ask, reader_parse

--- Close the listen and hand `text` (empty when nothing was heard) to `done`,
--- once. Every way out -- the recognizer answering, the recorder stopped, the
--- cap firing, a program failing -- comes through here, so the phase always
--- returns to idle. A recording whose every sample was digital silence is an
--- error, not a quiet listen: it is the one signal that the microphone itself
--- is not delivering anything. A transcriber asked about silence still answers
--- -- whisper makes a word of it, `you` or `(crickets chirping)` -- so the
--- meter, not the words, decides whether anything was said.
---@param text string
---@param done fun(text: string)
local function heard(text, done)
  drop_partial()
  reader_stop()
  if job.wav then
    pcall(uv.fs_unlink, job.wav)
  end
  job.proc = nil
  job.wav = nil
  state.level = 0
  state.level_db = nil
  state.partial = ''
  local said = vim.trim((text or ''):gsub('%s+', ' '))
  if not state.signal then
    set_phase('error', { heard = '', error = 'the microphone delivered no sound' })
    done ''
    return
  end
  set_phase(said == '' and 'idle' or 'thinking', { heard = said })
  done(said)
end

--- Words with whisper's non-speech markers cut out. A recording that holds no
--- speech at all still gets an answer -- `(crickets chirping)`,
--- `(blender whirring)`, `[BLANK_AUDIO]` -- and that is its guess at the room,
--- not the sentence: left in, it would reach the run as the words said.
---@param text string
---@return string
local function spoken(text)
  local said = vim.trim((text or ''):gsub('%b[]', ''):gsub('%b()', ''):gsub('♪', ''):gsub('%s+', ' '))
  if said:gsub('[%p%s]', '') == '' then
    return ''
  end
  return said
end

--- The threads a whisper read is given: one per core, up to eight, so a read
--- is quicker than the sentence it reads without leaving nvim without a core.
---@return string
local function whisper_threads()
  local cores = vim.uv.available_parallelism and vim.uv.available_parallelism() or 4
  return tostring(math.max(1, math.min(8, cores)))
end

--- Read `wav` back into words: the user's own command (`OMP_VOICE_STT`, the
--- wav path as `$1`), Windows' recognizer on the file, Handy's model through
--- `transcribe-cli`, or whisper.cpp. A `quiet` read is the words of a sentence
--- still being said: it hands them to `done` and leaves the listen alone. Only
--- the final read ends it.
---@param wav string
---@param backend string
---@param done fun(text: string)
---@param quiet? boolean
local function transcribe(wav, backend, done, quiet)
  local cmd, env, out
  if backend == 'custom' then
    cmd = { 'sh', '-c', opts.stt .. ' "$1"', 'sh', wav }
    env = audio_env()
  elseif backend == 'windows' then
    -- the recognizer runs on Windows and reads the file through the WSL
    -- share, so the wav has to be named the way Windows names it
    local win = vim.trim(vim.fn.systemlist({ 'wslpath', '-w', wav })[1] or '')
    if win == '' then
      pcall(uv.fs_unlink, wav)
      vim.schedule(function()
        if not quiet then
          set_phase('error', { error = 'could not hand the recording to Windows' })
        end
        done ''
      end)
      return
    end
    local script = PS_RECOGNIZE:gsub('__WAV__', function()
      return (win:gsub("'", "''"))
    end)
    cmd = { 'powershell.exe', '-NoProfile', '-NonInteractive', '-Command', script }
  elseif backend == 'handy' then
    local model = handy_model()
    if not model then
      pcall(uv.fs_unlink, wav)
      vim.schedule(function()
        if not quiet then
          set_phase('error', { error = "Handy's model is not readable" })
        end
        done ''
      end)
      return
    end
    -- the words come back in a file: the command prints the model it loaded
    -- and the timings beside them, and the file holds the sentence alone
    out = vim.fn.tempname() .. '.txt'
    cmd = {
      'transcribe-cli',
      '-q',
      '--threads',
      whisper_threads(),
      '-m',
      model,
      '-o',
      out,
      wav,
    }
  else
    local model = (quiet and whisper_peek_model()) or whisper_model()
    cmd = {
      exe 'whisper-cli' and 'whisper-cli' or 'main',
      '-m',
      model,
      '-f',
      wav,
      '-nt',
      '-np',
      '-t',
      whisper_threads(),
    }
    local lang = opts.lang or vim.env.OMP_VOICE_LANG
    if lang then
      vim.list_extend(cmd, { '-l', lang })
    end
    env = audio_env()
  end
  local started, handle = pcall(vim.system, cmd, { text = true, env = env }, function(obj)
    pcall(uv.fs_unlink, wav)
    local text = text_of(obj)
    if out then
      text = slurp(out) or ''
      pcall(uv.fs_unlink, out)
    end
    if backend == 'whisper' then
      text = spoken(text)
    end
    vim.schedule(function()
      if quiet then
        done(text)
      else
        heard(text, done)
      end
    end)
  end)
  return started and handle or nil
end

--- Write the two sizes into the wav's header, so the file names its own length
--- at whatever moment it is read: the recorder writes a zero length first and
--- the real one is filled in here. Safe while the recorder is still writing
--- (the samples go at a fixed offset past the header), which is what lets a
--- reader open the recording while the sentence is still being said.
local function patch_sizes()
  if not job.fd or not job.bytes then
    return
  end
  local bytes = job.bytes
  pcall(uv.fs_write, job.fd, u32(36 + bytes), 4)
  pcall(uv.fs_write, job.fd, u32(bytes), 40)
end

--- Close the wav and fill in its two sizes, so the file is whole before any
--- transcriber opens it. Safe to call twice: the handle is gone after the
--- first.
local function close_wav()
  if not job.fd then
    return
  end
  patch_sizes()
  pcall(uv.fs_close, job.fd)
  job.fd = nil
end

--- What has been recorded so far, as a wav a transcriber can read while the
--- recording goes on. The file the recorder writes carries sizes that are only
--- patched when it stops, so a reader would have to guess its length; this copy
--- carries the real ones, which is what lets the words show up as they are
--- said instead of after the fact.
---@return string|nil path
local function snapshot()
  if not job.wav or not job.bytes or job.bytes == 0 then
    return nil
  end
  local src = uv.fs_open(job.wav, 'r', 384)
  if not src then
    return nil
  end
  local data = uv.fs_read(src, job.bytes, 44)
  uv.fs_close(src)
  if type(data) ~= 'string' or data == '' then
    return nil
  end
  local path = vim.fn.tempname() .. '.wav'
  local fd = uv.fs_open(path, 'w', 384)
  if not fd then
    return nil
  end
  uv.fs_write(fd, wav_header(#data), 0)
  uv.fs_write(fd, data, 44)
  uv.fs_close(fd)
  return path
end

-- ------------------------------------------------------- the open recognizer

--- Windows' own recognizer, kept open for the whole listen. Words have to show
--- up on the card while the sentence is still being said, and starting
--- PowerShell -- loading System.Speech and building a grammar -- costs more
--- than reading a few seconds of audio does; kept open, a read is the
--- recognition and nothing else, on one engine built while the recorder is
--- already running. The process reads its wav path from its first stdin line,
--- then answers one line per question it is asked: `\1` is what a peek found,
--- `\2` what the final read found, and `QUIT` ends it.
local PS_READ = table.concat({
  'Add-Type -AssemblyName System.Speech;',
  '$p = [Console]::In.ReadLine();',
  'if ($null -ne $p) {',
  '$p = $p.Trim();',
  '$eng = New-Object System.Speech.Recognition.SpeechRecognitionEngine;',
  '$eng.LoadGrammar((New-Object System.Speech.Recognition.DictationGrammar));',
  'function Words($f) {',
  '  $o = @();',
  '  try {',
  '    $eng.SetInputToWaveFile($f);',
  '    while ($true) {',
  '      try { $x = $eng.Recognize() } catch { break };',
  '      if ($null -eq $x) { break };',
  '      $o += $x.Text',
  '    }',
  '  } catch { };',
  "  return (($o -join ' ').Trim())",
  '};',
  'while ($true) {',
  '  $l = [Console]::In.ReadLine();',
  '  if ($null -eq $l) { break };',
  '  $l = $l.Trim();',
  "  if ($l -eq 'QUIT') { break };",
  '  $t = [char]1;',
  "  if ($l -eq 'FINAL') { $t = [char]2 };",
  '  [Console]::Out.WriteLine($t + (Words $p));',
  '  [Console]::Out.Flush();',
  "  if ($l -eq 'FINAL') { break }",
  '}',
  '}',
}, ' ')

--- The open recognizer: its process, the recording it reads, and the answer a
--- final read is still owed.
local reader = { proc = nil, wav = nil, buf = '', final = nil }

--- The path a Windows program needs to open this recording: it is in a Linux
--- directory, and Windows reads it through the WSL share.
---@param wav string
---@return string
local function win_path(wav)
  local out = vim.fn.systemlist { 'wslpath', '-w', wav }
  if vim.v.shell_error ~= 0 then
    return ''
  end
  return vim.trim(out[1] or '')
end

--- Start the recognizer on `wav`, or say it is already open. PowerShell is the
--- only one it knows: every other transcriber is cheap enough to start per
--- read.
---@param wav string|nil
---@return boolean started
function reader_start(wav)
  if reader.proc then
    return true
  end
  if not windows() or not wav then
    return false
  end
  local win = win_path(wav)
  if win == '' then
    return false
  end
  -- declared before the callbacks so they close over the handle that is
  -- assigned once it exists: a `local ok, handle = ...` would leave them
  -- reading a global of the same name, always nil, and every answer would
  -- look like a dead recognizer's
  local handle
  local ok
  ok, handle = pcall(vim.system, {
    'powershell.exe',
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    PS_READ,
  }, {
    stdin = true,
    text = true,
    stdout = function(_, data)
      if not data or data == '' then
        return
      end
      vim.schedule(function()
        if reader.proc ~= handle then
          return
        end
        reader.buf = reader.buf .. data
        reader_parse()
      end)
    end,
  }, function()
    vim.schedule(function()
      if reader.proc == handle then
        reader_exit()
      end
    end)
  end)
  if not ok then
    return false
  end
  reader.proc, reader.wav, reader.buf = handle, wav, ''
  local wrote = pcall(function()
    handle:write(win .. '\n')
  end)
  if not wrote then
    reader_stop()
    return false
  end
  return true
end

--- Let go of the recognizer: the recording stays on disk (`M.cancel` and the
--- ends of a listen delete it themselves), and nothing left to answer.
function reader_stop()
  local handle = reader.proc
  reader.proc = nil
  reader.wav, reader.buf, reader.final = nil, '', nil
  partial.busy, partial.asked = false, nil
  if handle then
    pcall(handle.kill, handle, 'sigterm')
  end
end

--- The recognizer's process is gone. A final read it owed is taken the one-off
--- way, so the words are not lost with the process; otherwise the recording is
--- done and its file goes.
function reader_exit()
  local wav, final = reader.wav, reader.final
  reader.proc, reader.wav, reader.buf, reader.final = nil, nil, '', nil
  partial.busy, partial.asked = false, nil
  if state.phase == 'listening' then
    -- the recording goes on; the next peek starts a recognizer again
    return
  end
  if final and state.phase == 'thinking' and wav and vim.fn.filereadable(wav) == 1 then
    transcribe(wav, 'windows', final)
    return
  end
  if wav then
    pcall(uv.fs_unlink, wav)
  end
end

--- Ask the open recognizer a question: `PEEK` for the words so far, `FINAL`
--- for the whole recording. Answers arrive on the reader's stdout.
---@param cmd string
---@return boolean asked
function reader_ask(cmd)
  local handle = reader.proc
  if not handle then
    return false
  end
  local ok = pcall(function()
    handle:write(cmd .. '\n')
  end)
  if not ok then
    reader_stop()
    return false
  end
  return true
end

--- One line per completed answer: what a peek found goes on the card while the
--- sentence is still being said, what the final read found is the sentence.
function reader_parse()
  while true do
    local line = reader.buf:match '^([^\n]*)\n'
    if not line then
      return
    end
    reader.buf = reader.buf:sub(#line + 2)
    local kind = line:sub(1, 1)
    local words = vim.trim((line:sub(2):gsub('%s+$', '')))
    if kind == '\1' then
      partial.busy, partial.asked = false, nil
      if state.phase == 'listening' and words ~= '' and state.signal then
        state.partial = words
      end
    elseif kind == '\2' then
      local done = reader.final
      reader.final = nil
      if done and state.phase == 'thinking' then
        heard(words, done)
      end
    end
  end
end

--- Is there enough of the sentence to read yet? The first tenths of a second
--- are noise and a breath, and a transcriber asked about them guesses -- a
--- stray `you` at the top of every sentence -- where a second and a half
--- already holds the opening words. Asked and answered while the recording
--- runs, so the card starts on the words and not on a guess.
---@return boolean
local function enough_to_read()
  return (job.bytes or 0) >= PCM.rate * 2 * 1.5
end

--- Read the growing recording again and again, so the card shows the words
--- while they are still being said. A read at a time: a recognizer slower than
--- the clock skips a turn instead of piling up behind itself, and one that
--- stops answering is replaced rather than waited on forever.
local function peek_open()
  local step = opts.partial_seconds
  partial.timer = uv.new_timer()
  partial.timer:start(step * 1000, step * 1000, function()
    vim.schedule(function()
      if state.phase ~= 'listening' or not enough_to_read() then
        return
      end
      if partial.busy then
        if uv.now() - (partial.asked or 0) > 5000 then
          reader_stop()
          reader_start(job.wav)
        end
        return
      end
      patch_sizes()
      partial.busy = true
      partial.asked = uv.now()
      if not reader_ask 'PEEK' then
        partial.busy = false
      end
    end)
  end)
end

--- Read the words of the recording so far, again and again, until the
--- recording stops: this is the text the screen shows while the sentence is
--- still being said.
---@param backend string|nil
local function peek(backend)
  if not backend or (opts.partial_seconds or 0) <= 0 then
    return
  end
  if backend == 'windows' and reader_start(job.wav) then
    peek_open()
    return
  end
  partial.timer = uv.new_timer()
  partial.timer:start(opts.partial_seconds * 1000, opts.partial_seconds * 1000, function()
    vim.schedule(function()
      if state.phase ~= 'listening' or partial.busy or not enough_to_read() then
        return
      end
      local path = snapshot()
      if not path then
        return
      end
      partial.busy = true
      partial.proc = transcribe(path, backend, function(text)
        partial.busy, partial.proc = false, nil
        local words = vim.trim((text or ''):gsub('%s+', ' '))
        if state.phase == 'listening' and words ~= '' and state.signal then
          state.partial = words
        end
      end, true)
    end)
  end)
end

--- Open the wav a listen writes into. Both recording halves start here: the
--- same file, the same header, the same `job` fields behind it, so whatever
--- reads it back cannot tell which one filled it.
---@param done fun(text: string)
---@return string|nil wav
local function open_wav(done)
  local wav = vim.fn.tempname() .. '.wav'
  local fd = uv.fs_open(wav, 'w', 384)
  if not fd then
    set_phase('error', { error = 'could not write the recording' })
    done ''
    return nil
  end
  job.wav, job.fd, job.bytes, job.ended = wav, fd, 0, false
  uv.fs_write(fd, wav_header(0), 0)
  return wav
end

--- Close the recording and read it back: the last step of a listen, whichever
--- half recorded it. The bytes are on disk in the module's format by now, so
--- from here on nothing knows the difference. Safe to call twice -- the
--- second click and a failing recorder can both land here -- because the
--- first call is what sets `job.ended`.
---@param backend string|nil
---@param wav string
---@param done fun(text: string)
local function end_recording(backend, wav, done)
  if job.ended then
    return
  end
  job.ended = true
  job.finish = nil
  close_wav()
  drop_partial()
  if state.phase ~= 'listening' then
    pcall(uv.fs_unlink, wav)
    return
  end
  job.proc = nil
  if vim.fn.filereadable(wav) ~= 1 then
    heard('', done)
    return
  end
  if not backend then
    pcall(uv.fs_unlink, wav)
    job.wav = nil
    reader_stop()
    set_phase('error', { error = 'recorded, but no speech-to-text is installed' })
    done ''
    return
  end
  set_phase 'thinking'
  if backend == 'windows' and reader.proc and reader.wav == wav then
    -- the recognizer already has the recording open: asking it again is the
    -- recognition alone, where a fresh process would pay for its startup
    reader.final = done
    if reader_ask 'FINAL' then
      return
    end
    reader.final = nil
  end
  transcribe(wav, backend, done)
end

--- Record until a second click, then transcribe. The recording has no clock of
--- its own: the click that ends the sentence is the one that wants it, so a
--- sentence nobody ends keeps recording until `M.stop` or `M.cancel` reaches
--- it. `parec` streams the microphone as raw PCM instead of writing a file
--- itself, which is what lets the same bytes become both the wav and the
--- level: an encoded recorder buffers its output and the meter would only
--- arrive when the recording ended. Every chunk is measured for the card and
--- appended to the wav; stopping closes the file before anything reads it.
---@param backend string|nil
---@param done fun(text: string)
local function start_recording(backend, done)
  local wav = open_wav(done)
  if not wav then
    return
  end
  if backend == 'windows' then
    -- started with the recording, so PowerShell's own startup is paid for
    -- while the sentence is being said rather than after it
    reader_start(wav)
  end
  local function on_stdout(_, data)
    if not data or data == '' or not job.fd then
      return
    end
    pcall(uv.fs_write, job.fd, data, 44 + job.bytes)
    job.bytes = job.bytes + #data
    level_of(data)
  end
  local ok, handle = pcall(vim.system, {
    'parec',
    '--format=s16le',
    '--rate=' .. PCM.rate,
    '--channels=' .. PCM.channels,
    '--latency-msec=100',
    '--raw',
  }, { env = audio_env(), stdout = on_stdout }, function()
    vim.schedule(function()
      end_recording(backend, wav, done)
    end)
  end)
  if not ok then
    close_wav()
    pcall(uv.fs_unlink, wav)
    job.wav = nil
    set_phase('error', { error = 'could not start the recorder' })
    done ''
    return
  end
  job.proc = handle
  peek(backend)
end

--- Record from the page's own microphone: the browser captures the sound and
--- streams it here one piece at a time (`M.chunk`), and this half is what
--- `parec` is on the machine -- a wav growing on disk, the level measured as
--- the bytes land, a recognizer reading it while it grows. There is no
--- process, so `job.finish` is what ends it where the local recorder gets a
--- signal.
---@param backend string|nil
---@param done fun(text: string)
local function start_stream(backend, done)
  local wav = open_wav(done)
  if not wav then
    return
  end
  if backend == 'windows' then
    reader_start(wav)
  end
  job.finish = function()
    end_recording(backend, wav, done)
  end
  peek(backend)
end

--- One piece of the page's recording, as it lands: `data` is raw PCM at the
--- module's format (`POST /api/voice/audio`). The bytes a local recorder would
--- have written become the wav and the level here, so the card draws a page's
--- microphone exactly the way it draws this machine's. A piece that arrives
--- when nothing is listening is dropped: the page can lose a race with the cap
--- or a cancel, and a stray chunk is not a reason to fail a request.
---@param data any
---@return integer bytes this listen holds
function M.chunk(data)
  if type(data) ~= 'string' or not job.fd or state.phase ~= 'listening' or state.source ~= 'browser' then
    return job.bytes or 0
  end
  -- a piece cut mid-sample would shift every sample after it by a byte
  data = data:sub(1, #data - (#data % 2))
  if data == '' then
    return job.bytes
  end
  pcall(uv.fs_write, job.fd, data, 44 + job.bytes)
  job.bytes = job.bytes + #data
  level_of(data)
  return job.bytes
end

--- Listen once and hand the words to `done`: record through PulseAudio, or
--- through the page's own microphone when the click came from a device that
--- has one, show the level while it records, then read the file back.
--- Recording comes first even when no transcriber is installed, because a
--- silent level is the answer to "is the microphone working at all" -- on this
--- machine. A page's recording is only made when there is something to read it
--- back with.
---@param done fun(text: string)
local function listen(done)
  -- Handy can be given a different model between two listens, and the one it
  -- names then is the one this should read with: look it up again rather than
  -- keep the first answer for the life of the session
  handy.src, handy.model = nil, nil
  if state.source == 'browser' then
    if not stt_backend() then
      set_phase('error', { error = 'no speech-to-text is installed to read the recording' })
      done ''
      return
    end
    set_phase('listening', { level = 0, level_db = nil, signal = false, partial = '', heard = '' })
    start_stream(stt_backend(), done)
    return
  end
  if not exe 'parec' then
    set_phase('error', { error = 'no recorder: parec (pulseaudio-utils) is not installed' })
    done ''
    return
  end
  set_phase('listening', { level = 0, level_db = nil, signal = false, partial = '', heard = '' })
  start_recording(stt_backend(), done)
end

-- ------------------------------------------------------------------ the run

--- A cheap answer to "is the run still there": the page asks three times a
--- second while it draws, and asking tmux costs a process. Two seconds is the
--- shortest age that tells the truth and still misses no ending.
local seen = { pane = '', at = 0, alive = false }

---@param pane string
---@return boolean
function run_alive(pane)
  if not pane or pane == '' then
    return false
  end
  local now = uv.now()
  if seen.pane == pane and now - seen.at < 2000 then
    return seen.alive
  end
  local out = vim.fn.systemlist { 'tmux', 'list-panes', '-a', '-F', '#{pane_id}' }
  local alive = vim.v.shell_error == 0 and vim.tbl_contains(out, pane)
  seen = { pane = pane, at = now, alive = alive }
  return alive
end

--- Watch the words' pane until it is gone, then let the card fold away: the
--- words are out of the card's hands, and it has said where they went. The
--- pane is the talking instance's, which outlives the words on purpose -- it
--- stays up for the next line -- so the card also folds once the words have
--- been in its hands for `SETTLE` seconds: the run they become is dispatched
--- from there, and `helpers/org/runs.lua` is where its progress is watched.
local function watch_run()
  local function drop()
    if run_timer then
      pcall(run_timer.stop, run_timer)
      pcall(run_timer.close, run_timer)
      run_timer = nil
    end
  end
  drop()
  run_timer = uv.new_timer()
  run_timer:start(2000, 2000, function()
    vim.schedule(function()
      if state.phase ~= 'sent' then
        drop()
        return
      end
      if not run_alive(run.pane) or (run.settle and os.time() >= run.settle) then
        drop()
        set_phase 'idle'
      end
    end)
  end)
end

--- Hand the heard words on (`helpers.org.ai.open_prompt`): a run already on the
--- ticket the selection names hears them as the user's next turn, and every
--- other line reaches the one talking instance, which sorts it -- answering a
--- question, or filing the work as a ticket and starting the run on it. The
--- card carries the words, the view they were said on and the entry they are
--- about, and nothing else: the rules are the instance's own system prompt.
---
--- With the selection in hand (`state.target`) the instance is told which entry
--- the words hang under, so a spoken command lands in the project the user was
--- reading, or on the ticket they were looking at. Without one the words name
--- no destination, and they get the project's own board -- the one nvim is
--- working in (`ai.open_prompt`'s spec) -- so the instance files them without
--- asking anything back.
---@param text string
local function launch(text)
  if text == '' then
    return
  end
  local view = state.view ~= '' and state.view or 'dashboard'
  local title = '🤖 ' .. text:sub(1, 40)
  local pane
  local ok, err = pcall(function()
    pane = require('helpers.org.ai').open_prompt(text, state.target, view)
  end)
  if not ok or not pane then
    local why = ok and 'could not reach the talking instance' or tostring(err)
    set_phase('error', { error = why })
    notify('voice: ' .. why, vim.log.levels.ERROR)
    return
  end
  -- the words are the talking instance's now; the card says where they went
  -- and folds, rather than waiting on a pane that stays up for the next line
  run = { pane = pane, title = title, at = os.time(), settle = os.time() + SETTLE }
  set_phase('sent', { heard = text })
  watch_run()
end

--- Does the card say anything at all? Off by default: it is a microphone and
--- a run, not a speaker, and the voice was getting in the way. `speak =
--- true` in setup, or `OMP_VOICE_SPEAK=1`, brings it back.
local function speaks()
  return opts.speak and tts_backend() ~= nil
end

--- The whole conversation: listen, read the words back, and hold them for the
--- approve button (`M.send`), which hands them to the talking instance -- or
--- to the run already on the ticket the selection names (`launch`,
--- `ai.open_prompt`'s own route). A click while words wait in `review` starts
--- the listen over and the unapproved line goes with it, which is what the
--- mic's own hint says it does. The click is acknowledged out loud only when
--- the voice is on. `view` names what was open when the listen
--- started: the dashboard's view title, or `editor` for the commands, which
--- run in an nvim buffer rather than on the page. `entry` (the entry the list
--- had highlighted, or the headline at point) is the entry the words belong
--- to; it is what the words hang under when they become a ticket and what
--- decides which run hears them. `source` says which microphone the sound
--- comes from: `browser` for a page recording its own (a phone on the tunnel),
--- anything else -- or nothing at all -- this machine's, which is what the
--- editor's own commands use.
---@param view? string
---@param entry? { file: string, line?: integer, id?: string, title?: string }
---@param source? string
function M.converse(view, entry, source)
  local open = { idle = true, error = true, sent = true, review = true }
  if not open[state.phase] then
    return false
  end
  local function begin()
    listen(function(text)
      M._said(text)
    end)
  end
  state.target = target_of(entry)
  state.source = source == 'browser' and 'browser' or 'server'
  set_phase('idle', { view = vim.trim(view or ''), heard = '', partial = '', error = '' })
  if not speaks() then
    begin()
    return true
  end
  set_phase 'speaking'
  local where = state.target and state.target.title or state.view
  speak(where ~= '' and ('Listening on ' .. where) or 'Listening', function()
    if state.phase == 'speaking' then
      begin()
    end
  end)
  return true
end

--- What was heard: hold it on the card until the approve button is clicked
--- (`M.send`). Speech is the one input the user cannot check on the way in --
--- a word misheard reaches a run as an instruction nobody gave -- so the
--- transcript stops here for one look, and the recording behind it is already
--- gone: what waits is a line of text, not a wav. The voice, when it is on,
--- says the line back while it waits.
---@param text string
function M._said(text)
  local said = vim.trim((text or ''):gsub('%s+', ' '))
  if said == '' then
    set_phase('idle', { heard = '' })
    return
  end
  set_phase('review', { heard = said })
  if speaks() then
    speak(said)
  end
end

--- Send the words the card is holding: the approve button (`POST /api/voice`
--- with `{send: true}`), and `:OrgVoiceSend` from the editor. Only the words
--- of a listen that ended and is still waiting go on -- a second click, or a
--- card whose words were thrown away, is a race the page lost rather than a
--- sentence said twice.
---@return boolean sent
function M.send()
  if state.phase ~= 'review' or state.heard == '' then
    return false
  end
  launch(state.heard)
  return state.phase == 'sent'
end

--- Stop the recording and read the words back: the second click on the mic.
--- The click that ends a sentence is the one that wants the sentence read, so
--- this closes the recording the way the cap does and lets the transcription
--- run -- into `review`, where the words wait for the approve button;
--- `M.cancel` is the other way out, which throws the recording away.
---@return boolean stopping
function M.stop()
  if state.phase ~= 'listening' then
    return false
  end
  if job.finish then
    -- a recording the page made has no process to signal: the wav is already
    -- whole, and closing it is the whole of stopping
    job.finish()
    return true
  end
  local handle = job.proc
  if not handle then
    M.cancel()
    return false
  end
  pcall(handle.kill, handle, 'sigint')
  return true
end

--- Throw the recording away: the card's escape key, and the escape hatch when
--- a program hangs. Nothing is read back and no run starts. In `review` it
--- throws the words away instead -- the one way out of a line the user does
--- not want said.
function M.cancel()
  job.finish = nil
  if job.proc then
    local handle = job.proc
    job.proc = nil
    pcall(handle.kill, handle, 'sigterm')
  end
  drop_partial()
  reader_stop()
  if job.fd then
    close_wav()
  end
  if job.wav then
    pcall(uv.fs_unlink, job.wav)
    job.wav = nil
  end
  set_phase('idle', { heard = '', partial = '', level = 0, level_db = nil })
end

--- `:OrgVoiceSay {text}`: the words without the microphone, sent as given --
--- there is nothing to approve when the user typed them, so this skips the
--- card's `review` and is also what a test drives. `entry` is
--- the selection a click would have carried: the dashboard's highlight, or the
--- headline at point when the command was run from the editor (`M.converse`'s
--- `entry`, helpers/org/ai.lua's `entry_at_point`). `view` is what was open
--- when the words were said, for the instance the words reach -- a page's view
--- title, or `editor` for the command.
---@param text string
---@param entry? { file: string, line?: integer, id?: string, title?: string }
---@param view? string
function M.say(text, entry, view)
  local said = vim.trim((text or ''):gsub('%s+', ' '))
  if said == '' then
    return
  end
  state.view = vim.trim(view or '')
  state.target = target_of(entry)
  set_phase('thinking', { heard = said })
  launch(said)
end

--- `:OrgVoiceSpeak {text}`: just the speaking half.
---@param text string
---@return boolean speaking
function M.speak(text)
  return speak(text)
end

function M.setup(user)
  opts = vim.tbl_extend('force', opts, user or {})
  if vim.env.OMP_VOICE_PARTIAL then
    opts.partial_seconds = tonumber(vim.env.OMP_VOICE_PARTIAL) or opts.partial_seconds
  end
  if vim.env.OMP_VOICE_SPEAK and vim.env.OMP_VOICE_SPEAK ~= '' then
    local v = vim.env.OMP_VOICE_SPEAK:lower()
    opts.speak = v ~= '0' and v ~= 'off' and v ~= 'false' and v ~= 'no'
  end
  if not opts.tts and vim.env.OMP_VOICE_TTS and vim.env.OMP_VOICE_TTS ~= '' then
    opts.tts = vim.env.OMP_VOICE_TTS
  end
  if not opts.stt and vim.env.OMP_VOICE_STT and vim.env.OMP_VOICE_STT ~= '' then
    opts.stt = vim.env.OMP_VOICE_STT
  end
  -- words said from the editor carry what is at point the way a click on the
  -- board carries its highlight: the ticket selected is the ticket spoken about
  local function selection()
    local ok, entry = pcall(function()
      return require('helpers.org.ai').entry_at_point()
    end)
    return ok and entry or nil
  end
  vim.api.nvim_create_user_command('OrgVoice', function()
    M.converse('editor', selection())
  end, { desc = 'voice: say a line, listen, hand the words to the talking instance' })
  vim.api.nvim_create_user_command('OrgVoiceSay', function(args)
    M.say(args.args, selection(), 'editor')
  end, { nargs = '+', desc = 'voice: hand the words to the talking instance, without the microphone' })
  vim.api.nvim_create_user_command('OrgVoiceSpeak', function(args)
    M.speak(args.args)
  end, { nargs = '+', desc = 'voice: just say it' })
  vim.api.nvim_create_user_command('OrgVoiceCancel', function()
    M.cancel()
  end, { desc = 'voice: stop listening' })
  vim.api.nvim_create_user_command('OrgVoiceStop', function()
    M.stop()
  end, { desc = 'voice: stop recording and read it back' })
  vim.api.nvim_create_user_command('OrgVoiceSend', function()
    if not M.send() then
      notify('voice: no words waiting to be sent', vim.log.levels.WARN)
    end
  end, { desc = 'voice: send the words the card is holding' })
  -- Handy's model is copied into the Linux side on first use and that copy
  -- takes a few seconds, so start it once nvim is up rather than during the
  -- launch: looking for it reads a few directories on the Windows drive, and
  -- every one of them is a round trip through the 9p share a launch should not
  -- wait on. A first click a moment later falls back to whisper only if it
  -- beats the copy.
  local warm = function()
    vim.defer_fn(handy_model, 500)
  end
  if vim.v.vim_did_enter == 1 then
    warm()
  else
    vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = warm, desc = 'voice: warm up the Handy model copy' })
  end
end

return M
