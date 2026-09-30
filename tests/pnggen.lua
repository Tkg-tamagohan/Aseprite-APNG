-- テスト用 PNG 生成器（純Lua・外部依存なし）
-- zlib の非圧縮（stored）DEFLATE ブロックを使い、実際にデコード可能な PNG を生成する。

local apng = require("apng")

local pnggen = {}

local function adler32(data)
  local a, b = 1, 0
  for i = 1, #data do
    a = (a + data:byte(i)) % 65521
    b = (b + a) % 65521
  end
  return (b << 16) | a
end

-- データを zlib stored ブロック列に包む（実装上は非圧縮だが正規の zlib ストリーム）
local function zlib_store(data)
  local out = { "\120\001" } -- CMF=0x78, FLG=0x01（チェックビット調整済み）
  local pos = 1
  repeat
    local n = math.min(65535, #data - pos + 1)
    local final = (pos + n - 1 == #data) and 1 or 0
    out[#out + 1] = string.pack("<I1I2I2", final, n, 0xFFFF - n)
    out[#out + 1] = data:sub(pos, pos + n - 1)
    pos = pos + n
  until pos > #data
  out[#out + 1] = string.pack(">I4", adler32(data))
  return table.concat(out)
end

local PNG_SIG = "\137PNG\r\n\026\n"

-- 生データから PNG を組み立てる。extra_chunks は { {type=, data=}, ... } で IDAT 前に挿入する。
local function build(width, height, bit_depth, color_type, raw_image, extra_chunks)
  local ihdr = string.pack(">I4I4BBBBB", width, height, bit_depth, color_type, 0, 0, 0)
  local out = { PNG_SIG, apng.pack_chunk("IHDR", ihdr) }
  for _, c in ipairs(extra_chunks or {}) do
    out[#out + 1] = apng.pack_chunk(c.type, c.data)
  end
  out[#out + 1] = apng.pack_chunk("IDAT", zlib_store(raw_image))
  out[#out + 1] = apng.pack_chunk("IEND", "")
  return table.concat(out)
end

-- RGBA8（color type 6）の単色 PNG を生成する。
-- rgba = { r, g, b, a }（省略可）
function pnggen.rgba(width, height, rgba)
  local px = string.char(
    (rgba and rgba[1]) or 0, (rgba and rgba[2]) or 0,
    (rgba and rgba[3]) or 0, (rgba and rgba[4]) or 255)
  local row = "\0" .. px:rep(width)
  return build(width, height, 8, 6, row:rep(height))
end

-- インデックスカラー（color type 3）の PNG を生成する。
-- PLTE/tRNS を含むため補助チャンク引き継ぎのテストに使う。
-- transparent_index を渡すと tRNS でそのパレット番号だけを透明（alpha=0）にする。
function pnggen.indexed(width, height, palette, index, transparent_index)
  local plte = {}
  for _, rgb in ipairs(palette) do
    plte[#plte + 1] = string.char(rgb[1], rgb[2], rgb[3])
  end
  local trns = "\255"
  if transparent_index then
    trns = string.rep("\255", transparent_index) .. "\0"
  end
  local row = "\0" .. string.char(index or 0):rep(width)
  return build(width, height, 8, 3, row:rep(height), {
    { type = "PLTE", data = table.concat(plte) },
    { type = "tRNS", data = trns },
  })
end

-- zlib stored ブロックを剥いて生データを取り出す（IDAT/fdAT ペイロード検証用）
function pnggen.unstore(zstream)
  local pos = 3 -- zlib ヘッダ 2 バイトを飛ばす
  local out = {}
  while true do
    local bfinal = zstream:byte(pos)
    local n = string.unpack("<I2", zstream, pos + 1)
    out[#out + 1] = zstream:sub(pos + 5, pos + 4 + n)
    pos = pos + 5 + n
    if bfinal == 1 then break end
  end
  return table.concat(out)
end

return pnggen
