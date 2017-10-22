require 'itorch'
require 'torch'
require 'nn'
local pl = require 'pl.import_into'()
local class = require 'class'

local itorch_utils = {}

-- Itorch utilities.
-- Channels:
function itorch_utils.showResp(chns, baselines)
  assert(chns:nDimension() == 3)

  local chnTable = {}
  for i = 1, chns:size(1) do
    if baselines then
      chnTable[i] = chns[i] - baselines[i];
    else
      chnTable[i] = chns[i]
    end;
  end
  itorch.image(chnTable)
end

function itorch_utils.showConvw(layer, outputIdx)
  if class.istype(layer, 'nn.SpatialConvolution') == nil then
    print("Input is " .. torch.classname(layer) .. " no weights can be shown.");
    return
  end

  local v
  if layer.weight:nDimension() == 2 then
    v = layer.weight[outputIdx]:view(layer.nInputPlane, layer.kH, layer.kW);
  else
    v = layer.weight[outputIdx]
  end
  itorch_utils.showResp(v)
end

function itorch_utils.showImMask(im, mask)
  local inputDup = im:sub(1, 3):clone()
  inputDup[1]:add(mask)

  itorch.image(inputDup)
end

function itorch_utils.showImOverlay(input)
  local inputDup = input:sub(1, 3):clone()
  inputDup[1]:add(input[4])

  itorch.image(inputDup)
end

function itorch_utils.showImOverlays(inputs, extractor)
  -- Input is a table with nbatch element, each is 4 * h * w
  local vis = pl.tablex.map(function(x)
    if extractor ~= nil then
      x = extractor(x)
    end
    local inputDup = x:sub(1, 3):clone()
    inputDup[1]:add(x[4])
    return inputDup;
  end,
  inputs);

  itorch.image(vis)
end

-- Show a list of images. Inputs are nimage * 3 * h * w, convert them into 
function itorch_utils.compareIms(...)
  -- Input is a set of images, each is nimage * 3 * h * w
  local ims = {}
  local args = {...}
  local nIms = args[1]:size(1)

  for i = 1, nIms do
    for _, input in ipairs(args) do 
      table.insert(ims, input[i])
    end
  end

  itorch.image(ims)
end

return itorch_utils
