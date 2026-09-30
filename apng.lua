-- APNG 組立モジュール（純Lua・Aseprite 非依存）
-- PNG バイト列のチャンク解析、IDAT→fdAT 詰め替え、acTL/fcTL 生成、CRC32 計算を担う。
-- Lua 5.3 系（string.pack / ビット演算）を前提とする。

local apng = {}

local PNG_SIG = "\137PNG\r\n\026\n"

-- CRC32（PNG 規格の多項式 0xEDB88320）
local crc_table = {}
for i = 0, 255 do
  local c = i
  for _ = 1, 8 do
    if (c & 1) ~= 0 then
      c = (c >> 1) ~ 0xEDB88320
    else
      c = c >> 1
    end
  end
  crc_table[i] = c
end

function apng.crc32(data)
  local c = 0xFFFFFFFF
  for i = 1, #data do
    c = (c >> 8) ~ crc_table[((c ~ data:byte(i)) & 0xFF)]
  end
  return c ~ 0xFFFFFFFF
end

local function pack_chunk(ctype, cdata)
  return string.pack(">I4", #cdata)
    .. ctype
    .. cdata
    .. string.pack(">I4", apng.crc32(ctype .. cdata))
end
apng.pack_chunk = pack_chunk

-- PNG バイト列をチャンク列に分解する。
-- 戻り値: { chunks = { {type=, data=}, ... }, ihdr = <13バイト>, idat = { payload, ... } }
-- 失敗時は nil, エラーメッセージ。
function apng.parse_png(data)
  if type(data) ~= "string" or #data < 8 or data:sub(1, 8) ~= PNG_SIG then
    return nil, "not a PNG file"
  end
  local chunks = {}
  local ihdr, idat = nil, {}
  local pos = 9
  while pos + 7 <= #data do
    local len = string.unpack(">I4", data, pos)
    local ctype = data:sub(pos + 4, pos + 7)
    if pos + 11 + len > #data then
      return nil, "truncated chunk: " .. ctype
    end
    local cdata = data:sub(pos + 8, pos + 7 + len)
    local crc = string.unpack(">I4", data, pos + 8 + len)
    if crc ~= apng.crc32(ctype .. cdata) then
      return nil, "CRC mismatch in chunk: " .. ctype
    end
    if ctype == "IHDR" then
      if len ~= 13 then
        return nil, "invalid IHDR length: " .. len
      end
      ihdr = cdata
    elseif ctype == "IDAT" then
      idat[#idat + 1] = cdata
    elseif ctype == "IEND" then
      chunks[#chunks + 1] = { type = ctype, data = cdata }
      pos = pos + 12 + len
      break
    end
    chunks[#chunks + 1] = { type = ctype, data = cdata }
    pos = pos + 12 + len
  end
  if pos ~= #data + 1 or chunks[#chunks].type ~= "IEND" then
    return nil, "missing IEND chunk"
  end
  if not ihdr then
    return nil, "missing IHDR chunk"
  end
  if #idat == 0 then
    return nil, "missing IDAT chunk"
  end
  return { chunks = chunks, ihdr = ihdr, idat = idat }
end

-- フレーム時間（秒）を fcTL の delay_num/delay_den に変換する。
-- delay_den=1000 固定のミリ秒丸め。0 になる場合は 1 に補正する。
function apng.duration_to_delay(seconds)
  if type(seconds) ~= "number" or seconds ~= seconds or seconds < 0 then
    seconds = 0.1
  end
  local num = math.floor(seconds * 1000 + 0.5)
  if num < 1 then
    num = 1
  elseif num > 65535 then
    num = 65535
  end
  return num, 1000
end

local function pack_fctl(seq, width, height, delay_num, delay_den)
  return pack_chunk("fcTL", string.pack(">I4I4I4I4I4I2I2BB",
    seq, width, height, 0, 0, delay_num, delay_den, 0, 0))
end

-- フレーム列から APNG バイナリを組み立てる。
-- frames[i] = { png = <PNGバイト列>, duration = <秒> }
-- 構成: シグネチャ, IHDR, acTL, (先頭PNGの事前IDAT補助チャンク),
--       fcTL+IDAT（先頭フレーム）, fcTL+fdAT（2フレーム目以降）, IEND
-- dispose op = NONE、blend op = SOURCE、num_plays = 0（無限ループ）。
-- 成功時は APNG バイト列、失敗時は nil, エラーメッセージ。
function apng.assemble(frames)
  if type(frames) ~= "table" or #frames == 0 then
    return nil, "no frames"
  end

  local parsed = {}
  local ihdr
  for i = 1, #frames do
    local frame = frames[i]
    local png = type(frame) == "table" and frame.png or frame
    local p, err = apng.parse_png(png)
    if not p then
      return nil, string.format("frame %d: %s", i, err)
    end
    if i == 1 then
      ihdr = p.ihdr
    elseif p.ihdr ~= ihdr then
      return nil, string.format("frame %d: IHDR does not match the first frame", i)
    end
    parsed[i] = p
  end

  local width, height = string.unpack(">I4I4", ihdr)

  local out = {
    PNG_SIG,
    pack_chunk("IHDR", ihdr),
    pack_chunk("acTL", string.pack(">I4I4", #frames, 0)),
  }

  -- 先頭フレームの事前 IDAT 補助チャンク（PLTE/tRNS 等）を引き継ぐ
  for _, c in ipairs(parsed[1].chunks) do
    if c.type == "IDAT" then
      break
    elseif c.type ~= "IHDR" then
      out[#out + 1] = pack_chunk(c.type, c.data)
    end
  end

  local seq = 0
  for i = 1, #frames do
    local duration = type(frames[i]) == "table" and frames[i].duration or nil
    local delay_num, delay_den = apng.duration_to_delay(duration)
    out[#out + 1] = pack_fctl(seq, width, height, delay_num, delay_den)
    seq = seq + 1
    if i == 1 then
      -- 先頭フレームはデフォルト画像として IDAT のまま出力する
      for _, payload in ipairs(parsed[1].idat) do
        out[#out + 1] = pack_chunk("IDAT", payload)
      end
    else
      local fdat = string.pack(">I4", seq) .. table.concat(parsed[i].idat)
      out[#out + 1] = pack_chunk("fdAT", fdat)
      seq = seq + 1
    end
  end

  out[#out + 1] = pack_chunk("IEND", "")
  return table.concat(out)
end

return apng
