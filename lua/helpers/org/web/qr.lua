-- A QR code big enough for a URL, drawn as SVG.
--
-- Byte mode, versions 1 to 10 (a tunnel URL never needs more), error
-- correction picked by `level`, mask chosen by the standard penalty score.
-- The rules and the constant tables are the ones every encoder follows
-- (Project Nayuki's qrcodegen is the reference this is ported from); the
-- page only needs the drawing, so this draws an SVG and nothing else.
local M = {}

local VERSIONS = 10

-- [level][version], version 1 at index 1. The four levels are the standard
-- ones: low, medium, quartile, high.
local ECC_PER_BLOCK = {
  { 7, 10, 15, 20, 26, 18, 20, 24, 30, 18 },
  { 10, 16, 26, 18, 24, 16, 18, 22, 22, 26 },
  { 13, 22, 18, 26, 18, 24, 18, 22, 20, 24 },
  { 17, 28, 22, 16, 22, 28, 26, 26, 24, 28 },
}

local NUM_BLOCKS = {
  { 1, 1, 1, 1, 1, 2, 2, 2, 2, 4 },
  { 1, 1, 1, 2, 2, 4, 4, 4, 5, 5 },
  { 1, 1, 2, 2, 4, 4, 6, 6, 8, 8 },
  { 1, 1, 2, 4, 4, 4, 5, 6, 8, 8 },
}

local ORDINAL = { L = 1, M = 2, Q = 3, H = 4 }
-- the two-bit code a level carries in the format bits
local FORMAT_BITS = { 1, 0, 3, 2 }

--- XOR of two non-negative integers, bit by bit. Lua 5.1 has no operator for
--- it and the values here are small.
local function bxor(a, b)
  local out, bit = 0, 1
  while a > 0 or b > 0 do
    local x, y = a % 2, b % 2
    if x ~= y then
      out = out + bit
    end
    a, b, bit = (a - x) / 2, (b - y) / 2, bit * 2
  end
  return out
end

local function raw_data_modules(ver)
  local result = (16 * ver + 128) * ver + 64
  if ver >= 2 then
    local num_align = math.floor(ver / 7) + 2
    result = result - (25 * num_align - 10) * num_align + 55
    if ver >= 7 then
      result = result - 36
    end
  end
  return result
end

local function data_codewords(ver, ord)
  return math.floor(raw_data_modules(ver) / 8) - ECC_PER_BLOCK[ord][ver] * NUM_BLOCKS[ord][ver]
end

--- GF(256) multiply, the QR field's polynomial (x^8 + x^4 + x^3 + x^2 + 1).
local gf = (function()
  local exp, log = {}, {}
  local x = 1
  for i = 0, 255 do
    exp[i] = x
    log[x] = i
    x = x * 2
    if x >= 256 then
      x = bxor(x, 0x11D)
    end
  end
  return function(a, b)
    if a == 0 or b == 0 then
      return 0
    end
    return exp[(log[a] + log[b]) % 255]
  end
end)()

local function rs_divisor(degree)
  local result = {}
  for i = 1, degree - 1 do
    result[i] = 0
  end
  result[degree] = 1
  local root = 1
  for _ = 1, degree do
    for j = 1, degree do
      result[j] = gf(result[j], root)
      if j + 1 <= degree then
        result[j] = bxor(result[j], result[j + 1])
      end
    end
    root = gf(root, 2)
  end
  return result
end

local function rs_remainder(data, divisor)
  local result = {}
  for i = 1, #divisor do
    result[i] = 0
  end
  for _, b in ipairs(data) do
    local factor = bxor(b, table.remove(result, 1))
    result[#result + 1] = 0
    for i, coef in ipairs(divisor) do
      result[i] = bxor(result[i], gf(coef, factor))
    end
  end
  return result
end

local function char_count_bits(ver)
  return ver <= 9 and 8 or 16
end

--- The data codewords of `text` at `ver`: mode, length, bytes, terminator,
--- padding.
local function payload(text, ver, ord)
  local bits = {}
  local function append(value, len)
    for i = len - 1, 0, -1 do
      bits[#bits + 1] = math.floor(value / 2 ^ i) % 2
    end
  end
  append(4, 4) -- byte mode
  append(#text, char_count_bits(ver))
  for i = 1, #text do
    append(text:byte(i), 8)
  end
  local capacity = data_codewords(ver, ord) * 8
  append(0, math.min(4, capacity - #bits))
  append(0, (8 - #bits % 8) % 8)
  local pad = { 0xEC, 0x11 }
  local i = 1
  while #bits < capacity do
    append(pad[i], 8)
    i = i == 1 and 2 or 1
  end
  local out = {}
  for k = 1, #bits / 8 do
    local byte = 0
    for j = 1, 8 do
      byte = byte * 2 + bits[(k - 1) * 8 + j]
    end
    out[k] = byte
  end
  return out
end

--- Split the data into blocks, add each block's error correction, and
--- interleave the lot -- the order a scanner reads the codewords in.
local function interleave(data, ver, ord)
  local num_blocks = NUM_BLOCKS[ord][ver]
  local ecc_len = ECC_PER_BLOCK[ord][ver]
  local raw = math.floor(raw_data_modules(ver) / 8)
  local short_count = num_blocks - raw % num_blocks
  local short_len = math.floor(raw / num_blocks)
  local divisor = rs_divisor(ecc_len)
  local blocks = {}
  local k = 1
  for i = 1, num_blocks do
    local take = short_len - ecc_len + (i <= short_count and 0 or 1)
    local dat = {}
    for j = 1, take do
      dat[j] = data[k]
      k = k + 1
    end
    local ecc = rs_remainder(dat, divisor)
    if i <= short_count then
      dat[#dat + 1] = 0
    end
    for _, b in ipairs(ecc) do
      dat[#dat + 1] = b
    end
    blocks[i] = dat
  end
  local out = {}
  for i = 1, #blocks[1] do
    for j = 1, num_blocks do
      if i ~= short_len - ecc_len + 1 or j > short_count then
        out[#out + 1] = blocks[j][i]
      end
    end
  end
  return out
end

local function alignment_positions(ver)
  if ver == 1 then
    return {}
  end
  local num = math.floor(ver / 7) + 2
  local step = math.ceil((ver * 4 + 4) / (num * 2 - 2)) * 2
  local last = ver * 4 + 10
  local out = { 6 }
  for i = 1, num - 1 do
    out[#out + 1] = last - (num - 1 - i) * step
  end
  return out
end

local function new_grid(size, fill)
  local grid = {}
  for y = 1, size do
    grid[y] = {}
    for x = 1, size do
      grid[y][x] = fill
    end
  end
  return grid
end

local function encoder(text, ord)
  local ver
  for v = 1, VERSIONS do
    if 4 + char_count_bits(v) + #text * 8 <= data_codewords(v, ord) * 8 then
      ver = v
      break
    end
  end
  if not ver then
    return nil, 'text too long for a version-' .. VERSIONS .. ' code'
  end
  local codewords = interleave(payload(text, ver, ord), ver, ord)

  local size = ver * 4 + 17
  local mod = new_grid(size, false)
  local fn = new_grid(size, false)
  local qr = { ver = ver, size = size, modules = mod }

  local function set(x, y, dark)
    mod[y][x] = dark
    fn[y][x] = true
  end

  local function finder(cx, cy)
    for dy = -4, 4 do
      for dx = -4, 4 do
        local x, y = cx + dx, cy + dy
        if x >= 1 and x <= size and y >= 1 and y <= size then
          local dist = math.max(math.abs(dx), math.abs(dy))
          set(x, y, dist ~= 2 and dist ~= 4)
        end
      end
    end
  end

  local function align(cx, cy)
    for dy = -2, 2 do
      for dx = -2, 2 do
        set(cx + dx, cy + dy, math.max(math.abs(dx), math.abs(dy)) ~= 1)
      end
    end
  end

  local function format_bits(mask)
    local data = FORMAT_BITS[ord] * 8 + mask
    local rem = data
    for _ = 1, 10 do
      local hi = math.floor(rem / 512) % 2
      rem = rem * 2
      if hi == 1 then
        rem = bxor(rem, 0x537)
      end
    end
    local bits = bxor(data * 1024 + rem, 0x5412)

    local function bit(i)
      return math.floor(bits / 2 ^ i) % 2 == 1
    end
    for i = 0, 5 do
      set(9, i + 1, bit(i))
    end
    set(9, 8, bit(6))
    set(9, 9, bit(7))
    set(8, 9, bit(8))
    for i = 9, 14 do
      set(15 - i, 9, bit(i))
    end
    for i = 0, 7 do
      set(size - i, 9, bit(i))
    end
    for i = 8, 14 do
      set(9, size - 15 + i + 1, bit(i))
    end
    set(9, size - 7, true)
  end

  local function version_bits()
    if ver < 7 then
      return
    end
    local rem = ver
    for _ = 1, 12 do
      local hi = math.floor(rem / 2048) % 2
      rem = rem * 2
      if hi == 1 then
        rem = bxor(rem, 0x1F25)
      end
    end
    local bits = ver * 4096 + rem
    for i = 0, 17 do
      local bit = math.floor(bits / 2 ^ i) % 2 == 1
      local a = size - 11 + i % 3
      local b = math.floor(i / 3)
      set(a + 1, b + 1, bit)
      set(b + 1, a + 1, bit)
    end
  end

  -- timing patterns
  for i = 1, size do
    set(7, i, i % 2 == 1)
    set(i, 7, i % 2 == 1)
  end
  finder(4, 4)
  finder(size - 3, 4)
  finder(4, size - 3)
  local pos = alignment_positions(ver)
  for i, cx in ipairs(pos) do
    for j, cy in ipairs(pos) do
      local corner = (i == 1 and j == 1) or (i == 1 and j == #pos) or (i == #pos and j == 1)
      if not corner then
        -- the positions are zero-based; the grid is one-based
        align(cx + 1, cy + 1)
      end
    end
  end
  format_bits(0)
  version_bits()

  -- the data, zigzagging up and down the columns in pairs
  local i = 1
  local right = size
  while right >= 1 do
    if right == 7 then
      right = 6
    end
    local upward = right % 4 < 2
    for vert = 0, size - 1 do
      for j = 0, 1 do
        local x = right - j
        local y = upward and (size - vert) or (vert + 1)
        if not fn[y][x] and i <= #codewords * 8 then
          local byte = codewords[math.floor((i - 1) / 8) + 1]
          mod[y][x] = math.floor(byte / 2 ^ (7 - (i - 1) % 8)) % 2 == 1
          i = i + 1
        end
      end
    end
    right = right - 2
  end

  local function masked(mask, x, y)
    -- x and y are zero-based here
    if mask == 0 then
      return (x + y) % 2 == 0
    elseif mask == 1 then
      return y % 2 == 0
    elseif mask == 2 then
      return x % 3 == 0
    elseif mask == 3 then
      return (x + y) % 3 == 0
    elseif mask == 4 then
      return (math.floor(x / 3) + math.floor(y / 2)) % 2 == 0
    elseif mask == 5 then
      return x * y % 2 + x * y % 3 == 0
    elseif mask == 6 then
      return (x * y % 2 + x * y % 3) % 2 == 0
    end
    return ((x + y) % 2 + x * y % 3) % 2 == 0
  end

  local function flip(mask)
    for y = 1, size do
      for x = 1, size do
        if not fn[y][x] and masked(mask, x - 1, y - 1) then
          mod[y][x] = not mod[y][x]
        end
      end
    end
  end

  local finder_a = { true, false, true, true, true, false, true, false, false, false, false }
  local finder_b = { false, false, false, false, true, false, true, true, true, false, true }

  local function penalty()
    local score = 0
    for y = 1, size do
      local run, last = 1, mod[y][1]
      for x = 2, size do
        if mod[y][x] == last then
          run = run + 1
        else
          if run >= 5 then
            score = score + run - 2
          end
          run, last = 1, mod[y][x]
        end
      end
      if run >= 5 then
        score = score + run - 2
      end
      for x = 1, size - 10 do
        local a, b = true, true
        for k = 1, 11 do
          if mod[y][x + k - 1] ~= finder_a[k] then
            a = false
          end
          if mod[y][x + k - 1] ~= finder_b[k] then
            b = false
          end
        end
        if a then
          score = score + 40
        end
        if b then
          score = score + 40
        end
      end
    end
    for x = 1, size do
      local run, last = 1, mod[1][x]
      for y = 2, size do
        if mod[y][x] == last then
          run = run + 1
        else
          if run >= 5 then
            score = score + run - 2
          end
          run, last = 1, mod[y][x]
        end
      end
      if run >= 5 then
        score = score + run - 2
      end
      for y = 1, size - 10 do
        local a, b = true, true
        for k = 1, 11 do
          if mod[y + k - 1][x] ~= finder_a[k] then
            a = false
          end
          if mod[y + k - 1][x] ~= finder_b[k] then
            b = false
          end
        end
        if a then
          score = score + 40
        end
        if b then
          score = score + 40
        end
      end
    end
    for y = 1, size - 1 do
      for x = 1, size - 1 do
        local c = mod[y][x]
        if mod[y][x + 1] == c and mod[y + 1][x] == c and mod[y + 1][x + 1] == c then
          score = score + 3
        end
      end
    end
    local dark = 0
    for y = 1, size do
      for x = 1, size do
        if mod[y][x] then
          dark = dark + 1
        end
      end
    end
    local total = size * size
    score = score + math.floor(math.abs(dark * 20 - total * 10) / total) * 10
    return score
  end

  local best, best_score = 0, math.huge
  for mask = 0, 7 do
    flip(mask)
    format_bits(mask)
    local s = penalty()
    flip(mask)
    if s < best_score then
      best, best_score = mask, s
    end
  end
  flip(best)
  format_bits(best)
  return qr
end

--- The code for `text` as an SVG string: `size` pixels square, black on
--- white (a camera reads the colour, not the page's theme) with the four
--- modules of quiet zone a scanner needs.
---@param text string
---@param opts? table { level = 'L'|'M'|'Q'|'H', size = px, quiet = modules, title = string }
---@return string|nil svg, string|nil err
function M.svg(text, opts)
  opts = opts or {}
  local ord = ORDINAL[opts.level or 'M']
  if not ord then
    return nil, 'unknown error correction level: ' .. tostring(opts.level)
  end
  local qr, err = encoder(tostring(text), ord)
  if not qr then
    return nil, err
  end
  local quiet = opts.quiet or 4
  local span = qr.size + quiet * 2
  local px = math.floor(opts.size or 160)

  local runs = {}
  for y = 1, qr.size do
    local x = 1
    while x <= qr.size do
      if qr.modules[y][x] then
        local start = x
        while x <= qr.size and qr.modules[y][x] do
          x = x + 1
        end
        local w = x - start
        runs[#runs + 1] = ('M%d %dh%dv1h%dz'):format(start - 1 + quiet, y - 1 + quiet, w, -w)
      else
        x = x + 1
      end
    end
  end

  local label = ((opts.title or 'QR code'):gsub('[^%w %-_:%.]', ''))
  return (
    table.concat({
      ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d" role="img" aria-label="%s" shape-rendering="crispEdges">'):format(
        span,
        span,
        px,
        px,
        label
      ),
      '<rect width="100%" height="100%" fill="#ffffff"/>',
      ('<path fill="#000000" d="%s"/>'):format(table.concat(runs, '')),
      '</svg>',
    }, '')
  )
end

return M
