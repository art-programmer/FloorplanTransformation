-- Load all common packages.
require 'nn'
require 'cunn'
require 'cudnn'
require 'fbnn'
require 'fbcunn'

local nnutils = require 'fbcode.deeplearning.experimental.yuandong.utils.nnutils'
local pl = require 'pl.import_into'()

local opt = pl.lapp[[
   -i,--input         (default "")  Input model
   -o,--output        (default "")  Output model 
]]

local saved_check_point = torch.load(opt.input)

local model
if type(saved_check_point) == 'table' then 
    saved_check_point.model = nnutils.remove_batchnorm(saved_check_point.model)
else
    saved_check_point = nnutils.remove_batchnorm(saved_check_point)
end

torch.save(opt.output, saved_check_point)
