package.path = '../util/lua/?.lua;' .. package.path
local fp_ut = require 'floorplan_utils'

dataPath = '../data/'

local imageInfo = csvigo.load({path=dataPath + '/test.txt', mode="large", header=false, separator='\t'})

local result = {}
for _, mode in pairs({'Wall Junction', 'Door', 'Object', 'Room'}) do
   result[mode] = {}
   for _, value in pairs({'numCorrectPredictions', 'numTargets', 'numPredictions'}) do
      result[mode][value] = 0
   end
end


local filenames = {}

--local finalExamples = {1, 2, 4, 5, 6}
--for _, i in pairs(finalExamples) do
local results = {}
for k, v in pairs(photo_info) do
   local floorplanFilename = dataPath .. v[1]
   local representationFilename = dataPath .. v[2]


   representationPrediction = fp_ut.invertFloorplan(floorplan, false)
   local singleResult = fp_ut.evaluateResult(floorplan:size(3), floorplan:size(2), representationTarget, representationPrediction, {pointDistanceThreshold = 0.02, doorDistanceThreshold = 0.02, iconIOUThreshold = 0.5, segmentIOUThreshold = 0.7}, result)
   table.insert(results, singleResult)
   for mode, values in pairs(singleResult) do
      for valueIndex, value in pairs(values) do
	 result[mode][valueIndex] = result[mode][valueIndex] + value
      end
   end

   table.insert(filenames, floorplanFilename)
end

print(results)


local resultPath = resultPath or 'results/'
if resultPath then
   pl.dir.makepath(resultPath)
end

local resultFile = io.open(resultPath .. 'index.html', 'w')
resultFile:write("<!DOCTYPE html><html><head></head><body>")
resultFile:write("<h3>Statistics:</h3>")
resultFile:write('<table border="1">')
resultFile:write("<tr><th>Category</th><th>Precision(%)</th><th>Recall(%)</th></tr>")
for mode, values in pairs(result) do
   resultFile:write("<tr><td>" .. mode .. "</td><td>" .. torch.round(values.numCorrectPredictions / values.numPredictions * 1000) / 10 .. "</td><td>" .. torch.round(values.numCorrectPredictions / values.numTargets * 1000) / 10 .. "</td></tr>")
end
resultFile:write("</table>")

resultFile:write("<h3>Results:</h3>")
for i, filename in pairs(filenames) do
   resultFile:write("<p>Index " .. i .. "</p>")
   resultFile:write('<img src="' .. filename .. '" alt="' .. filename .. '" width="100%">')
end
resultFile:write("</body></html>")
resultFile:close()

