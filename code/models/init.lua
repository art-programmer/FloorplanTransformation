require 'nn'
require 'cunn'
require 'cudnn'
require 'dpnn'
require 'nnx'
local inn = require 'inn'
if not nn.SpatialConstDiagonal then
   torch.class('nn.SpatialConstDiagonal', 'inn.ConstAffine')
end
--local utils = paths.dofile('modelUtils.lua')
--require 'models/DeepMask'

local M = {}

function M.setup(opt, checkpoint)
   local model
   if checkpoint then
      local modelPath = paths.concat(opt.resume, checkpoint.modelFile)
      assert(paths.filep(modelPath), 'Saved model not found: ' .. modelPath)
      print('=> Resuming model from ' .. modelPath)
      model = torch.load(modelPath)
   elseif opt.retrain ~= 'none' then
      assert(paths.filep(opt.retrain), 'File not found: ' .. opt.retrain)
      print('Loading model from file: ' .. opt.retrain)
      model = torch.load(opt.retrain)
   else
      local modelFileName = 'models/' .. opt.netType
      print('=> Creating model from file: ' .. modelFileName .. '.lua')
      model = require(modelFileName)(opt)
   end
   
   cudnn.convert(model, cudnn)

   
   local criterionFileName = 'models/' .. opt.criterionType
   criterionFileName = criterionFileName .. '-criterion'
   local criterion
   local f = io.open(criterionFileName .. '.lua', "r")
   if f ~= nil then
      io.close(f)
      criterion = require(criterionFileName)(opt)
   end
   
   return model, criterion
end

return M
