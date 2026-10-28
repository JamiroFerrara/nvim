-- The voice buddy's engine: what sits behind the orb on the org dashboard
-- (lua/helpers/org/web/assets/jarvis.js, served by helpers/org/web/).
--
-- The orb is UI and lives in the browser; this is the part that needs the
-- machine. A click comes in as `POST /api/voice` (helpers/org/web/init.lua)
-- and the conversation runs here:
--
--   1. speak a line about the view that was clicked -- the click registering
--   2. listen, and read back what was heard
--   3. hand the words to an `omp` instance in a tmux pane
--      (`helpers.org.ai.open_prompt`): that run decides what to do with them
--      inside the org system, the buddy only carries the words
--
-- Everything is local. Each half is picked from what the machine has, and a
-- missing speaker or microphone degrades instead of breaking:
--
--   text -> speech |  piper, espeak-ng, spd-say, or Windows' own voice
--                  |  (System.Speech, through powershell.exe under WSL)
--   recording     |  ffmpeg on PulseAudio (`/mnt/wslg/PulseServer` under WSLg)
--   speech -> text |  whisper.cpp (`whisper-cli`), or Windows' own dictation
--
-- Overrides, when the detection guesses wrong: `OMP_VOICE_TTS` (a shell
-- command, the words on stdin), `OMP_VOICE_STT` (a shell command, the wav
-- path as `$1`), `OMP_VOICE_WHISPER_MODEL`, `OMP_VOICE_LANG`,
-- `OMP_VOICE_PIPER_MODEL`, `OMP_VOICE_LISTEN_SECONDS`.
--
-- The browser polls `GET /api/voice` for `M.status()` while the orb is open:
-- the phase is what it draws (idle, speaking, listening, thinking, error) and
-- `heard` is the words it puts on the panel.

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
  lang = nil,
  tts = nil,
  stt = nil,
  whisper_model = nil,
}

