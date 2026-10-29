-- The voice buddy's engine: what sits behind the recording card on the org
-- dashboard (lua/helpers/org/web/assets/jarvis.js, served by helpers/org/web/).
--
-- The card is UI and lives in the browser; this is the part that needs the
-- machine. A click comes in as `POST /api/voice` (helpers/org/web/init.lua)
-- and the conversation runs here:
--
--   1. listen -- record through PulseAudio and report the level as it goes,
--      so a machine whose microphone is dead looks dead instead of silent
--   2. read the recording back into words -- the sentence so far, a piece at
--      a time while it is still being said, then all of it at the end
--   3. hand the words to an `omp` instance in a tmux pane
--      (`helpers.org.ai.open_prompt`): that run decides what to do with them
--      inside the org system, the buddy only carries the words
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
--   recording     |  parec on PulseAudio (`/mnt/wslg/PulseServer` under WSLg)
--   speech -> text |  whisper.cpp (`whisper-cli`), Windows' own recognizer on
--                  |  the recorded wav, or a command of the user's
--
-- Overrides, when the detection guesses wrong: `OMP_VOICE_TTS` (a shell
-- command, the words on stdin), `OMP_VOICE_STT` (a shell command, the wav
-- path as `$1`), `OMP_VOICE_WHISPER_MODEL`, `OMP_VOICE_LANG`,
-- `OMP_VOICE_PIPER_MODEL`, `OMP_VOICE_LISTEN_SECONDS`, `OMP_VOICE_SPEAK`,
-- `OMP_VOICE_PARTIAL` (seconds between two reads of a sentence being said;
-- `0` turns them off).
--
-- The browser polls `GET /api/voice` for `M.status()`: the phase is what the
-- card draws (idle, speaking, listening, thinking, error), `partial` the words
-- it has made of a sentence still being said, and `heard` the words the
-- finished recording produced.

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
  listen_seconds = 10,
  partial_seconds = 1.5,
  lang = nil,
  tts = nil,
  stt = nil,
  whisper_model = nil,
  speak = false,
}

--- What the card draws. `phase` is the state machine's, `heard` the words the
--- last listen produced, `view` the dashboard view the click came from and
--- `error` what went wrong, if anything. `level` is the microphone's loudness
--- a moment ago (0 empty, 1 full), `level_db` the raw reading it came from and
--- `signal` whether any sound at all has arrived in this listen. `partial` is
--- what the transcriber has made of the recording so far, refreshed while the
--- sentence is still being said.
local state = {
  phase = 'idle',
  heard = '',
  partial = '',
  view = '',
  error = '',
  at = 0,
  level = 0,
  level_db = nil,
  signal = false,
}

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
    error = state.error,
    at = state.at,
    level = state.level,
    level_db = state.level_db,
    signal = state.signal,
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

--- Where whisper.cpp's model lives, if the machine has one: the explicit
--- setting first (opts, then the environment), then the places people usually
--- put it, then any `ggml-*.bin` under the usual share directories.
local model -- found once: a glob per status poll would walk the share dirs 3x a second
local function whisper_model()
  if model ~= nil then
    return model ~= '' and model or nil
  end
  local candidates = {
    opts.whisper_model,
    vim.env.OMP_VOICE_WHISPER_MODEL,
    vim.fn.expand '~/.local/share/whisper/ggml-base.en.bin',
    vim.fn.expand '~/.local/share/whisper/ggml-small.en.bin',
    vim.fn.expand '~/.cache/whisper/ggml-base.en.bin',
    '/usr/share/whisper.cpp/ggml-base.en.bin',
  }
  for _, path in ipairs(candidates) do
    if path and path ~= '' and vim.fn.filereadable(path) == 1 then
      model = path
      return model
    end
  end
  for _, dir in ipairs { '~/.local/share/whisper', '~/.cache/whisper', '/usr/share/whisper.cpp' } do
    local found = vim.fn.glob(vim.fn.expand(dir) .. '/ggml-*.bin', false, true)[1]
    if found then
      model = found
      return model
    end
  end
  model = ''
  return nil
end

--- The listening half's transcriber: whisper.cpp when the machine has both
--- the binary and a model (better dictation, and no desktop session
--- involved), else Windows' own recognizer on the recorded wav.
---@return string|nil backend
function stt_backend()
  if opts.stt and opts.stt ~= '' then
    return 'custom'
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
--- cut it short. One listen at a time: the phase is the lock.
local job = { proc = nil, timer = nil, wav = nil, fd = nil, bytes = 0 }

local function drop_timer()
  if job.timer then
    pcall(job.timer.stop, job.timer)
    pcall(job.timer.close, job.timer)
    job.timer = nil
  end
end

--- The words of the sentence so far, read again every `partial_seconds` while
--- the recording runs, so the screen can show what was heard while it is still
--- being said. One read at a time: a transcriber slower than the clock skips a
--- turn instead of piling up behind itself.
local partial = { timer = nil, busy = false }

