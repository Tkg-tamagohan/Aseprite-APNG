-- main.lua スタンドアロンテスト（Aseprite API をモック化して onsave を検証）
-- 実行: リポジトリルートで `lua5.3 tests/test_main.lua`

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

-- モック状態 --------------------------------------------------------------
local st
local function reset_state()
  st = {
    draw_order = {},      -- drawSprite に渡されたフレーム番号の列
    saved_paths = {},     -- saveAs が書き出した一時ファイルパスの列
    save_palettes = {},   -- saveAs に渡されたパレットの列
    frame_colors = {},    -- フレーム番号 -> RGBA 色
    frame_sizes = {},     -- フレーム番号 -> {w, h}（異常系用）
    registered = {},      -- newFileFormat に渡された定義
  }
end

ColorMode = { RGB = 0, GRAYSCALE = 1, INDEXED = 2 }
FormatSupport = {
  RGB = 0x0004, RGBA = 0x0008, GRAY = 0x0010, GRAYA = 0x0020,
  INDEXED = 0x0040, LAYER = 0x0080, FRAME = 0x0100,
  PALETTE = 0x2200, PALETTE_ALPHA = 0x4000,
}

local TMPBASE = os.getenv("TMPDIR") or "/tmp"

local function fake_palette(frame_number, plte)
  return { frameNumber = frame_number, plte = plte }
end

local function fake_sprite(opts)
  opts = opts or {}
  local frames = {}
  for i, d in ipairs(opts.durations or { 0.1 }) do
    frames[i] = { duration = d }
  end
  return {
    width = opts.width or 4,
    height = opts.height or 3,
    colorMode = opts.colorMode or ColorMode.RGB,
    frames = frames,
    palettes = opts.palettes or {},
  }
end

