local nn = require 'nn'
require 'cunn'
require 'cudnn'

local function createCriterion(opt)
   local criterion = nn.ParallelCriterion()
   criterion:add(nn.MSECriterion(), 20)
   criterion:add(nn.CrossEntropyCriterion())
   criterion:add(nn.CrossEntropyCriterion())
   criterion:cuda()
   return criterion
end

return createCriterion