local function drop_partial()
  if partial.timer then
    pcall(partial.timer.stop, partial.timer)
    pcall(partial.timer.close, partial.timer)
    partial.timer = nil
  end
end

--- Close the listen and hand `text` (empty when nothing was heard) to `done`,
--- once. Every way out -- the recognizer answering, the recorder stopped, the
--- cap firing, a program failing -- comes through here, so the phase always
--- returns to idle. A recording whose every sample was digital silence is an
--- error, not a quiet listen: it is the one signal that the microphone itself
--- is not delivering anything.
---@param text string
---@param done fun(text: string)
local function heard(text, done)
  drop_timer()
  drop_partial()
  job.proc = nil
  job.wav = nil
  state.level = 0
  state.level_db = nil
  state.partial = ''
  local said = vim.trim((text or ''):gsub('%s+', ' '))
  if said == '' and not state.signal then
    set_phase('error', { heard = '', error = 'the microphone delivered no sound' })
    done ''
    return
  end
  set_phase(said == '' and 'idle' or 'thinking', { heard = said })
  done(said)
end

--- Read `wav` back into words: the user's own command (`OMP_VOICE_STT`, the
--- wav path as `$1`), Windows' recognizer on the file, or whisper.cpp. A
--- `quiet` read is the words of a sentence still being said: it hands them to
--- `done` and leaves the listen alone. Only the final read ends it.
---@param wav string
---@param backend string
---@param done fun(text: string)
---@param quiet? boolean
local function transcribe(wav, backend, done, quiet)
  local cmd, env
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
  else
    cmd = { exe 'whisper-cli' and 'whisper-cli' or 'main', '-m', whisper_model(), '-f', wav, '-nt', '-np' }
    local lang = opts.lang or vim.env.OMP_VOICE_LANG
    if lang then
      vim.list_extend(cmd, { '-l', lang })
    end
    env = audio_env()
  end
  pcall(vim.system, cmd, { text = true, env = env }, function(obj)
    pcall(uv.fs_unlink, wav)
    local text = text_of(obj)
    vim.schedule(function()
      if quiet then
        done(text)
      else
        heard(text, done)
      end
    end)
  end)
end

--- Close the wav and fill in its two sizes, so the file is whole before any
--- transcriber opens it. Safe to call twice: the handle is gone after the
--- first.
local function close_wav()
  if not job.fd then
    return
  end
  local bytes = job.bytes or 0
  pcall(uv.fs_write, job.fd, u32(36 + bytes), 4)
  pcall(uv.fs_write, job.fd, u32(bytes), 40)
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

--- Read the words of the recording so far, again and again, until the
--- recording stops: this is the text the screen shows while the sentence is
--- still being said.
---@param backend string|nil
local function peek(backend)
  if not backend or (opts.partial_seconds or 0) <= 0 then
    return
  end
  partial.timer = uv.new_timer()
  partial.timer:start(opts.partial_seconds * 1000, opts.partial_seconds * 1000, function()
    vim.schedule(function()
      if state.phase ~= 'listening' or partial.busy then
        return
      end
      local path = snapshot()
      if not path then
        return
      end
      partial.busy = true
      transcribe(path, backend, function(text)
        partial.busy = false
        local words = vim.trim((text or ''):gsub('%s+', ' '))
        if state.phase == 'listening' and words ~= '' then
          state.partial = words
        end
      end, true)
    end)
  end)
end

--- Record until a second click (or the cap), then transcribe. `parec`
--- streams the microphone as raw PCM instead of writing a file itself, which
--- is what lets the same bytes become both the wav and the level: an
--- encoded recorder buffers its output and the meter would only arrive when
--- the recording ended. Every chunk is measured for the card and appended to
--- the wav; stopping closes the file before anything reads it.
---@param backend string|nil
---@param done fun(text: string)
local function start_recording(backend, done)
  local wav = vim.fn.tempname() .. '.wav'
  local fd = uv.fs_open(wav, 'w', 384)
  if not fd then
    set_phase('error', { error = 'could not write the recording' })
    done ''
    return
  end
  job.wav, job.fd, job.bytes = wav, fd, 0
  uv.fs_write(fd, wav_header(0), 0)
  local function finished()
    close_wav()
    drop_partial()
    if state.phase ~= 'listening' then
      pcall(uv.fs_unlink, wav)
      return
    end
    job.proc = nil
    drop_timer()
    if vim.fn.filereadable(wav) ~= 1 then
      heard('', done)
      return
    end
    if not backend then
      pcall(uv.fs_unlink, wav)
      job.wav = nil
      set_phase('error', { error = 'recorded, but no speech-to-text is installed' })
      done ''
      return
    end
    set_phase 'thinking'
    transcribe(wav, backend, done)
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
    vim.schedule(finished)
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
  job.timer = uv.new_timer()
  job.timer:start(opts.listen_seconds * 1000, 0, function()
    vim.schedule(function()
      if state.phase == 'listening' and job.proc then
        pcall(handle.kill, handle, 'sigint')
      end
    end)
  end)
  peek(backend)
