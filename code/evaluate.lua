require 'nn'
require 'cudnn'
require 'cunn'

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


local dataPath = '../data/'
local imageInfo = csvigo.load({path=dataPath .. '/test.txt', mode="large", header=false, separator='\t'})

local result = {}
for _, mode in pairs({'Wall Junction', 'Door', 'Object', 'Room'}) do
   result[mode] = {}
   for _, value in pairs({'numCorrectPredictions', 'numTargets', 'numPredictions'}) do
      result[mode][value] = 0
   end
end


local resultFilenames = {}

--local finalExamples = {1, 2, 4, 5, 6}
--for _, i in pairs(finalExamples) do
local results = {}

local resultPath = opt.resultPath or 'results/'
if resultPath then
   pl.dir.makepath(resultPath)
end

for index, filenames in pairs(imageInfo) do
   local floorplanFilename = dataPath .. filenames[1]
   local representationFilename = dataPath .. filenames[2]
   local floorplan = image.load(floorplanFilename, 3)
   local representationTarget = fp_ut.loadRepresentation(representationFilename)
   
   local representationPrediction = fp_ut.invertFloorplan(modelHeatmap, floorplan)
   
   local singleResult = fp_ut.evaluateResult(floorplan:size(3), floorplan:size(2), representationTarget, representationPrediction, {pointDistanceThreshold = 0.02, doorDistanceThreshold = 0.02, iconIOUThreshold = 0.5, segmentIOUThreshold = 0.7}, result)
   table.insert(results, singleResult)
   for mode, values in pairs(singleResult) do
      for valueIndex, value in pairs(values) do
	 result[mode][valueIndex] = result[mode][valueIndex] + value
      end
   end

   local representationImage = fp_ut.drawRepresentationImage(floorplan, representationPrediction)
   local img = torch.cat(floorplan, representationImage, 3)
   local floorplanPredictionFilename = 'representation_prediction_' .. index .. '.png'
   image.save(resultPath .. '/' .. floorplanPredictionFilename, img)   
   table.insert(resultFilenames, floorplanPredictionFilename)
end

print(results)

local resultFile = io.open(resultPath .. '/index.html', 'w')
resultFile:write("<!DOCTYPE html><html><head></head><body>")
resultFile:write("<h3>Statistics:</h3>")
resultFile:write('<table border="1">')
resultFile:write("<tr><th>Category</th><th>Precision(%)</th><th>Recall(%)</th></tr>")
for mode, values in pairs(result) do
   resultFile:write("<tr><td>" .. mode .. "</td><td>" .. torch.round(values.numCorrectPredictions / values.numPredictions * 1000) / 10 .. "</td><td>" .. torch.round(values.numCorrectPredictions / values.numTargets * 1000) / 10 .. "</td></tr>")
end
resultFile:write("</table>")

resultFile:write("<h3>Results:</h3>")
for i, filename in pairs(resultFilenames) do
   resultFile:write("<p>Index " .. i .. "</p>")
   resultFile:write('<img src="' .. filename .. '" alt="' .. filename .. '" width="100%">')
end
resultFile:write("</body></html>")
resultFile:close()

