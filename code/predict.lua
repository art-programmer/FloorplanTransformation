require 'nn'
require 'cudnn'
require 'cunn'
image = require 'image'

package.path = '../util/lua/?.lua;' .. package.path
local fp_ut = require 'floorplan_utils'
pl = require 'pl.import_into' ()

pl.dir.makepath('test/')


local opts = require 'opts'
local opt = opts.parse(arg)
opts.init(opt)

local modelHeatmap = torch.load(opt.loadModel)
local heatmapBranch = nn.Sequential():add(nn.MulConstant(0.1))
local segmentationBranch_1 = nn.Sequential():add(nn.SoftMax()):add(nn.View(-1, opt.sampleDim, opt.sampleDim, 13)):add(nn.Transpose({3, 4}, {2, 3}))
local segmentationBranch_2 = nn.Sequential():add(nn.SoftMax()):add(nn.View(-1, opt.sampleDim, opt.sampleDim, 17)):add(nn.Transpose({3, 4}, {2, 3}))
modelHeatmap:add(nn.ParallelTable():add(heatmapBranch):add(segmentationBranch_1):add(segmentationBranch_2))
modelHeatmap:add(nn.JoinTable(1, 3))
modelHeatmap:cuda()
modelHeatmap:evaluate()


local floorplan = image.load(opt.floorplanFilename, 3)

local representationPrediction = fp_ut.invertFloorplan(modelHeatmap, floorplan)

local representationImage = fp_ut.drawRepresentationImage(floorplan, representationPrediction)
print(opt.outputFilename .. '.txt')
fp_ut.saveRepresentation(opt.outputFilename .. '.txt', representationPrediction)
fp_ut.writePopupData(floorplan:size(3), floorplan:size(2), representationPrediction, opt.outputFilename .. '_popup', representationPrediction)
image.save(opt.outputFilename .. '.png', representationImage)
