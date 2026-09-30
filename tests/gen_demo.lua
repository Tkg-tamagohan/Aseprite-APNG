-- 検証用 APNG デモ生成スクリプト
-- 実行: リポジトリルートで `lua5.3 tests/gen_demo.lua <出力パス>`
-- 色の異なる複数フレーム（フレーム時間も異なる）の APNG を書き出す。

package.path = "./?.lua;./tests/?.lua;" .. package.path

local apng = require("apng")
local pnggen = require("pnggen")

local out_path = arg[1] or "demo.apng"

local frames = {
  { png = pnggen.rgba(64, 64, { 255, 0, 0, 255 }),   duration = 0.5  },
  { png = pnggen.rgba(64, 64, { 0, 255, 0, 255 }),   duration = 0.25 },
  { png = pnggen.rgba(64, 64, { 0, 0, 255, 255 }),   duration = 0.5  },
  { png = pnggen.rgba(64, 64, { 255, 255, 0, 255 }), duration = 1.0  },
}

local bin = assert(apng.assemble(frames))
local f = assert(io.open(out_path, "wb"))
f:write(bin)
f:close()
print("wrote " .. out_path .. " (" .. #bin .. " bytes)")
