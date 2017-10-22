local cjson = require 'cjson'
local pl = require 'pl.import_into'()
local utils = require 'fbcode.deeplearning.experimental.yuandong.utils.utils'

-- Save everything as a dictionary
local opt = pl.lapp[[
   -i,--input         (default "")  Input t7 file
   -o,--output        (default "")  Output json file
]]

-- print("Input file = " .. opt.input)
-- print("Output file = " .. opt.output)

t = utils.convert_to_table(torch.load(opt.input))
if debug then print("encoding json") end 
s = cjson.encode(t)
-- s = pl.pretty.write(t)
f = assert(io.open(opt.output, "w"))
f:write(s)
-- save_to_json(t, f)
f:close()