end

--- Listen once and hand the words to `done`: record through PulseAudio, show
--- the level while it records, then read the file back. Recording comes first
--- even when no transcriber is installed, because a silent level is the
--- answer to "is the microphone working at all".
---@param done fun(text: string)
local function listen(done)
  if not exe 'parec' then
    set_phase('error', { error = 'no recorder: parec (pulseaudio-utils) is not installed' })
    done ''
    return
  end
  set_phase('listening', { level = 0, level_db = nil, signal = false, partial = '', heard = '' })
  start_recording(stt_backend(), done)
end

-- ------------------------------------------------------------------ the run

--- Hand the heard words to a fresh `omp` instance in a tmux pane: from here on
--- the run decides what to do with them inside the org system, the buddy only
--- carries them and says which view they came from.
---@param text string
local function launch(text)
  if text == '' then
    return
  end
  local org_dir = vim.fn.expand '~/org'
  pcall(function()
    local cfg = require('org.config').opts
    if cfg and cfg.org_directory then
      org_dir = vim.fn.expand(cfg.org_directory)
    end
  end)
  local message = ('Spoken to the org dashboard (%s view): "%s". The vault is at %s; work it out from there.'):format(
    state.view ~= '' and state.view or 'dashboard',
    text,
    org_dir
  )
  local ok, err = pcall(function()
    require('helpers.org.ai').open_prompt(message, '🤖 ' .. text:sub(1, 40))
  end)
  if not ok then
    set_phase('error', { error = tostring(err) })
    notify('voice: ' .. tostring(err), vim.log.levels.ERROR)
    return
  end
  set_phase 'idle'
end

--- Does the card say anything at all? Off by default: it is a microphone and
--- a run, not a speaker, and the voice was getting in the way. `speak =
--- true` in setup, or `OMP_VOICE_SPEAK=1`, brings it back.
local function speaks()
  return opts.speak and tts_backend() ~= nil
end

--- The whole conversation: listen, read the words back, hand them to a run.
--- The click is acknowledged out loud only when the voice is on. `view` names
--- what the dashboard had open when the mic was clicked, so the run is told
--- where the words came from.
---@param view? string
function M.converse(view)
  if state.phase ~= 'idle' and state.phase ~= 'error' then
    return false
  end
  local function begin()
    listen(function(text)
      M._said(text)
    end)
  end
  set_phase('idle', { view = vim.trim(view or ''), heard = '', partial = '', error = '' })
  if not speaks() then
    begin()
    return true
  end
  set_phase 'speaking'
  speak(state.view ~= '' and ('Listening on ' .. state.view) or 'Listening', function()
    if state.phase == 'speaking' then
      begin()
    end
  end)
  return true
end

--- What was heard: start the run from it, saying it back first when the voice
--- is on.
---@param text string
function M._said(text)
  local said = vim.trim((text or ''):gsub('%s+', ' '))
  if said == '' then
    set_phase('idle', { heard = '' })
    return
  end
  set_phase('thinking', { heard = said })
  if speaks() then
    speak(said, function()
      launch(said)
    end)
  else
    launch(said)
  end
end

--- Stop whatever is running: the second click on a listening mic, and the
--- escape hatch when a program hangs.
function M.cancel()
  if job.proc then
    local handle = job.proc
    job.proc = nil
    pcall(handle.kill, handle, 'sigterm')
  end
  drop_timer()
  drop_partial()
  if job.fd then
    close_wav()
    if job.wav then
      pcall(uv.fs_unlink, job.wav)
      job.wav = nil
    end
  end
  set_phase('idle', { heard = '', partial = '', level = 0, level_db = nil })
end

--- `:OrgVoiceSay {text}`: the run without the microphone -- the same path the
--- card takes once it has words, so it is also what a test drives.
---@param text string
function M.say(text)
  M._said(text)
end

--- `:OrgVoiceSpeak {text}`: just the speaking half.
---@param text string
---@return boolean speaking
function M.speak(text)
  return speak(text)
end

function M.setup(user)
  opts = vim.tbl_extend('force', opts, user or {})
  if vim.env.OMP_VOICE_LISTEN_SECONDS then
    opts.listen_seconds = tonumber(vim.env.OMP_VOICE_LISTEN_SECONDS) or opts.listen_seconds
  end
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
  vim.api.nvim_create_user_command('OrgVoice', function()
    M.converse()
  end, { desc = 'voice: say a line, listen, start a run from the words' })
  vim.api.nvim_create_user_command('OrgVoiceSay', function(args)
    M.say(args.args)
  end, { nargs = '+', desc = 'voice: start a run from the words, without the microphone' })
  vim.api.nvim_create_user_command('OrgVoiceSpeak', function(args)
    M.speak(args.args)
  end, { nargs = '+', desc = 'voice: just say it' })
  vim.api.nvim_create_user_command('OrgVoiceCancel', function()
    M.cancel()
  end, { desc = 'voice: stop listening' })
end

return M