--- What the orb draws. `phase` is the state machine's, `heard` the words the
--- last listen produced, `view` the dashboard view the click came from and
--- `error` what went wrong, if anything.
local state = {
  phase = 'idle',
  heard = '',
  view = '',
  error = '',
  at = 0,
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
    view = state.view,
    error = state.error,
    at = state.at,
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

--- The PulseAudio server WSLg runs for the distro. `ffmpeg -f pulse` needs it
--- named: nothing sets PULSE_SERVER in a WSL shell, so a recorder would find
--- no source without this.
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

--- The listening half: whisper.cpp when the machine has both the binary and a
--- model (better dictation, and no desktop session involved), else Windows'
--- own recognizer.
---@return string|nil backend
function stt_backend()
  if opts.stt and opts.stt ~= '' then
    return 'custom'
  end
  if (exe 'whisper-cli' or exe 'main') and exe 'ffmpeg' and whisper_model() then
    return 'whisper'
  end
  if windows() then
    return 'windows'
  end
end

--- Windows' own dictation, through interop: the recognizer listens to the
--- default microphone itself (no recording, no file), stops at the first
--- pause after speech and caps the whole wait at the listening window.
local PS_LISTEN = table.concat({
  'Add-Type -AssemblyName System.Speech;',
  '$r = New-Object System.Speech.Recognition.SpeechRecognitionEngine;',
  '$r.LoadGrammar((New-Object System.Speech.Recognition.DictationGrammar));',
  '$r.SetInputToDefaultAudioDevice();',
  '$w = [int]$env:OMP_VOICE_LISTEN_SECONDS; if ($w -le 0) { $w = 10 };',
  '$r.InitialSilenceTimeout = [TimeSpan]::FromSeconds($w);',
  '$r.BabbleTimeout = [TimeSpan]::FromSeconds(3);',
  '$x = $r.Recognize([TimeSpan]::FromSeconds($w));',
  'if ($x) { [Console]::Out.Write($x.Text) }',
}, ' ')

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
local job = { proc = nil, timer = nil, wav = nil }

local function drop_timer()
  if job.timer then
    pcall(job.timer.stop, job.timer)
    pcall(job.timer.close, job.timer)
    job.timer = nil
  end
end

--- Close the listen and hand `text` (empty when nothing was heard) to `done`,
--- once. Every way out -- the recognizer answering, the recorder stopped, the
--- cap firing, a program failing -- comes through here, so the phase always
--- returns to idle.
---@param text string
---@param done fun(text: string)
local function heard(text, done)
  drop_timer()
  job.proc = nil
  local said = vim.trim((text or ''):gsub('%s+', ' '))
  set_phase(said == '' and 'idle' or 'thinking', { heard = said })
  done(said)
end

--- Read `wav` back into words: whisper.cpp, or the user's own command
--- (`OMP_VOICE_STT`, the wav path as `$1`).
---@param wav string
---@param backend string
---@param done fun(text: string)
local function transcribe(wav, backend, done)
  local cmd
  if backend == 'custom' then
    cmd = { 'sh', '-c', opts.stt .. ' "$1"', 'sh', wav }
  else
    cmd = { exe 'whisper-cli' and 'whisper-cli' or 'main', '-m', whisper_model(), '-f', wav, '-nt', '-np' }
    local lang = opts.lang or vim.env.OMP_VOICE_LANG
    if lang then
      vim.list_extend(cmd, { '-l', lang })
    end
  end
  pcall(vim.system, cmd, { text = true, env = audio_env() }, function(obj)
    pcall(uv.fs_unlink, wav)
    local text = text_of(obj)
    vim.schedule(function()
      heard(text, done)
    end)
  end)
end

--- Record until a second click (or the cap), then transcribe. ffmpeg closes
--- the wav on SIGINT, so its own exit is what says the file is whole.
---@param backend string
---@param done fun(text: string)
local function start_recording(backend, done)
  local wav = vim.fn.tempname() .. '.wav'
  job.wav = wav
  local function finished()
    if state.phase ~= 'listening' then
      return
    end
    job.proc = nil
    drop_timer()
    if vim.fn.filereadable(wav) == 1 then
      set_phase 'thinking'
      transcribe(wav, backend, done)
    else
      heard('', done)
    end
  end
  local ok, handle = pcall(vim.system, {
    'ffmpeg',
    '-hide_banner',
    '-loglevel',
    'error',
    '-f',
    'pulse',
    '-i',
    'default',
    '-ar',
    '16000',
    '-ac',
    '1',
    '-y',
    wav,
  }, { env = audio_env() }, function()
    vim.schedule(finished)
  end)
  if not ok then
    set_phase('error', { error = 'could not start the recorder' })
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
end

--- Listen once and hand the words to `done`: record through PulseAudio and
--- let whisper read it back, ask Windows' recognizer, or -- with neither --
--- report that there is no microphone on this machine.
---@param done fun(text: string)
local function listen(done)
  local backend = stt_backend()
  if not backend then
    set_phase('error', { error = 'no microphone backend (whisper.cpp + ffmpeg, or Windows speech)' })
    done ''
    return
  end
  set_phase 'listening'

  if backend ~= 'windows' then
    start_recording(backend, done)
    return
  end

  -- the recognizer listens to the microphone itself and answers on the first
  -- pause, so its own window is the cap; the timer is the backstop for a
  -- program that never returns
  local ok, handle = pcall(vim.system, {
    'powershell.exe',
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    PS_LISTEN,
  }, {
    text = true,
    env = { OMP_VOICE_LISTEN_SECONDS = tostring(opts.listen_seconds) },
  }, function(obj)
    local text = text_of(obj)
    vim.schedule(function()
      heard(text, done)
    end)
  end)
  if not ok then
    set_phase('error', { error = 'could not start the recognizer' })
    return
  end
  job.proc = handle
  job.timer = uv.new_timer()
  job.timer:start((opts.listen_seconds + 5) * 1000, 0, function()
    vim.schedule(function()
      if state.phase == 'listening' then
        heard('', done)
      end
    end)
  end)
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
  local message = ('Said out loud on the org dashboard (%s view): "%s". The vault is at %s; work it out from there.'):format(
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

--- The whole conversation: acknowledge the click out loud, listen, read the
--- words back, hand them to a run. `view` names what the dashboard had open
--- when the orb was clicked, so the run is told where the words came from.
---@param view? string
function M.converse(view)
  if state.phase ~= 'idle' and state.phase ~= 'error' then
    return false
  end
  set_phase('speaking', { view = vim.trim(view or ''), heard = '', error = '' })
  speak(state.view ~= '' and ('Listening on ' .. state.view) or 'Listening', function()
    if state.phase ~= 'speaking' then
      return
    end
    set_phase 'idle'
    listen(function(text)
      M._said(text)
    end)
  end)
  return true
end

--- What was heard: read it back so the user hears what the run was given, then
--- start the run.
---@param text string
function M._said(text)
  local said = vim.trim((text or ''):gsub('%s+', ' '))
  if said == '' then
    set_phase('idle', { heard = '' })
    return
  end
  set_phase('thinking', { heard = said })
  speak(said, function()
    launch(said)
  end)
end

--- Stop whatever is running: the second click on a listening orb, and the
--- escape hatch when a program hangs.
function M.cancel()
  if job.proc then
    local handle = job.proc
    job.proc = nil
    pcall(handle.kill, handle, 'sigterm')
  end
  drop_timer()
  set_phase('idle', { heard = '' })
end

--- `:OrgVoiceSay {text}`: the run without the microphone -- the same path the
--- orb takes once it has words, so it is also what a test drives.
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
