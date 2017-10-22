require 'torch'
require 'image'
require 'paths'
require 'nn'
require 'inn'
require 'image'
require 'xlua'

require 'cudnn'
require 'loadcaffe'
local gp = require 'gpath'

local nn_utils = {}

nn_utils.mean = torch.Tensor({129.67, 114.43, 107.26})
nn_utils.nmean = nn_utils.mean:clone():div(255)

-------------------------------------------------------------------

-- generate an image of a particular size with values scaled in [0, 1] and 
-- then mean substracted
function nn_utils.normalize(im, width, height, nmean)
  nmean = nmean or nn_utils.nmean 
  assert((#im)[1] == (#nmean)[1])

  -- scale the image
  local normalized = image.scale(im, width, height)

  -- normalize it to [0, 1]
  if normalized:max() > 1 then
    normalized:div(255)
  end

  -- mean subtraction
  for i = 1, (#nmean)[1] do
    normalized[i]:csub(nmean[i])
  end

  return normalized
end

-- add mean value back
function nn_utils.unnormalize(im, nmean)
  nmean = nmean or nn_utils.nmean 
  assert((#im)[1] == (#nmean)[1])

  local unnorm = im:clone()
  for i = 1, (#nmean)[1] do
    unnorm[i]:add(nmean[i])
  end

  return unnorm
end

function nn_utils.loadNormalizeIm(imName, numChn, width, height)
  numChn = numChn or 3

  local im = image.load(imName)
  if im:size(1) == 1 and numChn == 3 then
    im = torch.repeatTensor(im, 3, 1, 1)
  end

  -- normalize image 
  im = nn_utils.normalize(im, width, height, mean)
  return im
end

function nn_utils.toCaffeInput(input, fullScale, swapChn, width, height, mean)
  assert(input:dim() == 4 and input:size(2) == 3 or 
  input:dim() == 3 and input:size(1) == 3)
  fullScale = fullScale or true
  swapChn = swapChn or true
  width = width or 227
  height = height or 227
  mean = mean or nn_utils.mean

  if input:dim() == 4 then
    local bs = input:size(1)
    local ch = input:size(2)
    local ht = input:size(3)
    local wd = input:size(4)
    input = image.scale(input:view(bs * ch, ht, wd), 
    width, height):view(bs, ch, height, width)
  else
    local ch = input:size(1)
    local ht = input:size(2)
    local wd = input:size(3)
    input = image.scale(input, width, height)
  end

  local maxV = input:max()
  local minV = input:min()
  if fullScale then
    if math.abs(maxV) <= 1 and math.abs(minV) <= 1 then
      input:mul(255)
    end
    if maxV >= 0.5 and minV >= 0 then
      if input:dim() == 4 then
        for i = 1, 3 do 
          input[{{}, i, {}, {}}]:csub(mean[i])
        end
      else
        for i = 1, 3 do 
          input[{i, {}, {}}]:csub(mean[i])
        end
      end
    end
  else
    if math.abs(maxV) > 1 or math.abs(minV) > 1 then
      input:div(255)
    end
    if maxV >= 0.5 and minV >= 0 then
      if input:dim() == 4 then
        for i = 1, 3 do 
          input[{{}, i, {}, {}}]:csub(mean[i]/255)
        end
      else
        for i = 1, 3 do 
          input[{i, {}, {}}]:csub(mean[i]/255)
        end
      end
    end
  end

  if swapChn then
    if input:dim() == 4 then
      local tmp = input[{{}, 1, {}, {}}]:clone()
      input[{{}, 1, {}, {}}] = input[{{}, 3, {}, {}}]
      input[{{}, 3, {}, {}}] = tmp
    else
      local tmp = input[{1, {}, {}}]:clone()
      input[{1, {}, {}}] = input[{3, {}, {}}]
      input[{3, {}, {}}] = tmp
    end
  end

  return input
end

-----------------------------------------------------------------------------
--
function nn_utils.loadLeNet(net)
  net = net or 'cudnn' 
  local modelPath = paths.concat(gp.caffe_model, 'lenet')
  return loadcaffe.load(paths.concat(modelPath, 'lenet.prototxt'), 
    paths.concat(modelPath, 'lenet_iter_10000.caffemodel'), net)
end

function nn_utils.loadAlexNet(net)
  net = net or 'cudnn' 
  local modelPath = paths.concat(gp.caffe_model, 'bvlc_alexnet')
  return loadcaffe.load(paths.concat(modelPath, 'deploy.prototxt'), 
    paths.concat(modelPath, 'bvlc_alexnet.caffemodel'), net)
end

-- not working
function nn_utils.loadPlacesAlexNet(net)
  print('Warning: loadFasterRCNNZF is not working')
  local net = net or 'cudnn' 
  local modelPath = paths.concat(gp.caffe_model, 'places205_alexnet')
  return loadcaffe.load(paths.concat(modelPath, 'places205CNN_deploy_torch.prototxt'), 
    paths.concat(modelPath, 'places205CNN_iter_300000.caffemodel'), net)
end

-- not working
function nn_utils.loadHybridAlexNet(net)
  print('Warning: loadFasterRCNNZF is not working')
  local net = net or 'cudnn' 
  local modelPath = paths.concat(gp.caffe_model, 'hybrid_alexnet')
  return loadcaffe.load(paths.concat(modelPath, 'hybridCNN_deploy.prototxt'), 
    paths.concat(modelPath, 'hybridCNN_iter_700000.caffemodel'), net)
end

function nn_utils.loadCaffeNet(net)
  local net = net or 'cudnn' 
  local modelPath = paths.concat(gp.caffe_model, 'bvlc_reference_caffenet')
  return loadcaffe.load(paths.concat(modelPath, 'deploy.prototxt'), 
    paths.concat(modelPath, 'bvlc_reference_caffenet.caffemodel'), net)
end

function nn_utils.loadVGG16(net)
  local net = net or 'cudnn' 
  local modelPath = paths.concat(gp.caffe_model, 'vgg_16')
  return loadcaffe.load(paths.concat(modelPath, 'VGG_ILSVRC_16_layers_deploy.prototxt'), 
    paths.concat(modelPath, 'VGG_ILSVRC_16_layers.caffemodel'), net)
end

function nn_utils.loadVGG19(net)
  local net = net or 'cudnn' 
  local modelPath = paths.concat(gp.caffe_model, 'vgg_19')
  return loadcaffe.load(paths.concat(modelPath, 'VGG_ILSVRC_19_layers_deploy.prototxt'), 
    paths.concat(modelPath, 'VGG_ILSVRC_19_layers.caffemodel'), net)
end

function nn_utils.loadGoogleNet(net)
  local modelPath = paths.concat(gp.caffe_model, 'googlenet')
  return torch.load(paths.concat(modelPath, 'inceptionv3.net'))
end

function nn_utils.loadResNet18()
  local modelPath = paths.concat(gp.caffe_model, 'resnet_18')
  return torch.load(paths.concat(modelPath, 'resnet-18.t7'))
end

function nn_utils.loadResNet34()
  local modelPath = paths.concat(gp.caffe_model, 'resnet_34')
  return torch.load(paths.concat(modelPath, 'resnet-34.t7'))
end

function nn_utils.loadResNet50()
  local modelPath = paths.concat(gp.caffe_model, 'resnet_50')
  return torch.load(paths.concat(modelPath, 'resnet-50.t7'))
end

function nn_utils.loadResNet101()
  local modelPath = paths.concat(gp.caffe_model, 'resnet_101')
  return torch.load(paths.concat(modelPath, 'resnet-101.t7'))
end

function nn_utils.loadResNet152()
  local modelPath = paths.concat(gp.caffe_model, 'resnet_152')
  return torch.load(paths.concat(modelPath, 'resnet-152.t7'))
end

function nn_utils.loadResNet200()
  local modelPath = paths.concat(gp.caffe_model, 'resnet_200')
  return torch.load(paths.concat(modelPath, 'resnet-200.t7'))
end

function nn_utils.loadRCNN(net)
  local net = net or 'cudnn' 
  local modelPath = paths.concat(gp.caffe_model, 'bvlc_reference_rcnn_ilsvrc13')
  return loadcaffe.load(paths.concat(modelPath, 'deploy.prototxt'), 
    paths.concat(modelPath, 'bvlc_reference_rcnn_ilsvrc13.caffemodel'), net)
end

function nn_utils.loadFastRCNNCaffeNet()
  local modelPath = paths.concat(gp.caffe_model, 'fastrcnn')
  return torch.load(paths.concat(modelPath, 'caffenet_fast_rcnn_iter_40000.t7')):unpack()
end

function nn_utils.loadFastRCNNVGG16()
  local modelPath = paths.concat(gp.caffe_model, 'fastrcnn')
  return torch.load(paths.concat(modelPath, 'vgg16_fast_rcnn_iter_40000.t7')):unpack()
end

function nn_utils.loadFCN32s(net)
  local modelPath = paths.concat(gp.caffe_model, 'fcn_32s_pascal')
  return torch.load(paths.concat(modelPath, 'fcn_32s_pascal.t7'))
end

function nn_utils.loadFCN32sRaw(net)
  local net = net or 'cudnn' 
  local modelPath = paths.concat(gp.caffe_model, 'fcn_32s_pascal')
  return loadcaffe.load(paths.concat(modelPath, 'fcn-32s-pascal-deploy.prototxt'), 
    paths.concat(modelPath, 'fcn-32s-pascal.caffemodel'), net)
end

function nn_utils.loadNIN(net)
  local net = net or 'cudnn' 
  local modelPath = paths.concat(gp.caffe_model, 'nin')
  return loadcaffe.load(paths.concat(modelPath, 'train_val.prototxt'), 
    paths.concat(modelPath, 'nin_imagenet_conv.caffemodel'), net)
end

-- not working
function nn_utils.loadFasterRCNNZF(net)
  print('Warning: loadFasterRCNNZF is not working')
  local net = net or 'cudnn' 
  local modelPath = paths.concat(gp.caffe_model, 'faster_rcnn_VOC0712_ZF')
  return loadcaffe.load(paths.concat(modelPath, 'deploy.prototxt'), 
    paths.concat(modelPath, 'ZF_faster_rcnn_final.caffemodel'), net)
end

-- not working
function nn_utils.loadFasterRCNNVGG(net)
  print('Warning: loadFasterRCNNVGG is not working')
  local net = net or 'cudnn' 
  local modelPath = paths.concat(gp.caffe_model, 'faster_rcnn_VOC0712_vgg_16layers')
  return loadcaffe.load(paths.concat(modelPath, 'deploy.prototxt'), 
    paths.concat(modelPath, 'VGG16_faster_rcnn_final.caffemodel'), net)
end

-- not working
function nn_utils.loadHED(net)
  print('Warning: loadHED is not working')
  local net = net or 'cudnn' 
  local modelPath = paths.concat(gp.caffe_model, 'hed')
  return loadcaffe.load(paths.concat(modelPath, 'hed.prototxt'), 
    paths.concat(modelPath, 'hed_bsds.caffemodel'), net)
end

------------------------------------------------------------------------

function nn_utils.sanitize(net)
  local list = net:listModules()
  for nameL, val in ipairs(list) do
    for name, field in pairs(val) do
      if torch.type(field) == 'cdata' then val[name] = nil end
      if name == 'homeGradBuffers' then val[name] = nil end
      if name == 'input_gpu' then val['input_gpu'] = {} end
      if name == 'gradOutput_gpu' then val['gradOutput_gpu'] = {} end
      if name == 'gradInput_gpu' then val['gradInput_gpu'] = {} end

      --if (name == 'output' or name == 'gradInput' or 
      --    name == 'fgradInput' or name == 'finput' or 
      --    name == 'gradWeight' or name == 'gradBias') then
      if (name == 'output' or name == 'gradInput' or
        name == 'fgradInput' or name == 'finput') then
        if torch.type(field) == 'table' then
          val[name] = {}
        else
          val[name] = field.new()
        end
      end
      if name == 'buffer' or name == 'buffer2' or name == 'normalized'
        or name == 'centered' or name == 'addBuffer' then         
        val[name] = nil
      end
    end
  end

  return net
end

-------------------------------------------------------------------------

function nn_utils.tensorDimsStr (A)
  if torch.isTensor(A) then
    local tmp = A:size(1)
    for iDim = 2,A:nDimension() do
      tmp = tmp .. ' x ' .. A:size(iDim)
    end
    return tmp
  else
    local tmp = 'Length ' .. #A .. ' Table\n'
    for i = 1, #A do
      tmp = tmp .. 'Table[' .. i ..']: ' .. nn_utils.tensorDimsStr(A[i]) .. '\n'
    end
    return tmp
  end
end

-- A multi-concat function.  
-- Replaces the 'concat' in torch, which can't deal with cuda tensors
function nn_utils.concatTensors (tensors, outputDimension)
  local nTensors = table.getn(tensors)

  local sumOutputSizes = 0
  for iTensor = 1,nTensors do
    sumOutputSizes = sumOutputSizes + tensors[iTensor]:size(outputDimension)
  end

  local outputSize = tensors[1]:size()
  outputSize[outputDimension] = sumOutputSizes

  -- We clone and then resize to make sure it's the right kind of tensor.
  -- TODO is there a better way to do this?
  local res = tensors[1]:clone()
  res:resize (outputSize)

  local curOutputOffset = 1
  for iTensor = 1,nTensors do
    local accessor = {}
    for j = 1,outputSize:size() do
      accessor[j] = {}
    end

    local outputDimSize = tensors[iTensor]:size(outputDimension)
    accessor[outputDimension] = {curOutputOffset, curOutputOffset + outputDimSize - 1}
    res[accessor]:copy(tensors[iTensor])
    curOutputOffset = curOutputOffset + outputDimSize
  end

  return res
end

function nn_utils.dumpNetwork (layer, inputData, prefix)
  prefix = prefix or ''
  local prefixExtension = "    "
  local output
  local strLayer = tostring(layer)
  if (strLayer:sub(1,13) == 'nn.Sequential') then
    local nLayers = layer:size()
    print (prefix .. 'Layer type: nn.Sequential (' .. nLayers .. ')')
    print (prefix .. 'Input: ' .. nn_utils.tensorDimsStr(inputData))
    local layerInput = inputData
    for iLayer = 1,nLayers do
      print (prefix .. 'Sequential layer ' .. iLayer)
      local curLayer = layer:get(iLayer)
      local res = nn_utils.dumpNetwork (curLayer, layerInput, prefix .. prefixExtension)
      layerInput = res
    end

    output = layerInput
  elseif (strLayer:sub(1,16) ~= "nn.ParallelTable" and strLayer:sub(1,11) == "nn.Parallel") then
    local nLayers = table.getn(layer.modules)
    print (prefix .. 'Layer type: nn.Parallel (' .. nLayers .. ')')
    local inputDimension = layer.inputDimension
    local outputDimension = layer.outputDimension
    print (prefix .. 'Split on ' .. inputDimension)
    print (prefix .. 'Input: ' .. nn_utils.tensorDimsStr(inputData))

    local layerRes = {}
    local sumOutputSizes = 0
    for iLayer = 1,nLayers do
      print (prefix .. 'Parallel layer ' .. iLayer)
      local curLayer = layer:get(iLayer)
      local curInput = inputData:select(inputDimension, iLayer)
      local res = nn_utils.dumpNetwork (curLayer, curInput, prefix .. prefixExtension)
      layerRes[iLayer] = res
    end

    output = nn_utils.concatTensors (layerRes, outputDimension)
  else
    print (prefix .. 'Layer type: ' .. strLayer)
    print (prefix .. 'Input: ' .. nn_utils.tensorDimsStr(inputData))
    output = layer:forward(inputData)
  end
  if torch.isTensor(output) and output:ne(output):sum() > 0 then
    print( prefix .. '!!!!!!!!!!!!!!!!!!!!!!! Found NaN in output !!!!!!!!!!!!!!!!!!!!!!!')
  end

  print (prefix .. 'Output: ' .. nn_utils.tensorDimsStr(output))
  return output
end


local function appendToPrefix (oldPrefix, newStuff)
  if (oldPrefix and oldPrefix ~= '') then
    return oldPrefix .. '_' .. newStuff;
  else
    return newStuff;
  end
end

-- Assumes that the data matrix is set up as
--     level 1, channel 1
--     level 1, channel 2
--     ...
--     level 2, channel 1
--     level 2, channel 2
--     ...
function nn_utils.dumpIntermediateWeights (layer, inputData, pyramidLevelSizes, channelNames, outputImagesDir, filePrefix)
  local output
  local strLayer = tostring(layer)
  if (strLayer:sub(1,13) == 'nn.Sequential') then
    local nLayers = layer:size()
    local layerInput = inputData
    for iLayer = 1,nLayers do
      local curLayer = layer:get(iLayer)
      local newPrefix = appendToPrefix (filePrefix, 'layer' .. iLayer)
      local res = nn_utils.dumpIntermediateWeights (curLayer, layerInput, pyramidLevelSizes, channelNames, outputImagesDir, newPrefix)
      layerInput = res
    end

    output = layerInput
  elseif (strLayer:sub(1,11) == "nn.Parallel") then
    local nLayers = table.getn(layer.modules)
    local inputDimension = layer.inputDimension
    local outputDimension = layer.outputDimension
    local combinedRes;
    local nPyramidLevels = table.getn (pyramidLevelSizes)
    local nChannels = table.getn (channelNames)

    local layerRes = {}
    assert (nLayers == nPyramidLevels * nChannels)
    for iLevel = 1,nPyramidLevels do
      for jChannel = 1,nChannels do
        local iLayer = (iLevel-1) * nChannels + jChannel
        local curLayer = layer:get(iLayer)
        local curInput = inputData:select(inputDimension, iLayer)

        local newPrefix = appendToPrefix (filePrefix, 'level' .. iLevel .. '_' .. channelNames[jChannel])
        local res = nn_utils.dumpIntermediateWeights (curLayer, curInput, pyramidLevelSizes, channelNames, outputImagesDir, newPrefix)
        layerRes[iLayer] = res
      end
    end
    output = nn_utils.concatTensors (layerRes, outputDimension)
  elseif (strLayer == "nn.SpatialConvolution" or 
    strLayer == "nn.SpatialConvolutionMM") then
    -- For convolution layers, save out the weights and stuff:
    local nInputPlane = layer["nInputPlane"]
    local nOutputPlane = layer["nOutputPlane"]
    local kw = layer["kW"]
    local kh = layer["kH"]
    local weightOrig = layer["weight"]
    local w = torch.reshape (weightOrig, torch.LongStorage{nOutputPlane,nInputPlane,kw,kh})
    local nChannels = table.getn (channelNames)

    -- Only do this for the first layer:
    if (w:size(2) == nChannels) then
      local filename = appendToPrefix (filePrefix, '_weights.png')
      image.save (paths.concat(outputImagesDir, filename), 
      image.toDisplayTensor {input=w:select(2,1), padding=3})
    end

    -- Only show the first 10 activations:
    local nActivationImages = math.min (nOutputPlane, 10)

    output = layer:forward(inputData)
    for iOutputPlane = 1,nActivationImages do
      local filename = appendToPrefix (filePrefix, '_activations_plane' .. iOutputPlane .. '.png')
      image.save (paths.concat (outputImagesDir, filename), 
      image.toDisplayTensor {input=output[{{},iOutputPlane,{},{}}], padding=3})
    end
  elseif (strLayer == 'nn.View') then
    output = layer:forward(inputData)
    if (output:nDimension() == 4 and output:size(2) == 1) then
      local filename = appendToPrefix (filePrefix, '_view.png')
      image.save (paths.concat (outputImagesDir, filename), 
      image.toDisplayTensor {input=output[{{},1,{},{}}], padding=0})
    end
  else
    output = layer:forward(inputData)
  end

  return output
end

function nn_utils.customLCN(inputs, kernel, threshold, thresval)
  assert (inputs:dim() == 4, "Input should be of the form nSamples x nChannels x width x height")

  local padH = math.floor(kernel:size(1)/2)
  local padW = padH

  -- normalize the kernel
  kernel:div(kernel:sum())

  local meanestimator = nn.Sequential()
  meanestimator:add(nn.SpatialZeroPadding(padW, padW, padH, padH))
  meanestimator:add(nn.SpatialConvolutionMap(nn.tables.oneToOne(1), kernel:size(1), 1))
  meanestimator:add(nn.SpatialConvolution(1, 1, 1, kernel:size(1), 1))

  local stdestimator = nn.Sequential()
  stdestimator:add(nn.Square())
  stdestimator:add(nn.SpatialZeroPadding(padW, padW, padH, padH))
  stdestimator:add(nn.SpatialConvolutionMap(nn.tables.oneToOne(1), kernel:size(1), 1))
  stdestimator:add(nn.SpatialConvolution(1, 1, 1, kernel:size(1)))
  stdestimator:add(nn.Sqrt())

  for i = 1,1 do 
    meanestimator.modules[2].weight[i]:copy(kernel)
    meanestimator.modules[3].weight[1][i]:copy(kernel)
    stdestimator.modules[3].weight[i]:copy(kernel)
    stdestimator.modules[4].weight[1][i]:copy(kernel)
  end
  meanestimator.modules[2].bias:zero()
  meanestimator.modules[3].bias:zero()
  stdestimator.modules[3].bias:zero()
  stdestimator.modules[4].bias:zero()

  -- Run the meanestimator on a bunch of ones to figure out the sum of the kenrel
  -- (This is pretty wasteful for large number of samples N of Nx1xKxK.)
  local coef = meanestimator:updateOutput(inputs.new():resizeAs(inputs):fill(1))
  coef = coef:clone()

  -- Take the kernel weighted local sums
  local localSums = meanestimator:updateOutput(inputs)
  -- Divide by the response of the kernel on ones (effectively, dividing by the kernel sum)
  local adjustedSums = nn.CDivTable():updateOutput{localSums, coef}
  -- Subtract tout the kernel weigthed adjusted sums
  local meanSubtracted = nn.CSubTable():updateOutput{inputs, adjustedSums}

  -- Take the mean subtracted output and divide out the kernel weighted standard deviation
  local localStds = stdestimator:updateOutput(meanSubtracted)
  local adjustedStds = nn.CDivTable():updateOutput{localStds, coef}
  local thresholdedStds = nn.Threshold(threshold, thresval):updateOutput(adjustedStds)
  local outputs = nn.CDivTable():updateOutput{meanSubtracted, thresholdedStds}

  return outputs
end

function nn_utils.originalLCN(inputs, kernel, threshold, thresval)
  local normalization = nn.SpatialContrastiveNormalization(1, kernel, threshold, thresval)
  local outputs = inputs:clone()
  for i=1,inputs:size(1) do
    outputs[i] = normalization:forward(inputs[i])
    xlua.progress(i, inputs:size(1))
  end

  return outputs
end

function nn_utils.testLCN()
  local neighborhood = image.gaussian1D(7)
  local inputs = torch.randn(100, 1, 50, 50)
  local timer = torch.Timer()
  timer:reset()
  local originalOutputs = nn_utils.originalLCN(inputs, neighborhood, 1, 1)
  print('Original LCN took : ' .. timer:time().real .. ' seconds')
  timer:reset()
  local customOutputs = nn_utils.customLCN(inputs, neighborhood, 1, 1)
  print('  Custom LCN took : ' .. timer:time().real .. ' seconds')

  local norm = (customOutputs - originalOutputs):norm()
  print('Difference between original and custom LCN implementations : '..norm)
end


local function ConvInit(model, name)
   for k, v in pairs(model:findModules(name)) do
      local n = v.kW * v.kH * v.nOutputPlane
      v.weight:normal(0, math.sqrt(2 / n))
      if cudnn.version >= 4000 then
         v.bias = nil
         v.gradBias = nil
      else
         v.bias:zero()
      end
   end
end

local function BNInit(model, name)
   for k, v in pairs(model:findModules(name)) do
      v.weight:fill(1)
      v.bias:zero()
   end
end

function nn_utils.init(model, opt)
   ConvInit(model, 'cudnn.SpatialConvolution')
   ConvInit(model, 'nn.SpatialConvolution')
   BNInit(model, 'fbnn.SpatialBatchNormalization')
   BNInit(model, 'cudnn.SpatialBatchNormalization')
   BNInit(model, 'nn.SpatialBatchNormalization')
   for k, v in pairs(model:findModules('nn.Linear')) do
      v.bias:zero()
   end
end

function nn_utils.cudnnize(model, opt)
   model:cuda()
   cudnn.convert(model, cudnn)

   if opt.cudnn == 'deterministic' then
      model:apply(function(m)
            if m.setMode then m:setMode(1,1,1) end
      end)
   end
end

return nn_utils