-- Image モック: drawSprite でフレーム番号を記録し、saveAs で実際に PNG を書き出す
Image = function(w, h, colorMode)
  local img = { width = w, height = h, colorMode = colorMode, _frame = nil }
  function img:drawSprite(sprite, frame_number)
    assert(type(sprite) == "table" and sprite.frames ~= nil,
           "drawSprite: invalid sprite")
    self._frame = frame_number
    st.draw_order[#st.draw_order + 1] = frame_number
  end
  function img:saveAs(arg)
    local fn, palette
    if type(arg) == "table" then
      fn, palette = arg.filename, arg.palette
    else
      fn = arg
    end
    st.saved_paths[#st.saved_paths + 1] = fn
    st.save_palettes[#st.save_palettes + 1] = palette
    local size = st.frame_sizes[self._frame]
    local pw, ph = w, h
    if size then pw, ph = size[1], size[2] end
    local png
    if self.colorMode == ColorMode.INDEXED then
      assert(palette, "indexed saveAs requires palette")
      png = pnggen.indexed(pw, ph, palette.plte, 1)
    else
      png = pnggen.rgba(pw, ph, st.frame_colors[self._frame])
    end
    local fh = assert(io.open(fn, "wb"))
    fh:write(png)
    fh:close()
    return true
  end
  return img
end

app = {
  isUIAvailable = false,
  sprite = nil,
  fs = {
    tempPath = TMPBASE,
    joinPath = function(a, b) return a .. "/" .. b end,
    makeAllDirectories = function(p)
      return os.execute(string.format("mkdir -p '%s'", p)) == true
    end,
    removeDirectory = function(p)
      return os.execute(string.format("rmdir '%s'", p)) == true
    end,
  },
}

local function fake_plugin()
  return {
    newFileFormat = function(_, def)
      st.registered[#st.registered + 1] = def
    end,
  }
end

dofile("main.lua")

local OUT = TMPBASE .. "/aseprite-apng-test-out.apng"

local function run_onsave(ev)
  local def = assert(st.registered[1], "format not registered")
  local fh = assert(io.open(OUT, "wb"))
  ev.file = fh
  ev.filename = OUT
  local ok, err = pcall(def.onsave, ev)
  fh:close()
  local rf = io.open(OUT, "rb")
  local bin = rf and rf:read("*a") or ""
  if rf then rf:close() end
  os.remove(OUT)
  return ok, err, bin
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

local function delay_nums(parsed)
  local t = {}
  for _, c in ipairs(parsed.chunks) do
    if c.type == "fcTL" then
      t[#t + 1] = select(6, string.unpack(">I4I4I4I4I4I2I2BB", c.data))
    end
  end
  return table.concat(t, ",")
end

-- REG-01: 形式登録 -------------------------------------------------------
reset_state()
init(fake_plugin())
local def = st.registered[1]
check(def ~= nil, "REG-01: file format registered")
eq(def.name, "apng", "REG-01: format name")
eq(table.concat(def.extensions, ","), "apng", "REG-01: extension")
eq(type(def.onsave), "function", "REG-01: onsave is a function")
check(def.onload == nil, "REG-01: onload not provided (save only)")
check((def.supports & FormatSupport.FRAME) ~= 0, "REG-01: FRAME supported")
check((def.supports & FormatSupport.RGBA) ~= 0, "REG-01: RGBA supported")
check((def.supports & FormatSupport.INDEXED) ~= 0, "REG-01: INDEXED supported")

-- REG-02: newFileFormat が無い環境（v1.3.18 未満）では登録しない ----------
reset_state()
init({})
eq(#st.registered, 0, "REG-02: no registration without newFileFormat")

-- MAIN-01: 複数フレーム RGB スプライトの APNG 化 ---------------------------
reset_state()
init(fake_plugin())
local sprite = fake_sprite{ durations = { 0.1, 0.05, 0.25 } }
st.frame_colors = { { 255, 0, 0, 255 }, { 0, 255, 0, 255 }, { 0, 0, 255, 255 } }
local ok, err, bin = run_onsave{ sprite = sprite }
check(ok, "MAIN-01: onsave succeeds (" .. tostring(err) .. ")")
local a = apng.parse_png(bin)
check(a ~= nil, "MAIN-01: output is a valid APNG")
eq(chunk_types(a), "IHDR,acTL,fcTL,IDAT,fcTL,fdAT,fcTL,fdAT,IEND",
   "MAIN-01: chunk sequence")
eq(string.unpack(">I4I4", chunk_at(a, "acTL").data), 3, "MAIN-01: num_frames")
eq(delay_nums(a), "100,50,250", "MAIN-01: Frame.duration -> delay_num")
eq(table.concat(st.draw_order, ","), "1,2,3", "MAIN-01: drawSprite order")
eq(#st.saved_paths, 3, "MAIN-01: temp PNG per frame")

-- MAIN-02: 一時ファイルが削除される ----------------------------------------
for _, p in ipairs(st.saved_paths) do
  check(io.open(p, "rb") == nil, "MAIN-02: temp file removed: " .. p)
end
do
  local dir = st.saved_paths[1] and st.saved_paths[1]:match("^(.*)/[^/]+$")
  check(dir ~= nil and os.execute(string.format("test ! -d '%s'", dir)),
        "MAIN-02: temp directory removed")
end

-- MAIN-03: 単一フレームでも有効な APNG を書き出す --------------------------
reset_state()
init(fake_plugin())
local ok, err, bin = run_onsave{ sprite = fake_sprite{ durations = { 0.5 } } }
check(ok, "MAIN-03: single frame succeeds (" .. tostring(err) .. ")")
local sp = apng.parse_png(bin)
eq(chunk_types(sp), "IHDR,acTL,fcTL,IDAT,IEND", "MAIN-03: chunk sequence")
eq(string.unpack(">I4", chunk_at(sp, "acTL").data), 1, "MAIN-03: num_frames = 1")

-- MAIN-04: インデックススプライトは対応パレットを saveAs へ渡す --------------
reset_state()
init(fake_plugin())
local plte = { { 255, 0, 0 }, { 0, 255, 0 } }
local pal = fake_palette(1, plte)
sprite = fake_sprite{ colorMode = ColorMode.INDEXED, palettes = { pal },
                      durations = { 0.2, 0.2 } }
local ok, err, bin = run_onsave{ sprite = sprite }
check(ok, "MAIN-04: indexed sprite succeeds (" .. tostring(err) .. ")")
eq(st.save_palettes[1], pal, "MAIN-04: palette passed to saveAs")
eq(st.save_palettes[2], pal, "MAIN-04: same palette for frame 2")
check(chunk_at(assert(apng.parse_png(bin)), "PLTE") ~= nil,
      "MAIN-04: PLTE carried into APNG")

-- MAIN-05: 複数パレットではフレーム番号に応じたパレットを選択する -------------
reset_state()
init(fake_plugin())
local pal1 = fake_palette(1, plte)
local pal2 = fake_palette(2, plte) -- 同色の別パレット（組立は成功する想定）
sprite = fake_sprite{ colorMode = ColorMode.INDEXED,
                      palettes = { pal1, pal2 },
                      durations = { 0.1, 0.1, 0.1 } }
local ok, err = run_onsave{ sprite = sprite }
check(ok, "MAIN-05: multi-palette save succeeds (" .. tostring(err) .. ")")
eq(st.save_palettes[1], pal1, "MAIN-05: frame 1 uses palette 1")
eq(st.save_palettes[2], pal2, "MAIN-05: frame 2 uses palette 2")
eq(st.save_palettes[3], pal2, "MAIN-05: frame 3 keeps palette 2")

-- MAIN-06: パレットがフレーム間で実際に異なる場合はエラー --------------------
reset_state()
init(fake_plugin())
local pal_diff = fake_palette(2, { { 0, 0, 255 }, { 0, 255, 0 } })
sprite = fake_sprite{ colorMode = ColorMode.INDEXED,
                      palettes = { pal1, pal_diff },
                      durations = { 0.1, 0.1 } }
local ok, err, bin = run_onsave{ sprite = sprite }
eq(ok, false, "MAIN-06: palette change rejected")
check(err and err:find("palette"), "MAIN-06: palette mismatch message")
eq(bin, "", "MAIN-06: nothing written on failure")

-- MAIN-07: ev.sprite が無い場合は app.sprite を使う --------------------------
reset_state()
init(fake_plugin())
app.sprite = fake_sprite{ durations = { 0.1 } }
local ok = run_onsave{ sprite = nil }
check(ok, "MAIN-07: falls back to app.sprite")
app.sprite = nil

-- ERR-01: スプライトが無い -------------------------------------------------
reset_state()
init(fake_plugin())
local ok, err, bin = run_onsave{ sprite = nil }
eq(ok, false, "ERR-01: no sprite rejected")
check(err and err:find("no sprite"), "ERR-01: error message")
eq(bin, "", "ERR-01: nothing written")

-- ERR-02: フレーム 0 件 -----------------------------------------------------
reset_state()
init(fake_plugin())
local ok, err = run_onsave{ sprite = fake_sprite{ durations = {} } }
eq(ok, false, "ERR-02: empty frames rejected")
check(err and err:find("no frames"), "ERR-02: error message")

-- ERR-03: キャンバスサイズ 0 --------------------------------------------------
reset_state()
init(fake_plugin())
local ok, err = run_onsave{ sprite = fake_sprite{ width = 0 } }
eq(ok, false, "ERR-03: empty canvas rejected")
check(err and err:find("canvas"), "ERR-03: error message")

-- ERR-04: 出力ハンドルが無い --------------------------------------------------
reset_state()
init(fake_plugin())
local def2 = st.registered[1]
local ok, err = pcall(def2.onsave, { filename = OUT,
                                   sprite = fake_sprite{} })
eq(ok, false, "ERR-04: missing file handle rejected")
check(err and err:find("file handle"), "ERR-04: error message")

-- ERR-05: フレーム間の IHDR 不一致 -------------------------------------------
reset_state()
init(fake_plugin())
st.frame_sizes[2] = { 5, 3 }
local ok, err, bin = run_onsave{
  sprite = fake_sprite{ durations = { 0.1, 0.1 } },
}
eq(ok, false, "ERR-05: IHDR mismatch rejected")
check(err and err:find("IHDR"), "ERR-05: error message")
eq(bin, "", "ERR-05: nothing written on failure")
for _, p in ipairs(st.saved_paths) do
  check(io.open(p, "rb") == nil, "ERR-05: temp file removed after error")
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
