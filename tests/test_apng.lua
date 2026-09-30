-- apng.lua スタンドアロンテスト
-- 実行: リポジトリルートで `lua5.3 tests/test_apng.lua`

package.path = "./?.lua;./tests/?.lua;" .. package.path

local apng = require("apng")
local pnggen = require("pnggen")

local passed, failed = 0, 0
local function check(cond, name)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. name)
  end
end
local function eq(got, want, name)
  check(got == want, string.format("%s (got %s, want %s)", name, tostring(got), tostring(want)))
end

local function chunk_types(parsed)
  local t = {}
  for _, c in ipairs(parsed.chunks) do
    t[#t + 1] = c.type
  end
  return table.concat(t, ",")
end

local function chunk_at(parsed, ctype, nth)
  local n = 0
  for _, c in ipairs(parsed.chunks) do
    if c.type == ctype then
      n = n + 1
      if n == (nth or 1) then return c end
    end
  end
end

local function fctl_fields(cdata)
  local seq, w, h, x, y, dn, dd, dis, blend =
    string.unpack(">I4I4I4I4I4I2I2BB", cdata)
  return { seq = seq, w = w, h = h, x = x, y = y,
           delay_num = dn, delay_den = dd, dispose = dis, blend = blend }
end

-- crc32 ----------------------------------------------------------
eq(apng.crc32("IEND"), 0xAE426082, "crc32: known IEND value")

-- duration_to_delay ----------------------------------------------
local n, d = apng.duration_to_delay(0.1)
eq(n, 100, "duration 0.1s -> delay_num")
eq(d, 1000, "duration 0.1s -> delay_den")
n = apng.duration_to_delay(0.033)
eq(n, 33, "duration 0.033s -> 33ms rounding")
n = apng.duration_to_delay(0.0004)
eq(n, 1, "sub-ms duration clamps to 1")
n = apng.duration_to_delay(0)
eq(n, 1, "zero duration clamps to 1")
n = apng.duration_to_delay(100)
eq(n, 65535, "huge duration clamps to u16 max")
n = apng.duration_to_delay(nil)
eq(n, 100, "nil duration defaults to 100ms")

-- parse_png --------------------------------------------------------
local png_red = pnggen.rgba(4, 3, { 255, 0, 0, 255 })
local p = apng.parse_png(png_red)
check(p ~= nil, "parse_png: valid PNG parses")
eq(chunk_types(p), "IHDR,IDAT,IEND", "parse_png: chunk order")
eq(#p.ihdr, 13, "parse_png: IHDR length")
local w, h, bd, ct = string.unpack(">I4I4BB", p.ihdr)
eq(w, 4, "parse_png: width")
eq(h, 3, "parse_png: height")
eq(bd, 8, "parse_png: bit depth")
eq(ct, 6, "parse_png: color type")
eq(#p.idat, 1, "parse_png: one IDAT payload")
eq(pnggen.unstore(p.idat[1]), ("\0" .. string.rep("\255\0\0\255", 4)):rep(3),
   "parse_png: IDAT decodes to generated pixels")

local p2, err = apng.parse_png("not a png")
eq(p2, nil, "parse_png: rejects non-PNG")
check(err:find("not a PNG"), "parse_png: non-PNG error message")

local bad_crc = png_red:sub(1, #png_red - 8) .. "\0\0\0\0" .. png_red:sub(#png_red - 3)
p2, err = apng.parse_png(bad_crc)
eq(p2, nil, "parse_png: rejects bad CRC")
check(err:find("CRC"), "parse_png: CRC error message")

p2 = apng.parse_png(png_red:sub(1, #png_red - 10))
eq(p2, nil, "parse_png: rejects truncated PNG")

p2, err = apng.parse_png("\137PNG\r\n\026\n")
eq(p2, nil, "parse_png: signature-only input returns error")
check(err:find("IEND"), "parse_png: signature-only error message")

-- assemble ---------------------------------------------------------
local png_green = pnggen.rgba(4, 3, { 0, 255, 0, 255 })
local png_blue = pnggen.rgba(4, 3, { 0, 0, 255, 255 })

local apng_bin = assert(apng.assemble({
  { png = png_red,   duration = 0.1  },
  { png = png_green, duration = 0.05 },
  { png = png_blue,  duration = 0.25 },
}))
local a = assert(apng.parse_png(apng_bin))

eq(chunk_types(a), "IHDR,acTL,fcTL,IDAT,fcTL,fdAT,fcTL,fdAT,IEND",
   "assemble: chunk sequence")

local nf, np = string.unpack(">I4I4", chunk_at(a, "acTL").data)
eq(nf, 3, "assemble: acTL num_frames")
eq(np, 0, "assemble: acTL num_plays = infinite")

local f1 = fctl_fields(chunk_at(a, "fcTL", 1).data)
eq(f1.seq, 0, "assemble: fcTL1 sequence number")
eq(f1.w, 4, "assemble: fcTL1 width")
eq(f1.h, 3, "assemble: fcTL1 height")
eq(f1.x, 0, "assemble: fcTL1 x_offset")
eq(f1.y, 0, "assemble: fcTL1 y_offset")
eq(f1.delay_num, 100, "assemble: fcTL1 delay_num")
eq(f1.delay_den, 1000, "assemble: fcTL1 delay_den")
eq(f1.dispose, 0, "assemble: fcTL1 dispose_op = NONE")
eq(f1.blend, 0, "assemble: fcTL1 blend_op = SOURCE")

local f2 = fctl_fields(chunk_at(a, "fcTL", 2).data)
eq(f2.seq, 1, "assemble: fcTL2 sequence number")
eq(f2.delay_num, 50, "assemble: fcTL2 delay_num")

local f3 = fctl_fields(chunk_at(a, "fcTL", 3).data)
eq(f3.seq, 3, "assemble: fcTL3 sequence number")
eq(f3.delay_num, 250, "assemble: fcTL3 delay_num")

eq(chunk_at(a, "IDAT").data, apng.parse_png(png_red).idat[1],
   "assemble: IDAT payload preserved")

local fd2 = chunk_at(a, "fdAT", 1).data
local fseq2 = string.unpack(">I4", fd2)
eq(fseq2, 2, "assemble: fdAT1 sequence number")
eq(fd2:sub(5), apng.parse_png(png_green).idat[1],
   "assemble: fdAT1 payload = frame2 IDAT")

local fd3 = chunk_at(a, "fdAT", 2).data
eq(string.unpack(">I4", fd3), 4, "assemble: fdAT2 sequence number")
eq(fd3:sub(5), apng.parse_png(png_blue).idat[1],
   "assemble: fdAT2 payload = frame3 IDAT")

-- 全出力チャンクの CRC は parse_png が検証済み（CRC不一致なら失敗する）

-- 補助チャンク（PLTE/tRNS）の引き継ぎ -----------------------------
local png_idx = pnggen.indexed(2, 2, { { 255, 0, 0 }, { 0, 255, 0 } }, 1)
local apng_idx = assert(apng.assemble({ { png = png_idx, duration = 0.2 } }))
eq(chunk_types(assert(apng.parse_png(apng_idx))),
   "IHDR,acTL,PLTE,tRNS,fcTL,IDAT,IEND",
   "assemble: ancillary chunks preserved before fcTL")

-- 単一フレーム ----------------------------------------------------
local single = assert(apng.assemble({ { png = png_red, duration = 0.5 } }))
local sp = assert(apng.parse_png(single))
eq(chunk_types(sp), "IHDR,acTL,fcTL,IDAT,IEND", "assemble: single frame structure")
eq(string.unpack(">I4", chunk_at(sp, "acTL").data), 1, "assemble: single num_frames")

-- エラーケース ----------------------------------------------------
local r, e = apng.assemble({})
eq(r, nil, "assemble: rejects empty frames")
check(e:find("no frames"), "assemble: empty frames message")

local png_big = pnggen.rgba(5, 3, { 0, 0, 0, 255 })
r, e = apng.assemble({ { png = png_red }, { png = png_big } })
eq(r, nil, "assemble: rejects IHDR mismatch")
check(e:find("IHDR"), "assemble: IHDR mismatch message")

r = apng.assemble({ { png = "garbage" } })
eq(r, nil, "assemble: rejects non-PNG frame")

local png_idx_alt = pnggen.indexed(2, 2, { { 0, 0, 255 }, { 0, 255, 0 } }, 1)
r, e = apng.assemble({ { png = png_idx }, { png = png_idx_alt } })
eq(r, nil, "assemble: rejects palette mismatch")
check(e and e:find("palette"), "assemble: palette mismatch message")

r = apng.assemble("not a table")
eq(r, nil, "assemble: rejects non-table input")

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
