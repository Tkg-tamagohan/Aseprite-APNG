-- Aseprite-APNG 拡張エントリ
-- plugin:newFileFormat で .apng 形式を登録し、onsave で全フレームの
-- 合成画像を apng モジュールへ渡して APNG を書き出す。
-- Aseprite API への依存はこのファイルに閉じ込める。
--
-- 注意: require("apng") はスクリプト評価時（_PLUGIN 設定中）にのみ
-- 拡張ディレクトリから解決されるため、トップレベルで行う必要がある。

local apng = require("apng")

local REQUIRED_VERSION = "v1.3.18"

-- フレーム番号に適用されるパレットを返す。
-- palettes[i].frameNumber はそのパレットが最初に適用されるフレーム番号（1始まり）。
local function palette_at_frame(sprite, frame_number)
  local palette = nil
  for _, p in ipairs(sprite.palettes) do
    if p.frameNumber > frame_number then
      break
    end
    palette = p
  end
  return palette
end

local temp_seq = 0

-- 一時 PNG の出力先ディレクトリを一意に作成して返す。
local function new_temp_dir()
  temp_seq = temp_seq + 1
  local dir = app.fs.joinPath(
    app.fs.tempPath,
    string.format("aseprite-apng-%x-%x-%x", os.time(), temp_seq,
                  math.random(0x7FFFFFFF)))
  if not app.fs.makeAllDirectories(dir) then
    error("cannot create temporary directory: " .. dir, 0)
  end
  return dir
end

local function remove_temp(dir, files)
  for _, f in ipairs(files) do
    local ok, removed = pcall(os.remove, f)
    if not ok or not removed then
      print("Aseprite-APNG: could not remove temp file " .. f)
    end
  end
  local ok, removed = pcall(app.fs.removeDirectory, dir)
  if not ok or removed == false then
    print("Aseprite-APNG: could not remove temp directory " .. dir)
  end
end

-- フレームを全レイヤー合成のキャンバス全面画像として一時 PNG に書き出し、
-- そのバイト列を返す。
local function render_frame_png(sprite, frame_number, path)
  -- sprite.spec を引き継ぐことでインデックス画像の透明色インデックスも
  -- 新規 Image 側の spec.transparentColor と一致する（0 以外の透明色に対応）。
  local image = Image(sprite.spec)
  image:drawSprite(sprite, frame_number)
  if sprite.colorMode == ColorMode.INDEXED then
    -- インデックス画像の保存には対応パレットの指定が必須
    image:saveAs{ filename = path, palette = palette_at_frame(sprite, frame_number) }
  else
    image:saveAs(path)
  end
  local fh = assert(io.open(path, "rb"))
  local png = fh:read("*a")
  fh:close()
  return png
end

local function save_apng(ev)
  if not ev or not ev.file then
    error("no output file handle", 0)
  end
  local sprite = ev.sprite or app.sprite
  if not sprite then
    error("no sprite to save", 0)
  end
  if #sprite.frames == 0 then
    error("sprite has no frames", 0)
  end
  if sprite.width <= 0 or sprite.height <= 0 then
    error("sprite canvas is empty", 0)
  end

  -- 全フレームを一時 PNG に書き出してから APNG を組み立てる。
  -- 一時ファイルは成否に関わらず削除する。
  local dir = new_temp_dir()
  local tmp_files, frames = {}, {}
  local ok, err = pcall(function()
    for i = 1, #sprite.frames do
      local tmp = app.fs.joinPath(dir, string.format("f%04d.png", i))
      tmp_files[#tmp_files + 1] = tmp
      frames[#frames + 1] = {
        png = render_frame_png(sprite, i, tmp),
        duration = sprite.frames[i].duration,
      }
    end
  end)
  remove_temp(dir, tmp_files)
  if not ok then
    error(err, 0)
  end

  local bin, aerr = apng.assemble(frames)
  if not bin then
    error(tostring(aerr), 0)
  end
  assert(ev.file:write(bin))
  return true
end

function init(plugin)
  -- newFileFormat API（aseprite/aseprite PR #5174）は Aseprite v1.3.18
  -- 以降で利用できる。未対応のバージョンでは登録せず警告だけ出す。
  if not plugin.newFileFormat then
    local msg = "Aseprite-APNG requires Aseprite " .. REQUIRED_VERSION ..
      " or later (plugin:newFileFormat is unavailable)"
    print(msg)
    if app.isUIAvailable then
      pcall(app.alert, msg)
    end
    return
  end
  plugin:newFileFormat{
    name = "apng",
    -- APNG は全カラーモード・フレームアニメーション・パレット透過を扱える
    supports = FormatSupport.RGB | FormatSupport.RGBA |
               FormatSupport.GRAY | FormatSupport.GRAYA |
               FormatSupport.INDEXED | FormatSupport.FRAME |
               FormatSupport.PALETTE_ALPHA,
    extensions = { "apng" },
    onsave = save_apng,
  }
end
