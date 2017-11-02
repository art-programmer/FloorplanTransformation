local nn = require 'nn'
--require 'cunn'
--require 'loadcaffe'
--require 'nngraph'
--require 'models/models'

local function createModel(opt)

   if opt.loadModel ~= '' then
      local model = torch.load(opt.loadModel)
      model:cuda()
      print(model)      
      return model
   end
   
   if opt.loadPoseEstimationModel ~= '' then
      local nOutput = 51 --This is slightly more than our final number of output channels. The actually used number of channels is 13 (wall corner) + 4 (opening corner) + 4 (icon corner) + 10 (opening/icon/empty segmentation) + 11 (wall/room segmentation)
      
      local model = torch.load(opt.loadPoseEstimationModel).modules[3].modules[1]

      --Change input layer since the original model takes 19 input channels
      local weight = model.modules[1].weight:clone()
      local conv_input = nn.SpatialConvolution(3, 64, 7, 7, 2, 2, 3, 3)
      conv_input.weight = weight:narrow(2, 1, 3):contiguous()
      model.modules[1] = conv_input
      
      --Append output branches
      model.modules[16] = nil
      model:add(nn.SpatialConvolution(256, nOutput, 1, 1))
      model:add(nn.SpatialFullConvolution(nOutput, nOutput, 4, 4, 4, 4))

      local cornerHeatmapBranch = nn.Sequential():add(nn.Narrow(2, 1, 21)):add(nn.Sigmoid()):add(nn.MulConstant(10))
      local segmentationBranch_1 = nn.Sequential():add(nn.Narrow(2, 22, 13)):add(nn.Transpose({2, 3}, {3, 4})):add(nn.View(-1, 13))
      local segmentationBranch_2 = nn.Sequential():add(nn.Narrow(2, 34, 17)):add(nn.Transpose({2, 3}, {3, 4})):add(nn.View(-1, 17))
      local outputBranches = nn.ConcatTable():add(cornerHeatmapBranch):add(segmentationBranch_1):add(segmentationBranch_2)
      model:add(outputBranches)

      model:cuda()   
      print(model)
      return model
   end
   
   assert(false, 'Please specify either opt.loadPoseEstimationModel or opt.loadModel')
end

return createModel
