require 'csvigo'
require 'image'
local pl = require 'pl.import_into' ()
cv = require 'cv'
require 'cv.imgproc'
py = require('python')
--paths.dofile('/home/chenliu/Projects/Floorplan/floorplan/InverseCAD/models/SpatialSymmetricPadding.lua')

local utils = {}

function utils.getSortedModes()
   return {'points', 'doors', 'icons', 'labels'}
end

function utils.getNumberMap()
   if not utils.numberMap then
      local numberMap = {}
      numberMap.labels = {}
      numberMap.labels['living_room'] = 1
      numberMap.labels['kitchen'] = 2
      numberMap.labels['bedroom'] = 3
      numberMap.labels['bathroom'] = 4
      numberMap.labels['restroom'] = 5
      numberMap.labels['balcony'] = 6
      numberMap.labels['closet'] = 7
      numberMap.labels['corridor'] = 8
      numberMap.labels['washing_room'] = 9
      numberMap.labels['PS'] = 10

      numberMap.icons = {}
      numberMap.icons['bathtub'] = {1}
      numberMap.icons['cooking_counter'] = {2, 2}
      numberMap.icons['toilet'] = {3}
      numberMap.icons['entrance'] = {4}
      numberMap.icons['washing_basin'] = {5, 6, 5, 5}
      numberMap.icons['special'] = {8, 8, 9}
      numberMap.icons['stairs'] = {10}

      numberMap.doors = {}
      numberMap.doors['door'] = 1
      utils.numberMap = numberMap
   end
   return utils.numberMap
end

function utils.getNumber(mode, itemInfo)
   local numberMap = utils.getNumberMap()
   if mode == 'points' then
      return (itemInfo[2] - 1) * 4 + itemInfo[3]
   elseif mode == 'doors' then
      return itemInfo[2]
   elseif mode == 'icons' then
      return numberMap[mode][itemInfo[1]][itemInfo[2]]
   elseif mode == 'labels' then
      return numberMap[mode][itemInfo[1]]
   else
      assert(false)
   end
end

function utils.getNameMap()
   if not utils.nameMap then
      local nameMap = {}
      local numberMap = utils.getNumberMap()
      for mode, map in pairs(numberMap) do
         nameMap[mode] = {}
         for name, number in pairs(map) do
            if type(number) == "table" then
               for _, num in pairs(number) do
                  if not nameMap[mode][num] then
                     nameMap[mode][num] = {name, _, 1}
                  end
               end
            else
               if not nameMap[mode][number] then
                  nameMap[mode][number] = {name, 1, 1}
               end
            end
         end
      end
      utils.nameMap = nameMap
   end
   return utils.nameMap
end

function utils.getItemInfo(mode, number)
   local nameMap = utils.getNameMap()
   if mode == 'points' then
      return {'point', math.floor((number - 1) / 4) + 1, (number - 1) % 4 + 1}
   elseif mode == 'doors' then
      return {'door', number, 1}
   elseif mode == 'icons' then
      number = math.min(number, #nameMap[mode])
      return nameMap[mode][number]
   elseif mode == 'labels' then
      number = math.min(number, #nameMap[mode])
      return nameMap[mode][number]
   else
      assert(false)
   end
end

function utils.keyMap()
   local keyMap = {}
   keyMap['b'] = {'icons', 'bathtub'}
   keyMap['c'] = {'icons', 'cooking_counter'}
   keyMap['t'] = {'icons', 'toilet'}
   keyMap['q'] = {'icons', 'special'}
   keyMap['e'] = {'icons', 'entrance'}
   keyMap['w'] = {'icons', 'washing_basin'}
   keyMap['s'] = {'icons', 'stairs'}
   for i = 1, 10 do
      keyMap[tostring(i % 10)] = {'labels', utils.getItemInfo('labels', i)[1]}
   end
   keyMap['a'] = {'walls', 'wall'}
   keyMap['d'] = {'doors', 'door'}

   return keyMap
end

function utils.modeMap()
   local modeMap = {}
   local keyMap = utils.keyMap()
   for _, modeNamePair in pairs(keyMap) do
      modeMap[modeNamePair[2]] = modeNamePair[1]
   end
   modeMap['point'] = 'points'
   return modeMap
end

function utils.numItemsPerCell()
   local numItemsPerCell = {}
   numItemsPerCell.points = 2
   numItemsPerCell.doors = 2
   numItemsPerCell.icons = 2
   numItemsPerCell.labels = 2
   return numItemsPerCell
end

function utils.numItemsGlobal()
   local numItemsGlobal = {}
   numItemsGlobal['bathtub'] = 1
   numItemsGlobal['cooking_counter'] = 1
   numItemsGlobal['toilet'] = 2
   numItemsGlobal['special'] = 4
   numItemsGlobal['entrance'] = 1
   numItemsGlobal['washing_basin'] = 4
   numItemsGlobal['stairs'] = 4

   numItemsGlobal['living_room'] = 1
   numItemsGlobal['kitchen'] = 1
   numItemsGlobal['bedroom'] = 4
   numItemsGlobal['bathroom'] = 1
   numItemsGlobal['restroom'] = 2
   numItemsGlobal['balcony'] = 2
   numItemsGlobal['closet'] = 4
   numItemsGlobal['corridor'] = 1
   numItemsGlobal['washing_room'] = 1
   numItemsGlobal['PS'] = 2

   return numItemsGlobal
end

function utils.numFeaturesPerItem()
   local numFeaturesPerItem = {}
   numFeaturesPerItem.points = 5
   numFeaturesPerItem.doors = 5
   numFeaturesPerItem.icons = 5
   numFeaturesPerItem.labels = 5
   return numFeaturesPerItem
end

function utils.offsetsBB()
   local numItemsPerCell = utils.numItemsPerCell()
   local numFeaturesPerItem = utils.numFeaturesPerItem()
   local offsetsBB = {}
   offsetsBB.points = 0
   offsetsBB.doors = offsetsBB.points + numFeaturesPerItem.points * numItemsPerCell.points
   offsetsBB.icons = offsetsBB.doors + numFeaturesPerItem.doors * numItemsPerCell.doors
   offsetsBB.labels = offsetsBB.icons + numFeaturesPerItem.icons * numItemsPerCell.icons
   return offsetsBB
end

function utils.numFeaturesBB()
   local numItemsPerCell = utils.numItemsPerCell()
   local offsetsBB = utils.offsetsBB()
   local numFeaturesPerItem = utils.numFeaturesPerItem()
   local numFeaturesBB = offsetsBB.labels + numFeaturesPerItem.labels * numItemsPerCell.labels
   return numFeaturesBB
end

function utils.offsetsClass()
   local numItemsPerCell = utils.numItemsPerCell()
   local numFeaturesBB = utils.numFeaturesBB()
   local offsetsClass = {}
   offsetsClass.points = numFeaturesBB
   offsetsClass.doors = offsetsClass.points + numItemsPerCell.points
   offsetsClass.icons = offsetsClass.doors + numItemsPerCell.doors
   offsetsClass.labels = offsetsClass.icons + numItemsPerCell.icons
   return offsetsClass
end

function utils.numFeaturesClass()
   local numItemsPerCell = utils.numItemsPerCell()
   local numFeaturesClass = numItemsPerCell.points + numItemsPerCell.doors + numItemsPerCell.icons + numItemsPerCell.labels
   return numFeaturesClass
end

function utils.getAnchorBoxesMap(cellWidth, cellHeight)
   local junctionAnchorBoxes = {}
   --[[
      table.insert(junctionAnchorBoxes, {{cellWidth / 6 * 1, cellHeight / 6 * 1}, {cellWidth / 3, cellHeight / 3}})
      table.insert(junctionAnchorBoxes, {{cellWidth / 6 * 3, cellHeight / 6 * 1}, {cellWidth / 3, cellHeight / 3}})
      table.insert(junctionAnchorBoxes, {{cellWidth / 6 * 5, cellHeight / 6 * 1}, {cellWidth / 3, cellHeight / 3}})
      table.insert(junctionAnchorBoxes, {{cellWidth / 6 * 1, cellHeight / 6 * 3}, {cellWidth / 3, cellHeight / 3}})
      table.insert(junctionAnchorBoxes, {{cellWidth / 6 * 3, cellHeight / 6 * 3}, {cellWidth / 3, cellHeight / 3}})
      table.insert(junctionAnchorBoxes, {{cellWidth / 6 * 5, cellHeight / 6 * 3}, {cellWidth / 3, cellHeight / 3}})
      table.insert(junctionAnchorBoxes, {{cellWidth / 6 * 1, cellHeight / 6 * 5}, {cellWidth / 3, cellHeight / 3}})
      table.insert(junctionAnchorBoxes, {{cellWidth / 6 * 3, cellHeight / 6 * 5}, {cellWidth / 3, cellHeight / 3}})
      table.insert(junctionAnchorBoxes, {{cellWidth / 6 * 5, cellHeight / 6 * 5}, {cellWidth / 3, cellHeight / 3}})
   ]]--
   for i = 1, 13 do
      table.insert(junctionAnchorBoxes, {{cellWidth / 2, cellHeight / 2}, {cellWidth, cellHeight}})
   end


   local doorAnchorBoxes = {}
   table.insert(doorAnchorBoxes, {{cellWidth / 8 * 1, cellHeight / 2}, {cellWidth / 4, cellHeight}})
   table.insert(doorAnchorBoxes, {{cellWidth / 8 * 3, cellHeight / 2}, {cellWidth / 4, cellHeight}})
   table.insert(doorAnchorBoxes, {{cellWidth / 8 * 5, cellHeight / 2}, {cellWidth / 4, cellHeight}})
   table.insert(doorAnchorBoxes, {{cellWidth / 8 * 7, cellHeight / 2}, {cellWidth / 4, cellHeight}})
   table.insert(doorAnchorBoxes, {{cellWidth / 2, cellHeight / 8 * 1}, {cellWidth, cellHeight / 4}})
   table.insert(doorAnchorBoxes, {{cellWidth / 2, cellHeight / 8 * 3}, {cellWidth, cellHeight / 4}})
   table.insert(doorAnchorBoxes, {{cellWidth / 2, cellHeight / 8 * 5}, {cellWidth, cellHeight / 4}})
   table.insert(doorAnchorBoxes, {{cellWidth / 2, cellHeight / 8 * 7}, {cellWidth, cellHeight / 4}})
   table.insert(doorAnchorBoxes, {{cellWidth / 2, cellHeight / 2}, {cellWidth, cellHeight}})

   table.insert(doorAnchorBoxes, {{cellWidth / 4 * 1, cellHeight / 2}, {cellWidth / 2, cellHeight * 2}})
   table.insert(doorAnchorBoxes, {{cellWidth / 4 * 3, cellHeight / 2}, {cellWidth / 2, cellHeight * 2}})
   table.insert(doorAnchorBoxes, {{cellWidth / 2, cellHeight / 4 * 1}, {cellWidth * 2, cellHeight / 2}})
   table.insert(doorAnchorBoxes, {{cellWidth / 2, cellHeight / 4 * 3}, {cellWidth * 2, cellHeight / 2}})


   local iconAnchorBoxes = {}
   table.insert(iconAnchorBoxes, {{cellWidth / 2, cellHeight / 2}, {cellWidth, cellHeight}})
   table.insert(iconAnchorBoxes, {{cellWidth / 2, cellHeight / 2}, {cellWidth * 2, cellHeight}})
   table.insert(iconAnchorBoxes, {{cellWidth / 2, cellHeight / 2}, {cellWidth, cellHeight * 2}})
   table.insert(iconAnchorBoxes, {{cellWidth / 2, cellHeight / 2}, {cellWidth / 2, cellHeight / 2}})
   table.insert(iconAnchorBoxes, {{cellWidth / 2, cellHeight / 2}, {cellWidth / 2, cellHeight}})
   table.insert(iconAnchorBoxes, {{cellWidth / 2, cellHeight / 2}, {cellWidth, cellHeight / 2}})
   table.insert(iconAnchorBoxes, {{cellWidth / 2, cellHeight / 2}, {cellWidth / 4, cellHeight / 4}})
   table.insert(iconAnchorBoxes, {{cellWidth / 2, cellHeight / 2}, {cellWidth / 4, cellHeight / 2}})
   table.insert(iconAnchorBoxes, {{cellWidth / 2, cellHeight / 2}, {cellWidth / 2, cellHeight / 4}})

   table.insert(iconAnchorBoxes, {{cellWidth / 2, cellHeight / 4 * 1}, {cellWidth, cellHeight / 2}})
   table.insert(iconAnchorBoxes, {{cellWidth / 2, cellHeight / 4 * 3}, {cellWidth, cellHeight / 2}})
   table.insert(iconAnchorBoxes, {{cellWidth / 4 * 1, cellHeight / 2}, {cellWidth / 2, cellHeight}})
   table.insert(iconAnchorBoxes, {{cellWidth / 4 * 3, cellHeight / 2}, {cellWidth / 2, cellHeight}})


   local labelAnchorBoxes = {}
   table.insert(labelAnchorBoxes, {{cellWidth / 6 * 1, cellHeight / 6 * 1}, {cellWidth / 3, cellHeight / 3}})
   table.insert(labelAnchorBoxes, {{cellWidth / 6 * 3, cellHeight / 6 * 1}, {cellWidth / 3, cellHeight / 3}})
   table.insert(labelAnchorBoxes, {{cellWidth / 6 * 5, cellHeight / 6 * 1}, {cellWidth / 3, cellHeight / 3}})
   table.insert(labelAnchorBoxes, {{cellWidth / 6 * 1, cellHeight / 6 * 3}, {cellWidth / 3, cellHeight / 3}})
   table.insert(labelAnchorBoxes, {{cellWidth / 6 * 3, cellHeight / 6 * 3}, {cellWidth / 3, cellHeight / 3}})
   table.insert(labelAnchorBoxes, {{cellWidth / 6 * 5, cellHeight / 6 * 3}, {cellWidth / 3, cellHeight / 3}})
   table.insert(labelAnchorBoxes, {{cellWidth / 6 * 1, cellHeight / 6 * 5}, {cellWidth / 3, cellHeight / 3}})
   table.insert(labelAnchorBoxes, {{cellWidth / 6 * 3, cellHeight / 6 * 5}, {cellWidth / 3, cellHeight / 3}})
   table.insert(labelAnchorBoxes, {{cellWidth / 6 * 5, cellHeight / 6 * 5}, {cellWidth / 3, cellHeight / 3}})

   table.insert(labelAnchorBoxes, {{cellWidth / 4 * 1, cellHeight / 4 * 1}, {cellWidth / 2, cellHeight / 2}})
   table.insert(labelAnchorBoxes, {{cellWidth / 4 * 1, cellHeight / 4 * 3}, {cellWidth / 2, cellHeight / 2}})
   table.insert(labelAnchorBoxes, {{cellWidth / 4 * 3, cellHeight / 4 * 1}, {cellWidth / 2, cellHeight / 2}})
   table.insert(labelAnchorBoxes, {{cellWidth / 4 * 3, cellHeight / 4 * 3}, {cellWidth / 2, cellHeight / 2}})


   local anchorBoxesMap = {}
   anchorBoxesMap['points'] = junctionAnchorBoxes
   anchorBoxesMap['doors'] = doorAnchorBoxes
   anchorBoxesMap['icons'] = iconAnchorBoxes
   anchorBoxesMap['labels'] = labelAnchorBoxes
   return anchorBoxesMap
end

function utils.getColorMap()
   local colorMap = {}
   colorMap[1] = {255, 0, 0}
   colorMap[2] = {0, 255, 0}
   colorMap[3] = {0, 0, 255}
   colorMap[4] = {255, 255, 0}
   colorMap[5] = {0, 255, 255}
   colorMap[6] = {255, 0, 255}
   colorMap[7] = {128, 0, 0}
   colorMap[8] = {0, 128, 0}
   colorMap[9] = {0, 0, 128}
   colorMap[10] = {128, 128, 0}
   colorMap[11] = {0, 128, 128}
   colorMap[12] = {128, 0, 128}
   colorMap[13] = {128, 128, 128}
   return colorMap
end



function utils.findConnectedComponents(mask)
   local maskByte = (mask * 255):byte()
   local components = torch.IntTensor(maskByte:size())
   local numComponents = cv.connectedComponents{maskByte, components}
   return components, numComponents
end

function utils.drawSegmentation(floorplanComponent, numComponents, denotedColorMap)
   local numComponents = numComponents or torch.max(floorplanComponent)
   local colorMap = denotedColorMap
   if colorMap == nil then
      colorMap = {}
      for i = 1, numComponents do
         colorMap[i] = torch.rand(3)
      end
   end
   colorMap[0] = torch.zeros(3)
   colorMap[-1] = torch.ones(3)

   local floorplanLabels = floorplanComponent:repeatTensor(3, 1, 1):double()
   for c = 1, 3 do
      floorplanLabels[c]:apply(function(x) return colorMap[x][c] end)
   end
   return floorplanLabels
end

function loadIcon(iconName, iconStyle, iconOrientation, extension)
   local icon = image.load('../icons/' .. iconName .. '_' .. iconStyle .. '.' .. extension, 1)
   assert(icon ~= nil)
   return rotateIcon(icon, iconOrientation)
end

function rotateIcon(iconOriginal, iconOrientation)
   local iconRotated
   if iconOrientation == 1 then
      iconRotated = iconOriginal:clone()
   elseif iconOrientation == 2 then
      if iconOriginal:dim() == 2 then
         iconRotated = image.hflip(iconOriginal:transpose(1, 2):contiguous())
      else
         iconRotated = image.hflip(iconOriginal:transpose(2, 3):contiguous())
      end
   elseif iconOrientation == 3 then
      iconRotated = image.vflip(image.hflip(iconOriginal))
   else
      if iconOriginal:dim() == 2 then
         iconRotated = image.vflip(iconOriginal:transpose(1, 2):contiguous())
      else
         iconRotated = image.vflip(iconOriginal:transpose(2, 3):contiguous())
      end
   end
   return iconRotated
end

function utils.loadIconImages()
   if utils.iconImages == nil then
      utils.iconImages = {}
      local numberMap = utils.getNumberMap()
      for mode, map in pairs(numberMap) do
         local extension = 'jpg'
         if mode == 'labels' then
            extension = 'png'
         end
         for name, number in pairs(map) do
            utils.iconImages[name] = {}
            for style = 1, 13 do
               local iconExists, icon = pcall(function()
                     return loadIcon(name, style, 1, extension)
               end)
               if iconExists == false then
                  break
               end
               if icon:dim() == 3 then
                  icon = icon[1]
               end
               utils.iconImages[name][style] = icon
            end
         end
      end
   end
   return utils.iconImages
end

function utils.lineDim(line, lineWidth)
   local lineWidth = lineWidth or 1
   if math.abs(line[1][1] - line[2][1]) > math.abs(line[1][2] - line[2][2]) and math.abs(line[1][2] - line[2][2]) <= lineWidth then
      return 1
   elseif math.abs(line[1][2] - line[2][2]) > math.abs(line[1][1] - line[2][1]) and math.abs(line[1][1] - line[2][1]) <= lineWidth then
      return 2
   else
      return 0
   end
end

function utils.cutoffRange(range, max)
   local lowerBound = math.max(range[1], 1)
   local upperBound = math.min(range[2], max)
   if lowerBound > upperBound then
      return {}
   else
      return {lowerBound, upperBound}
   end
end

function utils.drawLineMask(width, height, lines, lineWidth, indexed, lineExtentionLength, denotedLineDim)
   local lineWidth = lineWidth or 5
   local indexed = indexed or false
   local lineExtentionLength = lineExtentionLength or lineWidth

   local lineMask = torch.zeros(height, width)
   local size = {width, height}
   local index = 1
   for _, line in pairs(lines) do
      local lineDim = utils.lineDim(line)
      if (not denotedLineDim and lineDim > 0) or lineDim == denotedLineDim then
         local fixedDim = 3 - lineDim
         local fixedValue = (line[1][fixedDim] + line[2][fixedDim]) / 2
         local fixedRange = utils.cutoffRange({fixedValue - lineWidth, fixedValue + lineWidth}, size[fixedDim])
         if #fixedRange > 0 then
            local lineRange = utils.cutoffRange({line[1][lineDim] - lineExtentionLength, line[2][lineDim] + lineExtentionLength}, size[lineDim])
            if lineDim == 1 then
               lineMask[{{fixedRange[1], fixedRange[2]}, {lineRange[1], lineRange[2]}}] = index
            else
               lineMask[{{lineRange[1], lineRange[2]}, {fixedRange[1], fixedRange[2]}}] = index
            end
         end
      elseif not denotedLineDim and lineDim == 0 then
         if math.abs(line[1][1] - line[2][1]) > math.abs(line[1][2] - line[2][2]) then
            lineDim = 1
         else
            lineDim = 2
         end
         for lineDimValue = math.min(line[1][lineDim], line[2][lineDim]), math.max(line[1][lineDim], line[2][lineDim]) do
            local orthogonalValue = line[1][3 - lineDim] + (lineDimValue - line[1][lineDim]) / (line[2][lineDim] -  line[1][lineDim]) * (line[2][3 - lineDim] -  line[1][3 - lineDim])
            local orthogonalRange = utils.cutoffRange({orthogonalValue - lineWidth, orthogonalValue + lineWidth}, size[3 - lineDim])
            if lineDim == 1 then
               lineMask[{{orthogonalRange[1], orthogonalRange[2]}, lineDimValue}] = index
            else
               lineMask[{lineDimValue, {orthogonalRange[1], orthogonalRange[2]}}] = index
            end
         end
      end

      if indexed then
         index = index + 1
      end
   end
   return lineMask
end

function utils.sortLines(lines)
   for lineIndex, line in pairs(lines) do
      local lineDim = utils.lineDim(line)
      if lineDim > 0 and line[1][lineDim] > line[2][lineDim] then
         local temp = lines[lineIndex][1][lineDim]
         lines[lineIndex][1][lineDim] = lines[lineIndex][2][lineDim]
         lines[lineIndex][2][lineDim] = temp
      end
   end
   return lines
end

function utils.calcDistance(point_1, point_2)
   return math.sqrt(math.pow(point_1[1] - point_2[1], 2) + math.pow(point_1[2] - point_2[2], 2))
end

function utils.findNearestJunctionPair(line_1, line_2, gap, styleSensitive)
   local nearestPair
   local minDistance
   for index_1 = 1, 2 do
      for index_2 = 1, 2 do
         local distance = utils.calcDistance(line_1[index_1], line_2[index_2])
         if minDistance == nil or distance < minDistance then
            nearestPair = {index_1, index_2}
            minDistance = distance
         end
      end
   end
   if minDistance > gap then
      local lineDim_1 = utils.lineDim(line_1)
      local lineDim_2 = utils.lineDim(line_2)
      if lineDim_1 + lineDim_2 == 3 then
         local fixedValue_1 = (line_1[1][3 - lineDim_1] + line_1[2][3 - lineDim_1]) / 2
         local fixedValue_2 = (line_2[1][3 - lineDim_2] + line_2[2][3 - lineDim_2]) / 2
         if line_2[1][lineDim_2] < fixedValue_1 and line_2[2][lineDim_2] > fixedValue_1 then
            for index = 1, 2 do
               local distance = math.abs(line_1[index][lineDim_1] - fixedValue_2)
               if distance < minDistance then
                  nearestPair = {index, 0}
                  minDistance = distance
               end
            end
         end
         if line_1[1][lineDim_1] < fixedValue_2 and line_1[2][lineDim_1] > fixedValue_2 then
            for index = 1, 2 do
               local distance = math.abs(line_2[index][lineDim_2] - fixedValue_1)
               if distance < minDistance then
                  nearestPair = {0, index}
                  minDistance = distance
               end
            end
         end
      end
   end
   if styleSensitive ~= false then
      if #line_1 >= 3 and line_1[3][2] == 2 and line_2[3][2] == 1 then
         minDistance = gap + 1
         nearestPair[2] = 0
      end
      if #line_2 >= 3 and line_2[3][2] == 2 and line_1[3][2] == 1 then
         minDistance = gap + 1
         nearestPair[1] = 0
      end
   end

   return nearestPair, minDistance
end

function utils.stitchLines(lines, gap)
   for lineIndex_1, line_1 in pairs(lines) do
      local lineDim_1 = utils.lineDim(line_1)
      if lineDim_1 > 0 then
         local fixedValue_1 = (line_1[1][3 - lineDim_1] + line_1[2][3 - lineDim_1]) / 2
         for lineIndex_2, line_2 in pairs(lines) do
            if lineIndex_2 > lineIndex_1 then
               local lineDim_2 = utils.lineDim(line_2)
               if lineDim_2 > 0 then
                  local fixedValue_2 = (line_2[1][3 - lineDim_2] + line_2[2][3 - lineDim_2]) / 2
                  local nearestPair, minDistance = utils.findNearestJunctionPair(line_1, line_2, gap)
                  --print(minDistance .. ' ' .. lineDim_1 .. ' ' .. lineDim_2)
                  if minDistance <= gap and lineDim_1 + lineDim_2 == 3 then
                     local pointIndex_1 = nearestPair[1]
                     local pointIndex_2 = nearestPair[2]
                     --print(lineIndex_1 .. ' ' .. lineIndex_2)
                     if pointIndex_1 > 0 and pointIndex_2 > 0 then
                        lines[lineIndex_1][pointIndex_1][lineDim_1] = fixedValue_2
                        lines[lineIndex_2][pointIndex_2][lineDim_2] = fixedValue_1
                     elseif pointIndex_1 > 0 and pointIndex_2 == 0 then
                        lines[lineIndex_1][pointIndex_1][lineDim_1] = fixedValue_2
                     elseif pointIndex_1 == 0 and pointIndex_2 > 0 then
                        lines[lineIndex_2][pointIndex_2][lineDim_2] = fixedValue_1
                     end
                  end
               end
            end
         end
      end
   end
   return lines
end

function utils.mergeLines(lines, gap)
   local mergedLines = {}
   local mergedLineMap = {}
   while true do
      local hasChange = false
      for lineIndex_1, line_1 in pairs(lines) do
         if not mergedLines[lineIndex_1] and line_1[3][2] == 2 then
            local lineDim_1 = utils.lineDim(line_1)
            if lineDim_1 > 0 then
               local fixedValue_1 = (line_1[1][3 - lineDim_1] + line_1[2][3 - lineDim_1]) / 2
               for lineIndex_2, line_2 in pairs(lines) do
                  if lineIndex_2 ~= lineIndex_1 then
                     local lineDim_2 = utils.lineDim(line_2)
                     if lineDim_2 == lineDim_1 and line_2[3][2] == 1 then
                        local nearestPair, minDistance = utils.findNearestJunctionPair(line_1, line_2, gap, false)
                        if minDistance <= gap then
                           local fixedValue_2 = (line_2[1][3 - lineDim_2] + line_2[2][3 - lineDim_2]) / 2
                           local pointIndex_1 = nearestPair[1]
                           local pointIndex_2 = nearestPair[2]
                           --print(lineIndex_1 .. ' ' .. lineIndex_2)
                           if pointIndex_1 > 0 and pointIndex_2 > 0 then
                              --local fixedValue = (fixedValue_1 + fixedValue_2) / 2
                              local fixedValue = fixedValue_2
                              for pointIndex = 1, 2 do
                                 --line_1[pointIndex][lineDim_1] = fixedValue
                                 line_1[pointIndex][3 - lineDim_1] = fixedValue
                                 --line_1[3][2] = 1
                                 hasChange = true
                                 mergedLines[lineIndex_1] = true
                                 line_2[pointIndex_2][lineDim_2] = line_1[3 - pointIndex_1][lineDim_1]
                                 mergedLineMap[lineIndex_1] = lineIndex_2
                              end
                           end
                        end
                     elseif lineDim_2 + lineDim_1 == 3 and line_2[3][2] == 2 then
                        local nearestPair, minDistance = utils.findNearestJunctionPair(line_1, line_2, gap, false)
                        if minDistance <= gap then
                           local pointIndex_1 = nearestPair[1]
                           local pointIndex_2 = nearestPair[2]
                           --print(lineIndex_1 .. ' ' .. lineIndex_2)
                           if pointIndex_1 > 0 and pointIndex_2 > 0 then
                              local fixedValue_2 = (line_2[1][3 - lineDim_2] + line_2[2][3 - lineDim_2]) / 2
                              --local fixedValue = (fixedValue_1 + fixedValue_2) / 2
                              --local fixedValue = fixedValue_1
                              line_1[pointIndex_1][lineDim_1] = fixedValue_2
                              --line_2[pointIndex_2][lineDim_2] = fixedValue_1
                              mergedLines[lineIndex_1] = true
                              --line_2[3][2] = 1
                           end
                        end
                     end
                  end
               end
            end
         end
      end
      if hasChange == false then
         break
      end
   end

   local newLines = {}
   for lineIndex, line in pairs(lines) do
      line[3][2] = 1
      if not mergedLineMap[lineIndex] then
         table.insert(newLines, line)
      end
   end

   return newLines
end

function utils.fixedDoors(lines, walls, gap)
   for lineIndex_1, line_1 in pairs(lines) do
      local lineDim = utils.lineDim(line_1)
      if lineDim > 0 then
         local fixedValue_1 = (line_1[1][3 - lineDim] + line_1[2][3 - lineDim]) / 2
         local doorFixed = false
         for lineIndex_2, line_2 in pairs(walls) do
            if utils.lineDim(line_2) == lineDim then
               local fixedValue_2 = (line_2[1][3 - lineDim] + line_2[2][3 - lineDim]) / 2
               if math.abs(fixedValue_2 - fixedValue_1) <= gap and math.min(line_1[1][lineDim], line_1[2][lineDim]) >= math.min(line_2[1][lineDim], line_2[2][lineDim]) - gap and math.max(line_1[1][lineDim], line_1[2][lineDim]) <= math.max(line_2[1][lineDim], line_2[2][lineDim]) + gap then
                  for c = 1, 2 do
                     line_1[c][3 - lineDim] = fixedValue_2
                  end
                  doorFixed = true
               end
            end
         end
         if doorFixed == false then
            print('door: ' .. lineIndex_1 .. ' not fixed')
         end
      end
   end
   return lines
end

function utils.gridPoint(width, height, gridWidth, gridHeight, point)
   local cellWidth = width / gridWidth
   local cellHeight = height / gridHeight
   local gridX = math.floor((point[1] - 1) / cellWidth) + 1
   local gridY = math.floor((point[2] - 1) / cellHeight) + 1
   local cellX = ((point[1] - 1) - (gridX - 1) * cellWidth) / (cellWidth - 1)
   local cellY = ((point[2] - 1) - (gridY - 1) * cellHeight) / (cellHeight - 1)
   return {{gridX, gridY}, {cellX, cellY}}
end

function utils.gridRectangle(width, height, gridWidth, gridHeight, rectangle)
   --[[
      if point_2 == nil then
      local rectangle = utils.gridPoint(width, height, gridWidth, gridHeight, point_1)
      table.insert(rectangle, {0, 0})
      return rectangle
      end
   ]]--
   local point_1 = rectangle[1]
   local point_2 = rectangle[2]
   local center = utils.gridPoint(width, height, gridWidth, gridHeight, {(point_1[1] + point_2[1]) / 2, (point_1[2] + point_2[2]) / 2})
   local rectangle = center
   table.insert(rectangle, {(point_2[1] - point_1[1] + 1) / width, (point_2[2] - point_1[2] + 1) / height})
   return rectangle
end

function utils.imageRectangle(width, height, gridWidth, gridHeight, rectangle)
   local cellWidth = width / gridWidth
   local cellHeight = height / gridHeight
   local centerX = (rectangle[1][1] - 1) * cellWidth + rectangle[2][1] * (cellWidth - 1) + 1
   local centerY = (rectangle[1][2] - 1) * cellHeight + rectangle[2][2] * (cellHeight - 1) + 1
   return {{math.max(torch.round(centerX - (rectangle[3][1] * (width - 1)) / 2), 1), math.max(torch.round(centerY - (rectangle[3][2] * (height - 1)) / 2), 1)}, {math.min(torch.round(centerX + (rectangle[3][1] * (width - 1)) / 2), width), math.min(torch.round(centerY + (rectangle[3][2] * (height - 1)) / 2), height)}}
end

function utils.pointsToLines(width, height, points, lineWidth, divideLines, minLineLength, ordered, pointsDuplicated)
   local lineWidth = lineWidth or 5
   --local minLineLength = minLineLength or math.max(width, height)
   local minLineLength = minLineLength or lineWidth * 2
   local divideLines = divideLines or false

   local usedPointLineMask = {}
   local pointOrientations = {}
   for pointIndex, point in pairs(points) do
      usedPointLineMask[pointIndex] = {true, true, true, true}

      local orientations = {}
      local orientation = point[3][3]
      if point[3][2] == 1 then
         table.insert(orientations, (orientation + 2 - 1) % 4 + 1)
      elseif point[3][2] == 2 then
         table.insert(orientations, orientation)
         table.insert(orientations, (orientation + 3 - 1) % 4 + 1)
      elseif point[3][2] == 3 then
         if divideLines then
            for i = 1, 4 do
               if i ~= orientation then
                  table.insert(orientations, i)
               end
            end
         else
            table.insert(orientations, (orientation + 2 - 1) % 4 + 1)
         end
      else
         if divideLines then
            for i = 1, 4 do
               table.insert(orientations, i)
            end
         end
      end
      pointOrientations[pointIndex] = orientations
      for _, orientation in pairs(orientations) do
         usedPointLineMask[pointIndex][orientation] = false
      end
   end

   local lines = {}
   local lineJunctionsMap = {}
   for pointIndex, point in pairs(points) do
      local orientations = pointOrientations[pointIndex]

      local x = point[1][1]
      local y = point[1][2]
      for _, orientation in pairs(orientations) do
         if usedPointLineMask[pointIndex][orientation] == false then
            local lineDim
            local fixedValue
            local junction
            local startPoint
            if orientation == 1 or orientation == 3 then
               lineDim = 2
               fixedValue = x
               startPoint = y
               if orientation == 1 then
                  junction = 1
               else
                  junction = height
               end
            else
               lineDim = 1
               fixedValue = y
               startPoint = x
               if orientation == 4 then
                  junction = 1
               else
                  junction = width
               end
            end
            local orientationOpposite = (orientation + 2 - 1) % 4 + 1
            local selectedOtherPointIndex
            for otherPointIndex, otherPoint in pairs(points) do
               if otherPointIndex ~= pointIndex and usedPointLineMask[otherPointIndex][orientationOpposite] == false and (not ordered or otherPointIndex == pointIndex + 1) then
                  local otherXY = otherPoint[1]
                  if otherXY[lineDim] > math.min(junction, startPoint) and otherXY[lineDim] < math.max(junction, startPoint) and otherXY[3 - lineDim] >= fixedValue - lineWidth and otherXY[3 - lineDim] <= fixedValue + lineWidth then
                     junction = otherXY[lineDim]
                     selectedOtherPointIndex = otherPointIndex
                  end
               end
            end

            local point_1 = {}
            point_1[lineDim] = math.min(startPoint, junction)
            point_1[3 - lineDim] = fixedValue
            local point_2 = {}
            point_2[lineDim] = math.max(startPoint, junction)
            point_2[3 - lineDim] = fixedValue

            if point_1[1] ~= 1 and point_1[1] ~= width and point_1[2] ~= 1 and point_1[2] ~= height and point_2[1] ~= 1 and point_2[1] ~= width and point_2[2] ~= 1 and point_2[2] ~= height then
               if utils.calcDistance(point_1, point_2) > minLineLength then
                  table.insert(lines, {point_1, point_2, {"wall", 1, 1}})
                  if startPoint < junction then
                     table.insert(lineJunctionsMap, {pointIndex, selectedOtherPointIndex})
                  else
                     table.insert(lineJunctionsMap, {selectedOtherPointIndex, pointIndex})
                  end
                  if not pointsDuplicated then
                     if selectedOtherPointIndex ~= nil then
                        usedPointLineMask[selectedOtherPointIndex][orientationOpposite] = true
                     end
                     usedPointLineMask[pointIndex][orientation] = true
                  end
                  --print(pointIndex .. ' ' .. orientation .. ' ' .. selectedOtherPointIndex)
               end
            end
         end
      end
   end
   if pointsDuplicated then
      local newLines = {}
      local newLineJunctionsMap = {}
      local pointNeighborMap = {}
      for _, line in pairs(lines) do
         local junctions = lineJunctionsMap[_]
         if not pointNeighborMap[junctions[1]] then
            pointNeighborMap[junctions[1]] = {}
         end
         if not pointNeighborMap[junctions[1]][junctions[2]] then
            table.insert(newLines, line)
            table.insert(newLineJunctionsMap, junctions)
            pointNeighborMap[junctions[1]][junctions[2]] = true
         end
      end
      lines = newLines
      lineJunctionsMap = newLineJunctionsMap
   end

   return lines, lineJunctionsMap
end

function utils.linesToPoints(width, height, lines, lineWidth)
   local lineWidth = lineWidth or 5
   local points = {}
   local usedLinePointMask = {}
   for lineIndex, line in pairs(lines) do
      usedLinePointMask[lineIndex] = {false, false}
   end

   for lineIndex_1, line_1 in pairs(lines) do
      local lineDim_1 = utils.lineDim(line_1)
      if lineDim_1 > 0 then
         local fixedValue_1 = (line_1[1][3 - lineDim_1] + line_1[2][3 - lineDim_1]) / 2
         for lineIndex_2, line_2 in pairs(lines) do
            if lineIndex_2 > lineIndex_1 then
               local lineDim_2 = utils.lineDim(line_2)
               if lineDim_2 + lineDim_1 == 3 then
                  local fixedValue_2 = (line_2[1][3 - lineDim_2] + line_2[2][3 - lineDim_2]) / 2
                  local nearestPair, minDistance = utils.findNearestJunctionPair(line_1, line_2, lineWidth)

                  if minDistance <= lineWidth then
                     local pointIndex_1 = nearestPair[1]
                     local pointIndex_2 = nearestPair[2]
                     if pointIndex_1 > 0 and pointIndex_2 > 0 then
                        local point = {}
                        point[lineDim_1] = fixedValue_2
                        point[lineDim_2] = fixedValue_1
                        local side = {}
                        side[lineDim_1] = line_1[3 - pointIndex_1][lineDim_1] - fixedValue_2
                        side[lineDim_2] = line_2[3 - pointIndex_2][lineDim_2] - fixedValue_1
                        if side[1] < 0 and side[2] < 0 then
                           table.insert(points, {point, point, {'point', 2, 1}})
                        elseif side[1] > 0 and side[2] < 0 then
                           table.insert(points, {point, point, {'point', 2, 2}})
                        elseif side[1] > 0 and side[2] > 0 then
                           table.insert(points, {point, point, {'point', 2, 3}})
                        elseif side[1] < 0 and side[2] > 0 then
                           table.insert(points, {point, point, {'point', 2, 4}})
                        end
                        usedLinePointMask[lineIndex_1][pointIndex_1] = true
                        usedLinePointMask[lineIndex_2][pointIndex_2] = true
                     elseif (pointIndex_1 > 0 and pointIndex_2 == 0) or (pointIndex_1 == 0 and pointIndex_2 > 0) then
                        local lineDim
                        local pointIndex
                        local fixedValue
                        local pointValue
                        if pointIndex_1 > 0 then
                           lineDim = lineDim_1
                           pointIndex = pointIndex_1
                           fixedValue = fixedValue_2
                           pointValue = line_1[pointIndex_1][3 - lineDim_1]
                           usedLinePointMask[lineIndex_1][pointIndex_1] = true
                        else
                           lineDim = lineDim_2
                           pointIndex = pointIndex_2
                           fixedValue = fixedValue_1
                           pointValue = line_2[pointIndex_2][3 - lineDim_2]
                           usedLinePointMask[lineIndex_2][pointIndex_2] = true
                        end
                        local point = {}
                        point[lineDim] = fixedValue
                        point[3 - lineDim] = pointValue

                        if pointIndex == 1 then
                           if lineDim == 1 then
                              table.insert(points, {point, point, {'point', 3, 4}})
                           else
                              table.insert(points, {point, point, {'point', 3, 1}})
                           end
                        else
                           if lineDim == 1 then
                              table.insert(points, {point, point, {'point', 3, 2}})
                           else
                              table.insert(points, {point, point, {'point', 3, 3}})
                           end
                        end
                     end
                  elseif line_1[1][lineDim_1] < fixedValue_2 and line_1[2][lineDim_1] > fixedValue_2 and line_2[1][lineDim_2] < fixedValue_1 and line_2[2][lineDim_2] > fixedValue_1 then
                     local point = {}
                     point[lineDim_1] = fixedValue_2
                     point[lineDim_2] = fixedValue_1
                     table.insert(points, {point, point, {'point', 4, 1}})
                  end
               end
            end
         end
      end
   end
   for lineIndex, pointMask in pairs(usedLinePointMask) do
      local lineDim = utils.lineDim(lines[lineIndex])
      for pointIndex = 1, 2 do
         if pointMask[pointIndex] == false then
            local point = {lines[lineIndex][pointIndex][1], lines[lineIndex][pointIndex][2]}
            if pointIndex == 1 then
               if lineDim == 1 then
                  table.insert(points, {point, point, {'point', 1, 4}})
               elseif lineDim == 2 then
                  table.insert(points, {point, point, {'point', 1, 1}})
               end
            else
               if lineDim == 1 then
                  table.insert(points, {point, point, {'point', 1, 2}})
               elseif lineDim == 2 then
                  table.insert(points, {point, point, {'point', 1, 3}})
               end
            end
         end
      end
   end
   return points
end

function utils.convertRepresentationToGeneral(width, height, representation, representationType, lineWidth)
   local representationGeneral = {}
   if representationType == 'P' then

      representationGeneral.walls = utils.pointsToLines(width, height, representation.points, lineWidth)

      local lineMask = torch.zeros(height, width)
      for _, line in pairs(representationGeneral.walls) do
         local lineDim = utils.lineDim(line)
         if lineDim > 0 then
            local maxSize = {width, height}
            local rectangle = {{}, {}}
            rectangle[1][lineDim] = math.min(line[1][lineDim], line[2][lineDim])
            rectangle[2][lineDim] = math.max(line[1][lineDim], line[2][lineDim])
            rectangle[1][3 - lineDim] = math.max((line[1][3 - lineDim] + line[2][3 - lineDim]) / 2 - lineWidth, 1)
            rectangle[2][3 - lineDim] = math.min((line[1][3 - lineDim] + line[2][3 - lineDim]) / 2 + lineWidth, maxSize[3 - lineDim])

            --[[
               for pointIndex = 1, 2 do
               for c = 1, 2 do
               print(rectangle[pointIndex][c])
               end
               end
               print(#lineMask)
            ]]--

            --representationImage[{{}, {rectangle[1][2], rectangle[2][2]}, {rectangle[1][1], rectangle[2][1]}}] = 0
            lineMask[{{rectangle[1][2], rectangle[2][2]}, {rectangle[1][1], rectangle[2][1]}}] = 1
            --success, newRepresentationImage = pcall(function() return image.drawRect(representationImage, rectangle[1][1], rectangle[1][2], rectangle[2][1], rectangle[2][2], {lineWidth = lineWidth, color = {0, 0, 0}}) end)
            --if success then
            --representationImage = newRepresentationImage
            --end
         end
         --representationImage[{{}, {minX, maxX}, {minY, maxY}}] = 0
      end

      for mode, items in pairs(representation) do
         if mode == 'doors' or mode == 'icons' or mode == 'labels' then
            for __, item in pairs(items) do
               --print(mode)
               --print(item)
               --local iconImage = iconImages[item[3][1]][item[3][2]]
               if mode == 'icons' then
                  local orientation = 1
                  local rectangle = {item[1], item[2]}
                  if (math.abs(rectangle[2][1] - rectangle[1][1]) >= math.abs(rectangle[2][2] - rectangle[1][2]) and (item[3][1] ~= 'toilet' and item[3][1] ~= 'stairs')) or (math.abs(rectangle[2][1] - rectangle[1][1]) <= math.abs(rectangle[2][2] - rectangle[1][2]) and (item[3][1] == 'toilet' or item[3][1] == 'stairs')) then
                     local min = math.min(rectangle[1][2], rectangle[2][2])
                     local max = math.max(rectangle[1][2], rectangle[2][2])
                     local center = (rectangle[1][1] + rectangle[2][1]) / 2
                     local deltaMin = 0
                     for delta = 1, min - 1 do
                        deltaMin = delta
                        if lineMask[min - delta][center] == 1 then
                           break
                        end
                     end
                     local deltaMax = 0
                     for delta = 1, height - max do
                        deltaMax = delta
                        if lineMask[max + delta][center] == 1 then
                           break
                        end
                     end
                     if deltaMin > deltaMax then
                        orientation = 1
                     else
                        orientation = 3
                     end
                  else
                     local min = math.min(rectangle[1][1], rectangle[2][1])
                     local max = math.max(rectangle[1][1], rectangle[2][1])
                     local center = (rectangle[1][2] + rectangle[2][2]) / 2
                     local deltaMin = 0
                     for delta = 1, min - 1 do
                        deltaMin = delta
                        if lineMask[center][min - delta] == 1 then
                           break
                        end
                     end
                     local deltaMax = 0
                     for delta = 1, width - max do
                        deltaMax = delta
                        if lineMask[center][max + delta] == 1 then
                           break
                        end
                     end
                     if deltaMin > deltaMax then
                        orientation = 4
                     else
                        orientation = 2
                     end
                  end
                  --[[
                     print(item[3][1])
                     print(math.abs(rectangle[2][1] - rectangle[1][1]))
                     print(math.abs(rectangle[2][2] - rectangle[1][2]))
                     print(orientation)
                  ]]--
                  item[3][3] = orientation
               elseif mode == 'doors' then
                  local lineDim
                  if math.abs(item[2][1] - item[1][1]) > math.abs(item[2][2] - item[1][2]) then
                     item[3][3] = 1
                     lineDim = 1
                  else
                     item[3][3] = 2
                     lineDim = 2
                  end
                  local fixedValue = (item[1][3 - lineDim] + item[2][3 - lineDim]) / 2
                  item[1][3 - lineDim] = fixedValue
                  item[2][3 - lineDim] = fixedValue
               else
                  item[3][3] = 1
               end

               if mode ~= 'doors' then
                  item[2][1] = math.max(item[2][1] - item[1][1], 30) + item[1][1]
                  item[2][2] = math.max(item[2][2] - item[1][2], 30) + item[1][2]
               end


               --[[
                  iconImage = rotateIcon(iconImage, orientation)

                  local icon = image.scale(iconImage, rectangle[2][1] - rectangle[1][1] + 1, rectangle[2][2] - rectangle[1][2] + 1)
                  if icon:dim() == 2 then
                  icon = icon:repeatTensor(3, 1, 1)
                  end
               ]]--

               --print(rectangle)
               --print(#icon)
               --print(#representationImage[{{}, {rectangle[1][2], rectangle[2][2]}, {rectangle[1][1], rectangle[2][1]}}])
               --representationImage[{{}, {rectangle[1][2], rectangle[2][2]}, {rectangle[1][1], rectangle[2][1]}}] = icon
            end
            representationGeneral[mode] = items
         end
      end
   end
   return representationGeneral
end

function utils.convertRepresentation(width, height, representationGeneral, representationType, lineWidth)
   local representation = {}
   if representationType == 'P' then
      representationGeneral.walls = utils.mergeLines(representationGeneral.walls, lineWidth)

      representation.points = utils.linesToPoints(width, height, representationGeneral.walls, lineWidth)
      representation.doors = representationGeneral.doors
      representation.icons = representationGeneral.icons
      representation.labels = representationGeneral.labels
   end
   return representation
end

function utils.globalToGrid(width, height, gridWidth, gridHeight, representationGlobal)
   local representation = {}
   for mode, items in pairs(representationGlobal) do
      representation[mode] = {}
      for _, item in pairs(items) do
         local newRectangle = utils.gridRectangle(width, height, gridWidth, gridHeight, item)
         table.insert(newRectangle, item[3])
         if newRectangle[1][1] >= 1 and newRectangle[1][1] <= gridWidth and newRectangle[1][2] >= 1 and newRectangle[1][2] <= gridHeight then
            table.insert(representation[mode], newRectangle)
         end
      end
   end
   return representation
end

function utils.gridToGlobal(width, height, gridWidth, gridHeight, representation)
   local representationGlobal = {}
   for mode, items in pairs(representation) do
      representationGlobal[mode] = {}
      for _, item in pairs(items) do
         local newRectangle = utils.imageRectangle(width, height, gridWidth, gridHeight, item)
         table.insert(newRectangle, item[4])

         --print(mode)
         --print(item)
         --print(newRectangle)

         table.insert(representationGlobal[mode], newRectangle)
      end
   end
   --os.exit(1)
   return representationGlobal
end

function utils.convertRepresentationToTensor(width, height, gridWidth, gridHeight, representationGlobal)
   local representation = utils.globalToGrid(width, height, gridWidth, gridHeight, representationGlobal)

   local offsetsBB = utils.offsetsBB()
   local offsetsClass = utils.offsetsClass()
   local numFeaturesBB = utils.numFeaturesBB()
   local numFeaturesClass = utils.numFeaturesClass()
   local numItemsPerCell = utils.numItemsPerCell()
   local numFeaturesPerItem = utils.numFeaturesPerItem()

   local representationTensor = torch.zeros(numFeaturesBB + numFeaturesClass, gridHeight, gridWidth)
   local gridItems = {}
   for y = 1, gridHeight do
      gridItems[y] = {}
      for x = 1, gridWidth do
         gridItems[y][x] = {}
         for mode, offset in pairs(offsetsBB) do
            gridItems[y][x][mode] = {}
         end
      end
   end
   for mode, items in pairs(representation) do
      for __, item in pairs(items) do
         --if gridItems[item[1][2]][item[1][1]][mode] ~= nil then
         table.insert(gridItems[item[1][2]][item[1][1]][mode], item)
         --end
      end
   end

   for x = 1, gridWidth do
      for y = 1, gridHeight do
         for mode, items in pairs(gridItems[y][x]) do
            local numFeatures = numFeaturesPerItem[mode]
            local sortedItems = {}
            for _, item in pairs(items) do
               table.insert(sortedItems, {item[2][1] + item[2][2], item})
            end
            table.sort(sortedItems, function(a, b) return a[1] < b[1] end)
            for i = numItemsPerCell[mode] + 1, #sortedItems do
               table.remove(sortedItems)
            end

            local offsetBB = offsetsBB[mode]
            for itemIndex, item in pairs(sortedItems) do
               item = item[2]
               local itemTensor = representationTensor[{{offsetBB + (itemIndex - 1) * numFeatures + 1, offsetBB + (itemIndex - 1) * numFeatures + numFeatures}, y, x}]
               itemTensor[1] = item[2][1]
               itemTensor[2] = item[2][2]
               itemTensor[3] = item[3][1]
               itemTensor[4] = item[3][2]
               itemTensor[5] = 1
            end
            local offsetClass = offsetsClass[mode]
            for itemIndex, item in pairs(sortedItems) do
               item = item[2]
               local class = utils.getNumber(mode, item[4])
               representationTensor[{offsetClass + itemIndex, y, x}] = class
            end
         end
      end
   end
   return representationTensor
end

function utils.convertRepresentationToTensorAnchor(width, height, gridWidth, gridHeight, representationGlobal, confidenceThreshold)

   local confidenceThreshold = confidenceThreshold or 0.7
   local cellWidth = width / gridWidth
   local cellHeight = height / gridHeight

   local anchorBoxesMap = utils.getAnchorBoxesMap(cellWidth, cellHeight)

   local anchorBoxesTensors = {}

   for mode, items in pairs(representationGlobal) do
      local anchorBoxes = anchorBoxesMap[mode]
      local numAnchorBoxes = #anchorBoxes
      local anchorBoxesTensor = torch.zeros(gridHeight, gridWidth, numAnchorBoxes, 6)

      for __, item in pairs(items) do
         local point_1 = item[1]
         local point_2 = item[2]
         local label = utils.getNumber(mode, item[3])

         local center = {(point_1[1] + point_2[1]) / 2, (point_1[2] + point_2[2]) / 2}
         local gridX = math.floor((center[1] - 1) / cellWidth) + 1
         local gridY = math.floor((center[2] - 1) / cellHeight) + 1
         if gridX >= 1 and gridX <= gridWidth and gridY >= 1 and gridY <= gridHeight then
            local cellX = (center[1] - 1) - (gridX - 1) * cellWidth
            local cellY = (center[2] - 1) - (gridY - 1) * cellHeight

            local gridBox = {{cellX, cellY}, {math.abs(point_2[1] - point_1[1]), math.abs(point_2[2] - point_1[2])}}

            if mode == 'labels' then
               gridBox[2] = {0, 0}
            end
            for c = 1, 2 do
               gridBox[2][c] = math.max(gridBox[2][c], 1)
            end

            local gridAnchorBoxesTensor = torch.zeros(numAnchorBoxes, 5)

            for anchorBoxIndex, anchorBox in pairs(anchorBoxes) do

               if mode ~= 'points' or anchorBoxIndex == label then

                  local IOU = utils.calcIOU({{anchorBox[1][1] - anchorBox[2][1] / 2, anchorBox[1][2] - anchorBox[2][2] / 2}, {anchorBox[1][1] + anchorBox[2][1] / 2, anchorBox[1][2] + anchorBox[2][2] / 2}}, {{gridBox[1][1] - gridBox[2][1] / 2, gridBox[1][2] - gridBox[2][2] / 2}, {gridBox[1][1] + gridBox[2][1] / 2, gridBox[1][2] + gridBox[2][2] / 2}})

                  --[[
                     print(IOU)
                     print(gridY)
                     for index = 1, 2 do
                     for c = 1, 2 do
                     print(gridBox[index][c])
                     end
                     end
                     for index = 1, 2 do
                     for c = 1, 2 do
                     print(anchorBox[index][c])
                     end
                     end]]--

                  --assert(IOU >= 0 and IOU <= 1)
                  if IOU >= 0 and IOU <= 1 then
                     gridAnchorBoxesTensor[anchorBoxIndex][5] = IOU
                     for c = 1, 2 do
                        gridAnchorBoxesTensor[anchorBoxIndex][c] = (gridBox[1][c] - anchorBox[1][c]) / anchorBox[2][c]
                        gridAnchorBoxesTensor[anchorBoxIndex][c + 2] = math.log(gridBox[2][c] / anchorBox[2][c])
                     end
                  end
               end
            end

            --[[
               print('done')
               print(gridAnchorBoxesTensor)
               print(gridBox)
               print(anchorBox)
               os.exit(1)
            ]]--

            local maxIOU
            local maxIOUIndex
            for anchorBoxIndex = 1, gridAnchorBoxesTensor:size(1) do
               local IOU = gridAnchorBoxesTensor[anchorBoxIndex][5]
               if gridY <= 0 or gridY > 8 or gridX <= 0 or gridX > 8 or anchorBoxIndex <= 0 or anchorBoxIndex > numAnchorBoxes then
                  print(gridY .. ' ' .. gridX .. ' ' .. anchorBoxIndex)
                  for index = 1, 2 do
                     for c = 1, 2 do
                        print(item[index][c])
                     end
                  end
                  for c = 1, 3 do
                     print(item[3][c])
                  end
               end

               if IOU > anchorBoxesTensor[gridY][gridX][anchorBoxIndex][5] then
                  anchorBoxesTensor[gridY][gridX][anchorBoxIndex][{{1, 5}}] = gridAnchorBoxesTensor[anchorBoxIndex]
                  if IOU > confidenceThreshold then
                     anchorBoxesTensor[gridY][gridX][anchorBoxIndex][6] = label
                  end
               end
               if not maxIOU or IOU > maxIOU then
                  maxIOUIndex = anchorBoxIndex
                  maxIOU = IOU
               end
            end
            if maxIOU < confidenceThreshold then
               if maxIOU < 0.3 and false then
                  print(centerX)
                  print(centerY)
                  print(gridX)
                  print(gridY)
                  for index = 1, 2 do
                     for c = 1, 2 do
                        print(gridBox[index][c])
                     end
                  end
                  print(maxIOU)
                  print(maxIOUIndex)
                  print(gridWidth)
                  print(gridHeight)
                  os.exit(1)
               end
               anchorBoxesTensor[gridY][gridX][maxIOUIndex][6] = label
            end
         end
      end
      anchorBoxesTensors[mode] = anchorBoxesTensor
   end
   local representationTensor
   local sortedModes = utils.getSortedModes()
   for _, mode in pairs(sortedModes) do
      local anchorBoxesTensor = anchorBoxesTensors[mode]
      if not representationTensor then
         representationTensor = anchorBoxesTensor
      else
         representationTensor = torch.cat(representationTensor, anchorBoxesTensor, 3)
      end
   end
   return representationTensor
end

function utils.getHeatmapsStyless(width, height, representation, lineWidth, kernelSize)
   representation.walls = utils.mergeLines(representation.walls, lineWidth)
   representation.points = utils.linesToPoints(width, height, representation.walls, lineWidth)

   --local kernelSize = kernelSize or torch.round(7.0 * math.max(width, height) / 256)
   local kernelSize = kernelSize or 13

   local heatmaps = torch.zeros(13 + 4 + 4, height, width)
   for mode, items in pairs(representation) do
      if mode == 'points' then
         for _, item in pairs(items) do
            local x = torch.round(item[1][1])
            local y = torch.round(item[1][2])
            local label = utils.getNumber(mode, item[3])

            if x >= 1 and x <= width and y >= 1 and y <= height then
               heatmaps[label][y][x] = 1
            end
         end
      elseif mode == 'doors' then
         for _, item in pairs(items) do
            local lineDim = utils.lineDim(item)
            if lineDim > 0 then

               local x = torch.round(math.min(item[1][1], item[2][1]))
               local y = torch.round(math.min(item[1][2], item[2][2]))
               if x >= 1 and x <= width and y >= 1 and y <= height then
                  heatmaps[13 + (lineDim - 1) * 2 + 1][y][x] = 1
               end
               local x = torch.round(math.max(item[1][1], item[2][1]))
               local y = torch.round(math.max(item[1][2], item[2][2]))
               if x >= 1 and x <= width and y >= 1 and y <= height then
                  heatmaps[13 + (lineDim - 1) * 2 + 2][y][x] = 1
               end
            end
         end
      elseif mode == 'icons' then
         for _, item in pairs(items) do
            local lineDim = utils.lineDim(item)

            local x = torch.round(math.min(item[1][1], item[2][1]))
            local y = torch.round(math.min(item[1][2], item[2][2]))
            if x >= 1 and x <= width and y >= 1 and y <= height then
               heatmaps[13 + 4 + 1][y][x] = 1
            end
            local x = torch.round(math.max(item[1][1], item[2][1]))
            local y = torch.round(math.min(item[1][2], item[2][2]))
            if x >= 1 and x <= width and y >= 1 and y <= height then
               heatmaps[13 + 4 + 2][y][x] = 1
            end
            local x = torch.round(math.min(item[1][1], item[2][1]))
            local y = torch.round(math.max(item[1][2], item[2][2]))
            if x >= 1 and x <= width and y >= 1 and y <= height then
               heatmaps[13 + 4 + 3][y][x] = 1
            end
            local x = torch.round(math.max(item[1][1], item[2][1]))
            local y = torch.round(math.max(item[1][2], item[2][2]))
            if x >= 1 and x <= width and y >= 1 and y <= height then
               heatmaps[13 + 4 + 4][y][x] = 1
            end
         end
      end
   end

   --kernelSize = torch.round(1.0 * kernelSize * math.max(width, height) / 256)
   local kernel = image.gaussian(kernelSize)
   --local kernel = image.gaussian(nil, nil, nil, nil, torch.round(1.0 * kernelSize * width / 256), torch.round(1.0 * kernelSize * height / 256))

   for i = 1, heatmaps:size(1) do
      heatmaps[i] = image.convolve(heatmaps[i], kernel, 'same')
   end
   return heatmaps
end

function utils.getHeatmaps(width, height, representation, lineWidth, kernelSize)
   representation.points = utils.linesToPoints(width, height, representation.walls, lineWidth)

   local kernelSize = kernelSize or torch.round(7.0 * math.max(width, height) / 256)
   local heatmaps = torch.zeros(13 * (1 + 4 + 4), height, width)
   for mode, items in pairs(representation) do
      if mode == 'points' then
         for _, item in pairs(items) do
            local x = torch.round(item[1][1])
            local y = torch.round(item[1][2])
            local label = utils.getNumber(mode, item[3])

            if x >= 1 and x <= width and y >= 1 and y <= height then
               heatmaps[label][y][x] = 1
            end
         end
      elseif mode == 'doors' then
         for _, item in pairs(items) do
            local lineDim = utils.lineDim(item)
            if lineDim > 0 then
               local label = utils.getNumber(mode, item[3])

               local x = torch.round(math.min(item[1][1], item[2][1]))
               local y = torch.round(math.min(item[1][2], item[2][2]))
               if x >= 1 and x <= width and y >= 1 and y <= height then
                  heatmaps[13 + (label - 1) * 4 + (lineDim - 1) * 2 + 1][y][x] = 1
               end
               local x = torch.round(math.max(item[1][1], item[2][1]))
               local y = torch.round(math.max(item[1][2], item[2][2]))
               if x >= 1 and x <= width and y >= 1 and y <= height then
                  heatmaps[13 + (label - 1) * 4 + (lineDim - 1) * 2 + 2][y][x] = 1
               end
            end
         end
      elseif mode == 'icons' then
         for _, item in pairs(items) do
            local lineDim = utils.lineDim(item)
            local label = utils.getNumber(mode, item[3])

            local x = torch.round(math.min(item[1][1], item[2][1]))
            local y = torch.round(math.min(item[1][2], item[2][2]))
            if x >= 1 and x <= width and y >= 1 and y <= height then
               heatmaps[13 * 5 + (label - 1) * 4 + 1][y][x] = 1
            end
            local x = torch.round(math.max(item[1][1], item[2][1]))
            local y = torch.round(math.min(item[1][2], item[2][2]))
            if x >= 1 and x <= width and y >= 1 and y <= height then
               heatmaps[13 * 5 + (label - 1) * 4 + 2][y][x] = 1
            end
            local x = torch.round(math.min(item[1][1], item[2][1]))
            local y = torch.round(math.max(item[1][2], item[2][2]))
            if x >= 1 and x <= width and y >= 1 and y <= height then
               heatmaps[13 * 5 + (label - 1) * 4 + 3][y][x] = 1
            end
            local x = torch.round(math.max(item[1][1], item[2][1]))
            local y = torch.round(math.max(item[1][2], item[2][2]))
            if x >= 1 and x <= width and y >= 1 and y <= height then
               heatmaps[13 * 5 + (label - 1) * 4 + 4][y][x] = 1
            end
         end
      end
   end

   local kernel = image.gaussian(kernelSize)
   heatmaps = image.convolve(heatmaps, kernel, 'same')

   return heatmaps
end

function utils.getJunctionHeatmap(width, height, representationGlobal, kernelSize)

   local kernelSize = kernelSize or 7
   local heatmaps = torch.zeros(13, height, width)
   for mode, items in pairs(representationGlobal) do
      if mode == 'points' then
         for _, item in pairs(representationGlobal.points) do
            local x = torch.round(item[1][1])
            local y = torch.round(item[1][2])
            local label = utils.getNumber('points', item[3])

            if x >= 1 and x <= width and y >= 1 and y <= height then
               heatmaps[label][y][x] = 1
            end
         end
      end
   end
   local kernel = image.gaussian(kernelSize)
   for i = 1, heatmaps:size(1) do
      heatmaps[i] = image.convolve(heatmaps[i], kernel, 'same')
   end
   return heatmaps
end

function utils.convertTensorAnchorToRepresentation(width, height, representationTensor, confidenceThreshold)
   local confidenceThreshold = confidenceThreshold or 0.7
   local gridWidth = representationTensor:size(2)
   local gridHeight = representationTensor:size(1)
   local cellWidth = width / gridWidth
   local cellHeight = height / gridHeight

   local anchorBoxesMap = utils.getAnchorBoxesMap(cellWidth, cellHeight)

   local anchorBoxesTensors = {}
   local offset = 1
   local sortedModes = utils.getSortedModes()
   for _, mode in pairs(sortedModes) do
      local anchorBoxes = anchorBoxesMap[mode]
      anchorBoxesTensors[mode] = representationTensor:narrow(3, offset, #anchorBoxes)
      offset = offset + #anchorBoxes
   end
   --print(anchorBoxesTensors['points'])

   local representation = {}
   for mode, anchorBoxesTensor in pairs(anchorBoxesTensors) do
      representation[mode] = {}
      local anchorBoxes = anchorBoxesMap[mode]
      local numAnchorBoxes = #anchorBoxes

      for gridX = 1, gridWidth do
         for gridY = 1, gridHeight do
            for anchorBoxIndex = 1, numAnchorBoxes do
               if anchorBoxesTensor[gridY][gridX][anchorBoxIndex][5] > confidenceThreshold then
                  --print(mode)
                  --print(anchorBoxesTensor[gridY][gridX][anchorBoxIndex])
                  local gridBox = anchorBoxesTensor[gridY][gridX][anchorBoxIndex][{{1, 4}}]
                  local anchorBox = anchorBoxes[anchorBoxIndex]
                  local centerX = anchorBox[1][1] + gridBox[1] * anchorBox[2][1] + (gridX - 1) * cellWidth
                  local centerY = anchorBox[1][2] + gridBox[2] * anchorBox[2][2] + (gridY - 1) * cellHeight
                  local boxWidth = math.exp(gridBox[3]) * anchorBox[2][1]
                  local boxHeight = math.exp(gridBox[4]) * anchorBox[2][2]

                  local x_1 = math.min(math.max(torch.round(centerX - boxWidth / 2), 1), width)
                  local y_1 = math.min(math.max(torch.round(centerY - boxHeight / 2), 1), height)
                  local x_2 = math.max(math.min(torch.round(centerX + boxWidth / 2), width), 1)
                  local y_2 = math.max(math.min(torch.round(centerY + boxHeight / 2), height), 1)

                  local label = anchorBoxesTensor[gridY][gridX][anchorBoxIndex][6]
                  local itemInfo = utils.getItemInfo(mode, label)

                  if not itemInfo then
                     print('cannot find item info')
                     print(anchorBoxesTensor[gridY][gridX][anchorBoxIndex])
                     print(mode)
                     print(label)
                     os.exit(1)
                  end

                  local item = {{x_1, y_1}, {x_2, y_2}, itemInfo}
                  if mode == 'icons' or mode == 'doors' then
                     table.insert(item, anchorBoxesTensor[gridY][gridX][anchorBoxIndex][5])
                  end

                  table.insert(representation[mode], item)
               end
            end
         end
      end
   end

   representation.doors = utils.nms(representation.doors)
   representation.icons = utils.nms(representation.icons)
   return representation
end

function utils.nms(items, threshold)
   local nms = require 'nms'
   require 'cunn'
   --require 'cutorch'
   local threshold = threshold or 0
   local nameItemsMap = {}
   local nameItemsTensorMap = {}
   for _, item in pairs(items) do
      local itemTensor = torch.DoubleTensor({item[1][1], item[1][2], item[2][1], item[2][2], item[4]}):repeatTensor(1, 1)
      local name = item[3][1]
      if not nameItemsMap[name] then
         nameItemsTensorMap[name] = itemTensor
         nameItemsMap[name] = {item}
      else
         nameItemsTensorMap[name] = torch.cat(nameItemsTensorMap[name], itemTensor, 1)
         table.insert(nameItemsMap[name], item)
      end
   end
   local newItems = {}
   for name, itemsTensor in pairs(nameItemsTensorMap) do
      --print(name)
      --print(itemsTensor)
      local validIndices = nms.gpu_nms(itemsTensor:cuda(), threshold)
      --print(validIndices)
      for i = 1, validIndices:size(1) do
         local itemTensor = itemsTensor[validIndices[i]]
         local item = nameItemsMap[name][validIndices[i]]
         table.insert(newItems, {{itemTensor[1], itemTensor[2]}, {itemTensor[3], itemTensor[4]}, item[3]})
      end
   end
   return newItems
end

function utils.compressRepresentation(width, height, representationTensor)
   local offsetsBB = utils.offsetsBB()
   local offsetsClass = utils.offsetsClass()
   local numItemsPerCell = utils.numItemsPerCell()
   local numItemsGlobal = utils.numItemsGlobal()
   local numFeaturesPerItem = utils.numFeaturesPerItem()
   local numFeaturesBB = utils.numFeaturesBB()

   local gridWidth = representationTensor:size(3)
   local gridHeight = representationTensor:size(2)
   local confidenceThreshold = confidenceThreshold or 0.5

   local items = {}
   for x = 1, gridWidth do
      for y = 1, gridHeight do
         for mode, numItems in pairs(numItemsPerCell) do
            if mode == 'icons' or mode == 'labels' then
               local offsetBB = offsetsBB[mode]
               local offsetClass = offsetsClass[mode]
               local numFeatures = numFeaturesPerItem[mode]
               for itemIndex = 1, numItems do
                  local item = representationTensor[{{offsetBB + (itemIndex - 1) * numFeatures + 1, offsetBB + (itemIndex - 1) * numFeatures + numFeatures}, y, x}]

                  if item[5] > confidenceThreshold then
                     local class = representationTensor[{offsetClass + itemIndex, y, x}]
                     local name = utils.getItemInfo(mode, class)[1]
                     local newRectangle = utils.gridRectangle(width, height, 1, 1, utils.imageRectangle(width, height, gridWidth, gridHeight, {{x, y}, {item[1], item[2]}, {item[3], item[4]}}))
                     if items[name] == nil then
                        items[name] = {}
                     end
                     table.insert(items[name], torch.Tensor({newRectangle[2][1], newRectangle[2][2], newRectangle[3][1], newRectangle[3][2], item[5]}))
                  end
               end
            end
         end
      end
   end
   local totalNumItems = 0
   for _, num in pairs(numItemsGlobal) do
      totalNumItems = totalNumItems + num
   end
   local iconLabelTensor = torch.zeros(totalNumItems * 5)

   local offset = 0
   for name, numItems in pairs(numItemsGlobal) do
      if items[name] ~= nil then
         for itemIndex = 1, math.min(numItems, #items[name]) do
            iconLabelTensor[{{offset + (itemIndex - 1) * 5 + 1, offset + (itemIndex - 1) * 5 + 5}}] = items[name][itemIndex]
         end
      end
      offset = offset + numItems * 5
   end
   return {representationTensor[{{1, offsetsBB.icons}}], representationTensor[{{numFeaturesBB, offsetsClass.icons}}], iconLabelTensor:view(-1, 1, 1)}
end

function utils.uncompressRepresentation(width, height, representationTensors)
   local offsetsBB = utils.offsetsBB()
   local offsetsClass = utils.offsetsClass()
   local numItemsPerCell = utils.numItemsPerCell()
   local numItemsGlobal = utils.numItemsGlobal()
   local numFeaturesPerItem = utils.numFeaturesPerItem()
   local numFeaturesBB = utils.numFeaturesBB()
   local numFeaturesClass = utils.numFeaturesClass()
   local modeMap = utils.modeMap()

   local gridWidth = representationTensors[1]:size(3)
   local gridHeight = representationTensors[1]:size(2)
   local confidenceThreshold = confidenceThreshold or 0.5

   local iconLabelTensor = representationTensors[3]
   --local iconLabelTensorBB = torch.zeros(numFeaturesBB - offsetsBB.icons, gridHeight, gridWidth)
   --local iconLabelTensorClass = torch.zeros(numFeaturesClass + numFeaturesBB - offsetsClass.icons, gridHeight, gridWidth)
   local representationTensor = torch.zeros(numFeaturesBB + numFeaturesClass, gridHeight, gridWidth)
   representationTensor[{{1, offsetsBB.icons}}] = representationTensors[1]
   representationTensor[{{numFeaturesBB + 1, offsetsClass.icons}}] = representationTensors[2]

   local gridItems = {}
   for y = 1, gridHeight do
      gridItems[y] = {}
      for x = 1, gridWidth do
         gridItems[y][x] = {}
         for mode, offset in pairs(offsetsBB) do
            gridItems[y][x][mode] = {}
         end
      end
   end

   local offset = 0
   for name, numItems in pairs(numItemsGlobal) do
      local mode = modeMap[name]
      for itemIndex = 1, numItems do
         local item = iconLabelTensor[{{offset + (itemIndex - 1) * 5 + 1, offset + (itemIndex - 1) * 5 + 5}, 1, 1}]
         local newRectangle = utils.gridRectangle(width, height, gridWidth, gridWidth, utils.imageRectangle(width, height, 1, 1, {{1, 1}, {item[1], item[2]}, {item[3], item[4]}}))
         table.insert(newRectangle, {name, 1, 1})
         --print(item)
         --print(newRectangle)
         --print(mode)
         --print(name)
         if newRectangle[1][1] >= 1 and newRectangle[1][1] <= gridWidth and newRectangle[1][2] >= 1 and newRectangle[1][2] <= gridHeight then
            table.insert(gridItems[newRectangle[1][2]][newRectangle[1][1]][mode], {item[5], newRectangle})
         end
      end
      offset = offset + numItems * 5
   end

   for x = 1, gridWidth do
      for y = 1, gridHeight do
         for mode, items in pairs(gridItems[y][x]) do
            local numFeatures = numFeaturesPerItem[mode]
            local sortedItems = items
            table.sort(sortedItems, function(a, b) return a[1] > b[1] end)
            for i = numItemsPerCell[mode] + 1, #sortedItems do
               table.remove(sortedItems)
            end

            local offsetBB = offsetsBB[mode]
            for itemIndex, item in pairs(sortedItems) do
               item = item[2]
               local itemTensor = representationTensor[{{offsetBB + (itemIndex - 1) * numFeatures + 1, offsetBB + (itemIndex - 1) * numFeatures + numFeatures}, y, x}]
               itemTensor[1] = item[2][1]
               itemTensor[2] = item[2][2]
               itemTensor[3] = item[3][1]
               itemTensor[4] = item[3][2]
               itemTensor[5] = 1
            end
            local offsetClass = offsetsClass[mode]
            for itemIndex, item in pairs(sortedItems) do
               item = item[2]
               local class
               if mode == 'icons' then
                  class = utils.getNumber(mode, item[4])
               elseif mode == 'labels' then
                  class = utils.getNumber(mode, item[4])
               end
               representationTensor[{offsetClass + itemIndex, y, x}] = class
            end
         end
      end
   end

   return representationTensor
end


function utils.convertTensorToRepresentation(width, height, representationTensor, confidenceThreshold)
   local offsetsBB = utils.offsetsBB()
   local offsetsClass = utils.offsetsClass()
   local numItemsPerCell = utils.numItemsPerCell()
   local numFeaturesPerItem = utils.numFeaturesPerItem()

   local representation = {}
   representation.points = {}
   representation.doors = {}
   representation.icons = {}
   representation.labels = {}

   local gridWidth = representationTensor:size(3)
   local gridHeight = representationTensor:size(2)
   local confidenceThreshold = confidenceThreshold or 0.5

   for x = 1, gridWidth do
      for y = 1, gridHeight do
         for mode, numItems in pairs(numItemsPerCell) do
            local offsetBB = offsetsBB[mode]
            local offsetClass = offsetsClass[mode]
            local numFeatures = numFeaturesPerItem[mode]
            for itemIndex = 1, numItems do
               local item = representationTensor[{{offsetBB + (itemIndex - 1) * numFeatures + 1, offsetBB + (itemIndex - 1) * numFeatures + numFeatures}, y, x}]
               local class = representationTensor[{offsetClass + itemIndex, y, x}]

               if item[5] > confidenceThreshold then
                  table.insert(representation[mode], {{x, y}, {item[1], item[2]}, {item[3], item[4]}, utils.getItemInfo(mode, class)})
               end
            end
         end
      end
   end

   local representationGlobal = utils.gridToGlobal(width, height, gridWidth, gridHeight, representation)
   return representationGlobal
end

function utils.cropRepresentation(representation, startX, startY, endX, endY)
   local newRepresentation = {}
   for mode, items in pairs(representation) do
      newRepresentation[mode] = {}
      for _, item in pairs(items) do
         if (item[1][1] + item[2][1]) / 2 <= endX and (item[1][2] + item[2][2]) / 2 <= endY and (item[1][1] + item[2][1]) / 2 > startX and (item[1][2] + item[2][2]) / 2 > startY then
            if mode == 'icons' or mode == 'labels' then
               assert(item[1][1] <= item[2][1] and item[1][2] <= item[2][2], mode .. ' ' .. item[1][1] .. ' ' .. item[2][1] .. ' ' .. item[1][2] .. ' ' .. item[2][2])
            end

            for pointIndex = 1, 2 do
               item[pointIndex][1] = item[pointIndex][1] - startX
               item[pointIndex][2] = item[pointIndex][2] - startY
            end
            item[1][1] = math.max(item[1][1], 1)
            item[1][2] = math.max(item[1][2], 1)
            item[2][1] = math.min(item[2][1], endX - startX)
            item[2][2] = math.min(item[2][2], endY - startY)

            if mode == 'icons' or mode == 'labels' then
               if item[1][1] > item[2][1] or item[1][2] > item[2][2] then
                  print('invalid rectangle')
                  print(item[1][1] .. ' ' .. item[2][1] .. ' ' ..  item[1][2] .. ' ' .. item[2][2])
                  print(startX .. ' ' ..  startY)
                  print(endX .. ' ' ..  endY)
                  os.exit(1)
               end
            end

            table.insert(newRepresentation[mode], item)
         end
      end
   end
   return newRepresentation
end

function utils.scaleRepresentation(representation, width, height, newWidth, newHeight)
   local newRepresentation = {}
   for mode, items in pairs(representation) do
      newRepresentation[mode] = {}
      for _, item in pairs(items) do
         for pointIndex = 1, 2 do
            item[pointIndex][1] = torch.round((item[pointIndex][1] - 1) / width * newWidth + 1)
            item[pointIndex][2] = torch.round((item[pointIndex][2] - 1) / height * newHeight + 1)
         end
         table.insert(newRepresentation[mode], item)
      end
   end
   return newRepresentation
end

function utils.scaleRepresentationByRatio(representation, ratio)
   local newRepresentation = {}
   for mode, items in pairs(representation) do
      newRepresentation[mode] = {}
      for _, item in pairs(items) do
         for pointIndex = 1, 2 do
            item[pointIndex][1] = torch.round((item[pointIndex][1] - 1) * ratio + 1)
            item[pointIndex][2] = torch.round((item[pointIndex][2] - 1) * ratio + 1)
         end
         table.insert(newRepresentation[mode], item)
      end
   end
   return newRepresentation
end

function utils.rotateRepresentation(representation, width, height, orientation)
   --[[
      if orientation == 1 then
      return representation
      end
   ]]--

   local newRepresentation = {}
   for mode, items in pairs(representation) do
      newRepresentation[mode] = {}
      for _, item in pairs(items) do
         for pointIndex = 1, 2 do
            local x = item[pointIndex][1]
            local y = item[pointIndex][2]
            if orientation == 2 then
               item[pointIndex][1] = height - y
               item[pointIndex][2] = x
            elseif orientation == 3 then
               item[pointIndex][1] = width - x
               item[pointIndex][2] = height - y
            elseif orientation == 4 then
               item[pointIndex][1] = y
               item[pointIndex][2] = width - x
            end
         end
         if mode == 'icons' or mode == 'labels' then
            item = {{math.min(item[1][1], item[2][1]), math.min(item[1][2], item[2][2])}, {math.max(item[1][1], item[2][1]), math.max(item[1][2], item[2][2])}, item[3]}
         end
         table.insert(newRepresentation[mode], item)
      end
   end
   newRepresentation.walls = utils.sortLines(newRepresentation.walls)
   newRepresentation.doors = utils.sortLines(newRepresentation.doors)
   return newRepresentation
end

function utils.drawRepresentationImage(floorplan, representation, representationType, renderingType, lineWidth)
   local width, height = floorplan:size(3), floorplan:size(2)

   local iconImages = utils.loadIconImages()

   local representationType = representationType or 'P'
   local renderingType = renderingType or 'L'
   local lineWidth = lineWidth or 5

   local colorMap = {}
   colorMap[1] = {255, 0, 0}
   colorMap[2] = {0, 255, 0}
   colorMap[3] = {0, 0, 255}
   colorMap[4] = {255, 255, 0}
   colorMap[5] = {0, 255, 255}
   colorMap[6] = {255, 0, 255}
   colorMap[7] = {128, 0, 0}
   colorMap[8] = {0, 128, 0}
   colorMap[9] = {0, 0, 128}

   if representationType == 'P' and renderingType == 'P' then
      local representationImage = floorplan
      for mode, items in pairs(representation) do
         if mode == 'points' or mode == 'doors' or mode == 'icons' or mode == 'labels' then
            for __, item in pairs(items) do
               local rectangle = {item[1], item[2]}
               local center = {(rectangle[2][1] + rectangle[1][1]) / 2, (rectangle[2][2] + rectangle[1][2]) / 2}
               local rectangleWidth = math.max(rectangle[2][1] - rectangle[1][1] + 1, 10)
               local rectangleHeight = math.max(rectangle[2][2] - rectangle[1][2] + 1, 10)
               local color = colorMap[item[3][2]]

               local strokeWidth = 2
               if mode == 'points' then
                  strokeWidth = 10
               end

               local success, newRepresentationImage = pcall(function() return image.drawRect(representationImage, math.max(center[1] - rectangleWidth / 2, 1), math.max(center[2] - rectangleHeight / 2, 1), math.min(center[1] + rectangleWidth / 2, width), math.min(center[2] + rectangleHeight / 2, height), {lineWidth = strokeWidth, color = color}) end)
               if success then
                  representationImage = newRepresentationImage
               end
            end
         end
      end
      return representationImage
   elseif representationType == 'P' and renderingType == 'L' then
      if not representation.points or #representation.points == 0 then
         representation.points = utils.linesToPoints(width, height, representation.walls, lineWidth)
      end
      local representationImage = torch.ones(#floorplan)

      local lineWidth = 4
      local lines = utils.pointsToLines(width, height, representation.points, lineWidth, true)
      local lineMask = utils.drawLineMask(width, height, lines, lineWidth)


      local segmentation = utils.getSegmentation(width, height, representation, lineWidth)[1]
      local colorMap = {{224, 255, 192}, {224, 255, 192}, {255, 224, 128}, {192, 255, 255}, {192, 255, 255}, {255, 224, 224}, {192, 192, 224}, {255, 160, 96}, {192, 255, 255}, {224, 224, 224}}
      local borderColorMap = {{128, 192, 64}, {128, 192, 64}, {192, 128, 64}, {0, 128, 192}, {0, 128, 192}, {192, 64, 64}, {128, 64, 160}, {192, 64, 0}, {0, 128, 192}, {255, 255, 255}}

      local representationImageVideo = representationImage
      image.save('test/representation_image_background.png', representationImageVideo)

      local representationImageVideo = torch.zeros(3, height, width)
      --local representationImageMask = torch.zeros(4, height, width)
      --representationImageMask[{{1, 3}}] = 1
      for segmentIndex = 1, 10 do
         local segmentMask = segmentation:eq(segmentIndex)
         local dilatedSegmentMask = segmentMask
         for i = 1, lineWidth + 1 do
            dilatedSegmentMask = image.dilate(dilatedSegmentMask)
         end
         local borderMask = dilatedSegmentMask - segmentMask
         for c = 1, 3 do
            representationImage[c][borderMask] = borderColorMap[segmentIndex][c] / 256

            representationImageVideo[c][borderMask] = borderColorMap[segmentIndex][c] / 256
         end
         --representationImageVideo[4][borderMask] = 1
         --representationImageMask[4][borderMask] = 1
      end
      image.save('test/representation_image_walls.png', representationImageVideo)

      --local representationImageVideo = torch.ones(3, height, width)
      for segmentIndex = 1, 10 do
         local segmentMask = segmentation:eq(segmentIndex)
         for c = 1, 3 do
            representationImage[c][segmentMask] = colorMap[segmentIndex][c] / 256
            representationImageVideo[c][segmentMask] = colorMap[segmentIndex][c] / 256
         end
         --representationImageVideo[4][segmentMask] = 1
         --representationImageMask[4][segmentMask] = 1
      end
      image.save('test/representation_image_rooms.png', representationImageVideo)


      for __, item in pairs(representation.icons) do
         item[3] = utils.getItemInfo('icons', utils.getNumber('icons', item[3]))

         local iconImage = iconImages[item[3][1]][item[3][2]]
         --local rectangle = {item[1], item[2]}
         local rectangle = {{math.min(item[1][1], item[2][1]), math.min(item[1][2], item[2][2])}, {math.max(item[1][1], item[2][1]), math.max(item[1][2], item[2][2])}}
         for pointIndex = 1, 2 do
            rectangle[pointIndex][1] = torch.round(math.max(math.min(rectangle[pointIndex][1], width), 1))
            rectangle[pointIndex][2] = torch.round(math.max(math.min(rectangle[pointIndex][2], height), 1))
         end
         --print(mode)
         --print(rectangle)
         local orientation = 1
         local minDistance = math.max(width, height)
         local minDistanceOrientation
         if (math.abs(rectangle[2][1] - rectangle[1][1]) > math.abs(rectangle[2][2] - rectangle[1][2]) and item[3][1] ~= 'toilet' and item[3][1] ~= 'stairs') or (math.abs(rectangle[2][1] - rectangle[1][1]) < math.abs(rectangle[2][2] - rectangle[1][2]) and (item[3][1] == 'toilet' or item[3][1] == 'stairs')) or item[3][1] == 'washing_basin' then
            local min = math.min(rectangle[1][2], rectangle[2][2])
            local max = math.max(rectangle[1][2], rectangle[2][2])
            local center = (rectangle[1][1] + rectangle[2][1]) / 2
            local deltaMin = 0
            for delta = 1, min - 1 do
               deltaMin = delta
               if lineMask[min - delta][center] == 1 then
                  break
               end
            end
            local deltaMax = 0
            for delta = 1, height - max do
               deltaMax = delta
               if lineMask[max + delta][center] == 1 then
                  break
               end
            end

            if deltaMax < minDistance then
               minDistance = deltaMax
               minDistanceOrientation = 1
            end
            if deltaMin < minDistance then
               minDistance = deltaMin
               minDistanceOrientation = 3
            end
         end

         if (math.abs(rectangle[2][1] - rectangle[1][1]) < math.abs(rectangle[2][2] - rectangle[1][2]) and item[3][1] ~= 'toilet') or (math.abs(rectangle[2][1] - rectangle[1][1]) > math.abs(rectangle[2][2] - rectangle[1][2]) and item[3][1] == 'toilet') or item[3][1] == 'washing_basin' then
            local min = math.min(rectangle[1][1], rectangle[2][1])
            local max = math.max(rectangle[1][1], rectangle[2][1])
            local center = (rectangle[1][2] + rectangle[2][2]) / 2
            local deltaMin = 0
            for delta = 1, min - 1 do
               deltaMin = delta
               if lineMask[center][min - delta] == 1 then
                  break
               end
            end
            local deltaMax = 0
            for delta = 1, width - max do
               deltaMax = delta
               if lineMask[center][max + delta] == 1 then
                  break
               end
            end

            if deltaMax < minDistance then
               minDistance = deltaMax
               minDistanceOrientation = 4
            end
            if deltaMin < minDistance then
               minDistance = deltaMin
               minDistanceOrientation = 2
            end
         end

         if iconImage == nil then
            print(item)
         end
         orientation = minDistanceOrientation

         --[[
            if item[3][1] == 'stairs' and (rectangle[1][2] + rectangle[2][2]) / 2 > 277 then
            orientation = 1
            end
         ]]--


         iconImage = rotateIcon(iconImage, orientation)

         local icon = image.scale(iconImage, rectangle[2][1] - rectangle[1][1] + 1, rectangle[2][2] - rectangle[1][2] + 1)
         if icon:dim() == 2 or icon:size(1) == 1 then
            icon = icon:repeatTensor(3, 1, 1)
         end
         --print(#representationImage[{{}, {rectangle[1][2], rectangle[2][2]}, {rectangle[1][1], rectangle[2][1]}}])
         --[[
            print(#iconImage)
            print(#icon)
            print(rectangle[2][1] - rectangle[1][1] + 1)
            print(rectangle[2][2] - rectangle[1][2] + 1)
            print(item[3][1])
         ]]--

         representationImage[{{}, {rectangle[1][2], rectangle[2][2]}, {rectangle[1][1], rectangle[2][1]}}] = icon

         local representationImageVideo = torch.zeros(3, height, width)
         representationImageVideo[{{1, 3}, {rectangle[1][2], rectangle[2][2]}, {rectangle[1][1], rectangle[2][1]}}] = icon
         --representationImageVideo[{{4}, {rectangle[1][2], rectangle[2][2]}, {rectangle[1][1], rectangle[2][1]}}] = 1
         --representationImageMask[{{4}, {rectangle[1][2], rectangle[2][2]}, {rectangle[1][1], rectangle[2][1]}}] = 1
         image.save('test/representation_image_icon_' .. __ .. '.png', representationImageVideo)
      end


      local rooms, numRooms = utils.findConnectedComponents(1 - lineMask)
      --image.save('test/segmentation.png', utils.drawSegmentation(segmentation))
      --os.exit(1)
      rooms = segmentation:int() * numRooms + rooms:int()

      local roomLabelMap = {}
      for __, item in pairs(representation.labels) do
         local labelImage = iconImages[item[3][1]][item[3][2]]
         --local rectangle = {item[1], item[2]}
         local cx = (item[1][1] + item[2][1]) / 2
         local cy = (item[1][2] + item[2][2]) / 2

         local labelWidth = 80
         local labelHeight = 30
         local roomIndex = rooms[torch.round(cy)][torch.round(cx)]
         if not roomLabelMap[roomIndex] then
            roomLabelMap[roomIndex] = {}
         end
         local number = utils.getNumber('labels', item[3])
         if roomIndex > 0 and not roomLabelMap[roomIndex][number] then
            roomLabelMap[roomIndex][number] = true
            local roomIndices = rooms:eq(roomIndex):nonzero()
            local mins = torch.min(roomIndices, 1)[1]
            local maxs = torch.max(roomIndices, 1)[1]
            if maxs[2] - mins[2] + 1 < labelWidth * 0.8 then
               if math.min((maxs[2] - mins[2] + 1) / labelHeight, (maxs[1] - mins[1] + 1) / labelWidth) > (maxs[2] - mins[2] + 1) / labelWidth then
                  labelImage = rotateIcon(labelImage, 2)
                  labelWidth, labelHeight = labelHeight, labelWidth
               end
               if maxs[2] - mins[2] + 1 < labelWidth then
                  local ratio = math.max((maxs[2] - mins[2] + 1) / labelWidth, 0.5)
                  labelWidth, labelHeight = labelWidth * ratio, labelHeight * ratio
               end
            end

            if math.max(labelWidth, labelHeight) > 10 then
               local rectangle = {{cx - labelWidth / 2, cy - labelHeight / 2}, {cx + labelWidth / 2, cy + labelHeight / 2}}

               for pointIndex = 1, 2 do
                  rectangle[pointIndex][1] = torch.round(math.max(math.min(rectangle[pointIndex][1], width), 1))
                  rectangle[pointIndex][2] = torch.round(math.max(math.min(rectangle[pointIndex][2], height), 1))
               end


               --[[
                  if item[3][1] == 'bathroom' or item[3][1] == 'kitchen' then
                  for pointIndex = 1, 2 do
                  rectangle[pointIndex][2] = rectangle[pointIndex][2] - 20
                  end
                  end
                  if item[3][1] == 'bathroom' then
                  for pointIndex = 1, 2 do
                  rectangle[pointIndex][1] = rectangle[pointIndex][1] + 10
                  end
                  end
               ]]--

               local label = image.scale(labelImage, rectangle[2][1] - rectangle[1][1] + 1, rectangle[2][2] - rectangle[1][2] + 1, 'bicubic')
               label:narrow(1, 1, 1):fill(1)
               label:narrow(1, label:size(1), 1):fill(1)
               label:narrow(2, 1, 1):fill(1)
               label:narrow(2, label:size(2), 1):fill(1)

               if label:dim() == 2 or label:size(1) == 1 then
                  label = label:repeatTensor(3, 1, 1)
               end

               for c = 1, 3 do
                  representationImage[{c, {rectangle[1][2], rectangle[2][2]}, {rectangle[1][1], rectangle[2][1]}}][label[1]:lt(0.5)] = 0
               end
            end
            --representationImage = image.drawText(representationImage, 'abs', (rectangle[1][1] + rectangle[2][1]) / 2, (rectangle[1][2] + rectangle[2][2]) / 2, {color = {0, 0, 0}, size = 2})
            --representationImage[{{}, {rectangle[1][2], rectangle[2][2]}, {rectangle[1][1], rectangle[2][1]}}] = label
         end
      end


      local doorMask = torch.zeros(height, width)
      local endPointLineLength = 7
      local dashLineStride = 10
      for _, door in pairs(representation.doors) do
         local lineDim = utils.lineDim(door, lineWidth)
         for pointIndex = 1, 2 do
            for c = 1, 2 do
               door[pointIndex][c] = torch.round(door[pointIndex][c])
            end
         end
         if lineDim > 0 then
            for pointIndex = 1, 2 do
               local point = door[pointIndex]
               doorMask:narrow(3 - lineDim, point[lineDim], 1):narrow(lineDim, math.max(point[3 - lineDim] - endPointLineLength, 1), math.min(endPointLineLength * 2 + 1, doorMask:size(lineDim) - (point[3 - lineDim] - endPointLineLength) + 1)):fill(1)
            end
            local fixedValue = (door[1][3 - lineDim] + door[2][3 - lineDim]) / 2
            for lineValue = door[1][lineDim], door[2][lineDim], dashLineStride do
               doorMask:narrow(3 - lineDim, lineValue, 1):narrow(lineDim, fixedValue, 1):fill(1)
            end
         end
      end
      for i = 1, 2 do
         doorMask = image.dilate(doorMask)
      end
      doorMask = doorMask:byte()

      for c = 1, 3 do
         representationImage[c][doorMask] = 0
      end

      local representationImageVideo = torch.ones(3, height, width)
      for c = 1, 3 do
         representationImageVideo[c][doorMask] = 0
      end
      --representationImageVideo[4][doorMask] = 1
      --representationImageMask[4][doorMask] = 1
      image.save('test/representation_image_door.png', representationImageVideo)


      local pointMask = torch.zeros(height, width)
      for _, point in pairs(representation.points) do
         local x = torch.round(point[1][1])
         local y = torch.round(point[1][2])
         if x >= 1 and x <= width and y >= 1 and y <= height then
            pointMask[y][x] = 1
         end
      end

      local largeDiskRadius = 8
      local largeDiskKernel = torch.zeros(largeDiskRadius * 2 + 1, largeDiskRadius * 2 + 1)
      for y = 1, largeDiskRadius * 2 + 1 do
         for x = 1, largeDiskRadius * 2 + 1 do
            if ((x - largeDiskRadius - 1)^2 + (y - largeDiskRadius - 1)^2)^0.5 <= largeDiskRadius then
               largeDiskKernel[y][x] = 1
            end
         end
      end
      local largeDiskMask = image.dilate(pointMask, largeDiskKernel):byte()
      representationImage[1][largeDiskMask] = 0.9
      representationImage[2][largeDiskMask] = 0.3
      representationImage[3][largeDiskMask] = 0.3

      local smallDiskRadius = 4
      local smallDiskKernel = torch.zeros(smallDiskRadius * 2 + 1, smallDiskRadius * 2 + 1)
      for y = 1, smallDiskRadius * 2 + 1 do
         for x = 1, smallDiskRadius * 2 + 1 do
            if ((x - smallDiskRadius - 1)^2 + (y - smallDiskRadius - 1)^2)^0.5 <= smallDiskRadius then
               smallDiskKernel[y][x] = 1
            end
         end
      end
      local smallDiskMask = image.dilate(pointMask, smallDiskKernel):byte()
      for c = 1, 3 do
         representationImage[c][smallDiskMask] = 1
      end


      local representationImageVideo = torch.ones(3, height, width)
      representationImageVideo[1][largeDiskMask] = 0.9
      representationImageVideo[2][largeDiskMask] = 0.3
      representationImageVideo[3][largeDiskMask] = 0.3
      --representationImageVideo[4][largeDiskMask] = 1
      --representationImageMask[4][largeDiskMask] = 1
      for c = 1, 3 do
         representationImageVideo[c][smallDiskMask] = 0
      end
      --representationImageVideo[4][smallDiskMask] = 1
      --representationImageMask[4][smallDiskMask] = 1
      image.save('test/representation_image_wall_junctions.png', representationImageVideo)
      --image.save('test/representation_image_mask.png', representationImageMask)


      if true then
         return representationImage
      end

      for c = 1, 3 do
         representationImage[c][lineMask:byte()] = 0
      end

      local doorWidth = lineWidth - 2
      for _, line in pairs(representation.doors) do
         local lineDim = utils.lineDim(line)
         if lineDim > 0 then
            local maxSize = {width, height}
            local rectangle = {{}, {}}
            rectangle[1][lineDim] = math.max(math.min(line[1][lineDim], line[2][lineDim], maxSize[lineDim]), 1)
            rectangle[2][lineDim] = math.min(math.max(line[1][lineDim], line[2][lineDim], 1), maxSize[lineDim])
            rectangle[1][3 - lineDim] = math.max((line[1][3 - lineDim] + line[2][3 - lineDim]) / 2 - doorWidth, 1)
            rectangle[2][3 - lineDim] = math.min((line[1][3 - lineDim] + line[2][3 - lineDim]) / 2 + doorWidth, maxSize[3 - lineDim])

            representationImage[{{}, {rectangle[1][2], rectangle[2][2]}, {rectangle[1][1], rectangle[2][1]}}] = 1
            --success, newRepresentationImage = pcall(function() return image.drawRect(representationImage, rectangle[1][1], rectangle[1][2], rectangle[2][1], rectangle[2][2], {lineWidth = lineWidth, color = {0, 0, 0}}) end)
            --if success then
            --representationImage = newRepresentationImage
            --end
         end
         --representationImage[{{}, {minX, maxX}, {minY, maxY}}] = 0
      end

      return representationImage
   end
end

function utils.getImageInfo(floorplan, representation, representationType, renderingType, lineWidth)
   local lineWidth = lineWidth or 5

   for mode, items in pairs(representation) do
      for _, item in pairs(items) do
         for pointIndex = 1, 2 do
            for c = 1, 2 do
               item[pointIndex][c] = torch.round(item[pointIndex][c])
            end
         end
         if mode == 'walls' or mode == 'doors' then
            local lineDim = utils.lineDim(item, lineWidth)
            local fixedValue = torch.round((item[1][3 - lineDim] + item[2][3 - lineDim]) / 2)
            item[1][3 - lineDim] = fixedValue
            item[2][3 - lineDim] = fixedValue
         end
      end
   end

   local width, height = floorplan:size(3), floorplan:size(2)

   local iconImages = utils.loadIconImages()

   local lineWidth = lineWidth or 4

   if not representation.points or #representation.points == 0 then
      representation.points = utils.linesToPoints(width, height, representation.walls, lineWidth)
   end
   local newPoints = {}
   for _, point in pairs(representation.points) do
      if point[3][2] <= 2 then
         table.insert(newPoints, point)
      elseif point[3][2] == 3 then
         local orientation = point[3][3]
         if orientation == 1 then
            table.insert(newPoints, {{point[1][1], point[1][2]}, {point[2][1], point[2][2]}, {'point', 2, 3}})
            table.insert(newPoints, {{point[1][1], point[1][2]}, {point[2][1], point[2][2]}, {'point', 2, 4}})
         elseif orientation == 2 then
            table.insert(newPoints, {{point[1][1], point[1][2]}, {point[2][1], point[2][2]}, {'point', 2, 4}})
            table.insert(newPoints, {{point[1][1], point[1][2]}, {point[2][1], point[2][2]}, {'point', 2, 1}})
         elseif orientation == 3 then
            table.insert(newPoints, {{point[1][1], point[1][2]}, {point[2][1], point[2][2]}, {'point', 2, 1}})
            table.insert(newPoints, {{point[1][1], point[1][2]}, {point[2][1], point[2][2]}, {'point', 2, 2}})
         else
            table.insert(newPoints, {{point[1][1], point[1][2]}, {point[2][1], point[2][2]}, {'point', 2, 2}})
            table.insert(newPoints, {{point[1][1], point[1][2]}, {point[2][1], point[2][2]}, {'point', 2, 3}})
         end
      else
         for orientation = 1, 4 do
            table.insert(newPoints, {point[1], point[2], {'point', 2, orientation}})
         end
      end
   end
   representation.points = newPoints

   local newWalls, wallPoints = utils.pointsToLines(width, height, representation.points, lineWidth, true, nil, nil, true)
   for _, wall in pairs(newWalls) do
      local lineDim = utils.lineDim(wall, lineWidth)
      local wallFixedValue = (wall[1][3 - lineDim] + wall[2][3 - lineDim]) / 2
      local wallMinValue = math.min(wall[1][lineDim], wall[2][lineDim])
      local wallMaxValue = math.max(wall[1][lineDim], wall[2][lineDim])
      for _, longWall in pairs(representation.walls) do
         if utils.lineDim(longWall, lineWidth) == lineDim then
            local longWallFixedValue = (longWall[1][3 - lineDim] + longWall[2][3 - lineDim]) / 2
            local longWallMinValue = math.min(longWall[1][lineDim], longWall[2][lineDim])
            local longWallMaxValue = math.max(longWall[1][lineDim], longWall[2][lineDim])
            if math.abs(longWallFixedValue - wallFixedValue) <= lineWidth and longWallMinValue - lineWidth <= wallMinValue and longWallMaxValue + lineWidth >= wallMaxValue then
               if #longWall == 4 then
                  table.insert(newWalls[_], longWall[4])
                  break
               end
            end
         end
      end
   end

   local pointWalls = {}
   for wallIndex, points in pairs(wallPoints) do
      for pointIndex = 1, 2 do
         if not pointWalls[points[pointIndex]] then
            pointWalls[points[pointIndex]] = {}
         end
         table.insert(pointWalls[points[pointIndex]], {wallIndex, pointIndex})
      end
   end


   local lineMask = utils.drawLineMask(width, height, representation.walls, lineWidth)

   local segmentation = utils.getSegmentation(width, height, representation, lineWidth)[1]
   local colorMap = {{224, 255, 192}, {224, 255, 192}, {255, 224, 128}, {192, 255, 255}, {192, 255, 255}, {255, 224, 224}, {192, 192, 224}, {255, 160, 96}, {192, 255, 255}, {224, 224, 224}}
   local borderColorMap = {{128, 192, 64}, {128, 192, 64}, {192, 128, 64}, {0, 128, 192}, {0, 128, 192}, {192, 64, 64}, {128, 64, 160}, {192, 64, 0}, {0, 128, 192}, {160, 160, 160}}
   table.insert(borderColorMap, {255, 255, 255})
   for _, color in pairs(colorMap) do
      for c = 1, 3 do
         color[c] = color[c] / 255
      end
   end
   for _, color in pairs(borderColorMap) do
      for c = 1, 3 do
         color[c] = color[c] / 255
      end
   end

   local segmentImages = {}
   local allWallImage = torch.ones(3, height, width)
   local allSegmentMask = torch.zeros(height, width)
   for segmentIndex = 1, 10 do
      local segmentMask = segmentation:eq(segmentIndex)
      local dilatedSegmentMask = segmentMask
      for i = 1, lineWidth do
         dilatedSegmentMask = image.dilate(dilatedSegmentMask)
      end
      local borderMask = dilatedSegmentMask - segmentMask
      for c = 1, 3 do
         allWallImage[c][borderMask] = borderColorMap[segmentIndex][c]
      end
      --allWallImage[4][borderMask] = 1

      --local segmentImage = torch.zeros(height, width)
      --         --local segmentMask = segmentation:eq(segmentIndex)
      --for c = 1, 3 do
      --segmentImage[c][segmentMask] = colorMap[segmentIndex][c] / 256
      --end
      --segmentImage[segmentMask] = 1

      table.insert(segmentImages, dilatedSegmentMask)
      allSegmentMask[segmentMask] = segmentIndex
   end

   --local wallRoomLabels = {}
   for _, wall in pairs(representation.walls) do
      local lineDim = utils.lineDim(wall, lineWidth)

      local x = (wall[1][1] + wall[2][1]) / 2
      local y = (wall[1][2] + wall[2][2]) / 2
      local deltas
      if lineDim == 1 then
         deltas = {0, 1}
      else
         deltas = {1, 0}
      end
      if #wall == 3 then
         local roomLabels = {11, 11}
         for direction = 1, 2 do
            local newX = x
            local newY = y
            for i = 1, 10 do
               newX = newX + deltas[1] * (direction * 2 - 3)
               newY = newY + deltas[2] * (direction * 2 - 3)
               if newX <= 0 or newX > width or newY <= 0 or newY > height then
                  break
               end
               local segmentIndex = segmentation[newY][newX]
               if segmentIndex > 0 and segmentIndex <= 10 then
                  roomLabels[direction] = segmentIndex
                  break
               end
            end
         end
         --table.insert(wallRoomLabels, roomLabels)
         table.insert(representation.walls[_], roomLabels)
      end
      table.insert(representation.walls[_], wallPoints[_])
   end

   for _, wall in pairs(representation.walls) do
      local lineDim = utils.lineDim(wall, lineWidth)
      local wallFixedValue = (wall[1][3 - lineDim] + wall[2][3 - lineDim]) / 2
      local wallMinValue = math.min(wall[1][lineDim], wall[2][lineDim])
      local wallMaxValue = math.max(wall[1][lineDim], wall[2][lineDim])
      local doorIndices = {}
      for doorIndex, door in pairs(representation.doors) do
         if utils.lineDim(door, lineWidth) == lineDim then
            local doorFixedValue = (door[1][3 - lineDim] + door[2][3 - lineDim]) / 2
            local doorMinValue = math.min(door[1][lineDim], door[2][lineDim])
            local doorMaxValue = math.max(door[1][lineDim], door[2][lineDim])
            if math.abs(doorFixedValue - wallFixedValue) <= lineWidth and math.max(doorMinValue, wallMinValue) < math.min(doorMaxValue, wallMaxValue) then
               table.insert(doorIndices, doorIndex)
            end
         end
      end
      table.insert(representation.walls[_], doorIndices)
   end

   -- local wallImages = {}
   -- local wallNeighborSegments = {}
   -- for _, wall in pairs(representation.walls) do
   --    local lineDim = utils.lineDim(wall, lineWidth)
   --    local fixedValue = (wall[1][3 - lineDim] + wall[2][3 - lineDim]) / 2
   --    local minValue = math.min(wall[1][lineDim], wall[2][lineDim])
   --    local maxValue = math.max(wall[1][lineDim], wall[2][lineDim])
   --    table.insert(wallImages, allWallImage:narrow(4 - lineDim, minValue, maxValue - minValue + 1):narrow(1 + lineDim, fixedValue - lineWidth, lineWidth * 2 + 1))
   --    wall[1][lineDim] = minValue
   --    wall[2][lineDim] = maxValue
   --    wall[1][3 - lineDim] = fixedValue
   --    wall[2][3 - lineDim] = fixedValue

   --    local segmentMasks = torch.zeros(2, 10, maxValue - minValue - 1)
   --    local deltas = {-1, 1}
   --    for value = minValue + 1, maxValue - 1 do
   -- 	 for direction = 1, 2 do
   --          local segmentIndex
   -- 	    for i = 1, 10 do
   -- 	       if lineDim == 1 then
   -- 		  if fixedValue + deltas[direction] * i <= 0 or fixedValue + deltas[direction] * i > height then
   --                   break
   --                end
   -- 		  segmentIndex = allSegmentMask[fixedValue + deltas[direction] * i][value]
   --                if segmentIndex > 0 then
   --                   break
   --                end
   --             elseif lineDim == 2 then
   -- 		  if fixedValue + deltas[direction] * i <= 0 or fixedValue + deltas[direction] * i > width then
   --                   break
   --                end
   -- 		  segmentIndex = allSegmentMask[value][fixedValue + deltas[direction] * i]
   --                if segmentIndex > 0 then
   --                   break
   --                end
   -- 	       end
   -- 	    end
   -- 	    if segmentIndex > 0 then
   -- 	       segmentMasks[direction][segmentIndex][value - minValue] = 1
   -- 	    end
   -- 	 end
   --    end
   --    local neighborSegments = {{}, {}}
   --    for direction = 1, 2 do
   -- 	 for segmentIndex = 1, 10 do
   -- 	    if segmentMasks[direction][segmentIndex]:sum() > 0 then
   -- 	       local segmentMask = segmentMasks[direction][segmentIndex]
   -- 	       segmentMask = segmentMask:repeatTensor(1, 1)
   -- 	       if lineDim == 2 then
   -- 		  segmentMask = segmentMask:transpose(1, 2)
   -- 	       end
   -- 	       table.insert(neighborSegments[direction], {segmentIndex, segmentMask:byte()})
   -- 	    end
   -- 	 end
   --    end
   --    table.insert(wallNeighborSegments, neighborSegments)
   -- end

   -- for iconIndex, icon in pairs(representation.icons) do
   --    local neighborWalls = {}
   --    local center = {(icon[1][1] + icon[2][1]) / 2, (icon[1][2] + icon[2][2]) / 2}
   --    local size = {icon[2][1] - icon[1][1], icon[2][2] - icon[1][2]}
   --    for _, wall in pairs(representation.walls) do
   --       local lineDim = utils.lineDim(wall, lineWidth)
   --       local wallFixedValue = (wall[1][3 - lineDim] + wall[2][3 - lineDim]) / 2
   --       local wallMinValue = math.min(wall[1][lineDim], wall[2][lineDim])
   --       local wallMaxValue = math.max(wall[1][lineDim], wall[2][lineDim])
   -- 	 if wallMinValue < center[lineDim] + size[lineDim] / 2 and wallMaxValue > center[lineDim] - size[lineDim] / 2 then
   -- 	 end
   --    end
   -- end

   for __, item in pairs(representation.icons) do
      item[3] = utils.getItemInfo('icons', utils.getNumber('icons', item[3]))
      local rectangle = {{math.min(item[1][1], item[2][1]), math.min(item[1][2], item[2][2])}, {math.max(item[1][1], item[2][1]), math.max(item[1][2], item[2][2])}}
      for pointIndex = 1, 2 do
         rectangle[pointIndex][1] = torch.round(math.max(math.min(rectangle[pointIndex][1], width), 1))
         rectangle[pointIndex][2] = torch.round(math.max(math.min(rectangle[pointIndex][2], height), 1))
      end
      local minDistance = math.max(width, height)
      local minDistanceOrientation
      if (math.abs(rectangle[2][1] - rectangle[1][1]) > math.abs(rectangle[2][2] - rectangle[1][2]) and item[3][1] ~= 'toilet' and item[3][1] ~= 'stairs') or (math.abs(rectangle[2][1] - rectangle[1][1]) < math.abs(rectangle[2][2] - rectangle[1][2]) and (item[3][1] == 'toilet' or item[3][1] == 'stairs')) or item[3][1] == 'washing_basin' then
         local min = math.min(rectangle[1][2], rectangle[2][2])
         local max = math.max(rectangle[1][2], rectangle[2][2])
         local center = (rectangle[1][1] + rectangle[2][1]) / 2
         local deltaMin = 0
         for delta = 1, min - 1 do
            deltaMin = delta
            if lineMask[min - delta][center] == 1 then
               break
            end
         end
         local deltaMax = 0
         for delta = 1, height - max do
            deltaMax = delta
            if lineMask[max + delta][center] == 1 then
               break
            end
         end

         if deltaMax < minDistance then
            minDistance = deltaMax
            minDistanceOrientation = 1
         end
         if deltaMin < minDistance then
            minDistance = deltaMin
            minDistanceOrientation = 3
         end
      end

      if (math.abs(rectangle[2][1] - rectangle[1][1]) < math.abs(rectangle[2][2] - rectangle[1][2]) and item[3][1] ~= 'toilet') or (math.abs(rectangle[2][1] - rectangle[1][1]) > math.abs(rectangle[2][2] - rectangle[1][2]) and item[3][1] == 'toilet') or item[3][1] == 'washing_basin' then
         local min = math.min(rectangle[1][1], rectangle[2][1])
         local max = math.max(rectangle[1][1], rectangle[2][1])
         local center = (rectangle[1][2] + rectangle[2][2]) / 2
         local deltaMin = 0
         for delta = 1, min - 1 do
            deltaMin = delta
            if lineMask[center][min - delta] == 1 then
               break
            end
         end
         local deltaMax = 0
         for delta = 1, width - max do
            deltaMax = delta
            if lineMask[center][max + delta] == 1 then
               break
            end
         end

         if deltaMax < minDistance then
            minDistance = deltaMax
            minDistanceOrientation = 4
         end
         if deltaMin < minDistance then
            minDistance = deltaMin
            minDistanceOrientation = 2
         end
      end

      item[3][3] = minDistanceOrientation
   end


   local rooms, numRooms = utils.findConnectedComponents(1 - lineMask)
   rooms = segmentation:int() * numRooms + rooms:int()


   local newLabels = {}
   local roomLabelMap = {}
   for __, item in pairs(representation.labels) do
      --local rectangle = {item[1], item[2]}
      local cx = (item[1][1] + item[2][1]) / 2
      local cy = (item[1][2] + item[2][2]) / 2

      local labelWidth = 80
      local labelHeight = 30
      local roomIndex = rooms[torch.round(cy)][torch.round(cx)]
      if not roomLabelMap[roomIndex] then
         roomLabelMap[roomIndex] = {}
      end
      local number = utils.getNumber('labels', item[3])
      if roomIndex > 0 and not roomLabelMap[roomIndex][number] then
         roomLabelMap[roomIndex][number] = true
         local roomIndices = rooms:eq(roomIndex):nonzero()
         local mins = torch.min(roomIndices, 1)[1]
         local maxs = torch.max(roomIndices, 1)[1]

         local orientation = 1
         if maxs[2] - mins[2] + 1 < labelWidth * 0.8 then
            if math.min((maxs[2] - mins[2] + 1) / labelHeight, (maxs[1] - mins[1] + 1) / labelWidth) > (maxs[2] - mins[2] + 1) / labelWidth then
               labelWidth, labelHeight = labelHeight, labelWidth
               orientation = 2
            end
            if maxs[2] - mins[2] + 1 < labelWidth then
               local ratio = math.max((maxs[2] - mins[2] + 1) / labelWidth, 0.5)
               labelWidth, labelHeight = labelWidth * ratio, labelHeight * ratio
            end
         end

         if math.max(labelWidth, labelHeight) > 10 then
            local cx = (mins[2] + maxs[2]) / 2
            local cy = (mins[1] + maxs[1]) / 2
            local rectangle = {{cx - labelWidth / 2, cy - labelHeight / 2}, {cx + labelWidth / 2, cy + labelHeight / 2}}

            for pointIndex = 1, 2 do
               rectangle[pointIndex][1] = torch.round(math.max(math.min(rectangle[pointIndex][1], width), 1))
               rectangle[pointIndex][2] = torch.round(math.max(math.min(rectangle[pointIndex][2], height), 1))
            end
            local label = rectangle
            table.insert(label, {item[3][1], item[3][2], orientation})
            table.insert(newLabels, label)
         end
      end
   end
   representation.labels = newLabels


   local doorMask = torch.zeros(height, width)
   local endPointLineLength = 7
   local dashLineStride = 10
   for _, door in pairs(representation.doors) do
      local lineDim = utils.lineDim(door, lineWidth)
      for pointIndex = 1, 2 do
         for c = 1, 2 do
            door[pointIndex][c] = torch.round(door[pointIndex][c])
         end
      end
      for pointIndex = 1, 2 do
         local point = door[pointIndex]
         doorMask:narrow(3 - lineDim, point[lineDim], 1):narrow(lineDim, math.max(point[3 - lineDim] - endPointLineLength, 1), math.min(endPointLineLength * 2 + 1, doorMask:size(lineDim) - (point[3 - lineDim] - endPointLineLength) + 1)):fill(1)
      end
      local fixedValue = (door[1][3 - lineDim] + door[2][3 - lineDim]) / 2
      for lineValue = door[1][lineDim], door[2][lineDim], dashLineStride do
         doorMask:narrow(3 - lineDim, lineValue, 1):narrow(lineDim, fixedValue, 1):fill(1)
      end
   end
   for i = 1, 2 do
      doorMask = image.dilate(doorMask)
   end
   doorMask = doorMask:byte()

   local allDoorImage = torch.zeros(4, height, width)
   for c = 1, 3 do
      allDoorImage[c][doorMask] = 0
   end
   allDoorImage[4][doorMask] = 1

   for _, door in pairs(representation.doors) do
      local lineDim = utils.lineDim(door, lineWidth)
      local fixedValue = (door[1][3 - lineDim] + door[2][3 - lineDim]) / 2
      local minValue = math.min(door[1][lineDim], door[2][lineDim])
      local maxValue = math.max(door[1][lineDim], door[2][lineDim])
      --table.insert(doorImages, allDoorImage:narrow(4 - lineDim, minValue, maxValue - minValue + 1):narrow(1 + lineDim, fixedValue - endPointLineLength, endPointLineLength * 2 + 1))
      door[1][lineDim] = minValue
      door[2][lineDim] = maxValue
      door[1][3 - lineDim] = fixedValue
      door[2][3 - lineDim] = fixedValue
      local doorImage = doorMask:narrow(3 - lineDim, minValue, maxValue - minValue + 1):narrow(lineDim, fixedValue - endPointLineLength, endPointLineLength * 2 + 1)
      table.insert(representation.doors[_], doorImage)
   end


   local pointMask = torch.zeros(height, width)
   for _, point in pairs(representation.points) do
      local x = torch.round(point[1][1])
      local y = torch.round(point[1][2])
      if x >= 1 and x <= width and y >= 1 and y <= height then
         pointMask[y][x] = 1
      end
   end

   local largeDiskRadius = 8
   local largeDiskKernel = torch.zeros(largeDiskRadius * 2 + 1, largeDiskRadius * 2 + 1)
   for y = 1, largeDiskRadius * 2 + 1 do
      for x = 1, largeDiskRadius * 2 + 1 do
         if ((x - largeDiskRadius - 1)^2 + (y - largeDiskRadius - 1)^2)^0.5 <= largeDiskRadius then
            largeDiskKernel[y][x] = 1
         end
      end
   end
   local largeDiskMask = image.dilate(pointMask, largeDiskKernel):byte()

   local smallDiskRadius = 4
   local smallDiskKernel = torch.zeros(smallDiskRadius * 2 + 1, smallDiskRadius * 2 + 1)
   for y = 1, smallDiskRadius * 2 + 1 do
      for x = 1, smallDiskRadius * 2 + 1 do
         if ((x - smallDiskRadius - 1)^2 + (y - smallDiskRadius - 1)^2)^0.5 <= smallDiskRadius then
            smallDiskKernel[y][x] = 1
         end
      end
   end
   local smallDiskMask = image.dilate(pointMask, smallDiskKernel):byte()

   local allPointImage = torch.zeros(4, height, width)
   allPointImage[1][largeDiskMask] = 0.9
   allPointImage[2][largeDiskMask] = 0.3
   allPointImage[3][largeDiskMask] = 0.3
   allPointImage[4][largeDiskMask] = 1
   for c = 1, 3 do
      allPointImage[c][smallDiskMask] = 1
   end

   local point = representation.points[1][1]
   local pointImage = allPointImage:narrow(2, point[2] - largeDiskRadius, largeDiskRadius * 2 + 1):narrow(3, point[1] - largeDiskRadius, largeDiskRadius * 2 + 1)
   -- local pointImages = {}
   -- for _, point in pairs(representation.points) do
   --    point = point[1]
   --    table.insert(pointImages, allPointImage:narrow(2, point[2] - largeDiskRadius, largeDiskRadius * 2 + 1):narrow(3, point[1] - largeDiskRadius, largeDiskRadius * 2 + 1))
   -- end


   return {pointImage = pointImage, segmentImages = segmentImages, colorMap = colorMap, borderColorMap = borderColorMap, pointWalls = pointWalls}
end

function utils.loadRepresentation(filename)
   local representationExists, representationInfo = pcall(function()
         return csvigo.load({path=filename, mode="large", header=false, separator='\t', verbose=false})
   end)
   if representationExists and representationInfo ~= nil then
      local representation = {}
      representation.walls = {}
      representation.doors = {}
      representation.icons = {}
      representation.labels = {}
      local modeMap = utils.modeMap()
      for _, itemInfo in pairs(representationInfo) do
         if itemInfo[5] ~= 'point' then
            local itemMode = modeMap[itemInfo[5]]
            local item = {{tonumber(itemInfo[1]), tonumber(itemInfo[2])}, {tonumber(itemInfo[3]), tonumber(itemInfo[4])}, {itemInfo[5], tonumber(itemInfo[6]), tonumber(itemInfo[7])}}
            if itemMode == 'icons' or itemMode == 'labels' or utils.lineDim(item) > 0 then
               item[1][1], item[2][1] = math.min(item[1][1], item[2][1]), math.max(item[1][1], item[2][1])
               item[1][2], item[2][2] = math.min(item[1][2], item[2][2]), math.max(item[1][2], item[2][2])
            end
            table.insert(representation[itemMode], item)
         end
      end
      return representation
   else
      return nil
   end
end

function utils.loadItems(filename)
   local representationExists, representationInfo = pcall(function()
         return csvigo.load({path=filename, mode="large", header=false, separator='\t', verbose=false})
         --return io.open(filename, 'r')
   end)

   if representationExists and representationInfo ~= nil then
      --representationInfo = csvigo.load({path=filename, mode="large", header=false, separator='\t', verbose=false})

      local items = {}
      for _, item in pairs(representationInfo) do
         local itemInfo = {{tonumber(item[1]), tonumber(item[2])}, {tonumber(item[3]), tonumber(item[4])}, {item[5], tonumber(item[6]), tonumber(item[7])}}
         --print(item[5])
         --print(itemMode)
         table.insert(items, itemInfo)
      end
      return items
   else
      return {}
   end
end

function utils.finalizeRepresentation(representation)
   if representation.walls then
      representation.walls = utils.stitchLines(utils.sortLines(representation.walls), 5)
      if representation.doors then
         representation.doors = utils.fixedDoors(utils.sortLines(representation.doors), representation.walls, 5)
      end
   end
   return representation
end

function utils.saveRepresentation(filename, representation, ratio)
   --local representationExists, representationFile = pcall(function()
   --return io.open(filename, 'r')
   --end)
   --local override = false
   --if representationExists then
   --end
   print('save representation')

   if ratio ~= nil and ratio ~= 1 then
      representation = utils.scaleRepresentationByRatio(representation, ratio)
   end

   if filename:match('(.+)/(.+)') ~= nil then
      pl.dir.makepath(filename:match('(.+)/(.+)'))
   end

   local representationFile = io.open(filename, 'w')
   representation.points = nil
   for itemMode, items in pairs(representation) do
      for _, item in pairs(items) do
         for __, field in pairs(item) do
            if __ <= 3 then
               for ___, value in pairs(field) do
                  representationFile:write(value .. '\t')
               end
            end
         end
         representationFile:write('\n')
      end
   end

   representationFile:close()
end

function utils.printRepresentation(representation)
   for itemMode, items in pairs(representation) do
      for _, item in pairs(items) do
         --for __, field in pairs(item) do
         --if __ <= 3 then
         --for ___, value in pairs(field) do
         --end
         --end
         --end
         print('(' .. item[1][1] .. ', ' .. item[1][2] .. ')\t(' .. item[2][1] .. ', ' .. item[2][2] .. ')\t' .. item[3][1] .. ' ' .. item[3][2] .. ' ' .. item[3][3])
         print('\n')
      end
   end
end

function utils.predictRepresentation(modelPath, floorplan)
   if utils.model == nil then
      utils.model = torch.load(modelPath)
   end

   local width = floorplan:size(3)
   local height = floorplan:size(2)
   local sampleDim = 256
   --local floorplanScaled = image.scale(floorplan, sampleDim, sampleDim)
   local lineWidth = lineWidth or 5

   local model = utils.model
   model:evaluate()

   package.path = '../code/datasets/?.lua;' .. package.path
   package.path = '../code/?.lua;' .. package.path


   local dataset = require('floorplan-representation')
   local floorplanNormalized = dataset:preprocessResize(sampleDim, sampleDim)(floorplan)
   local input = floorplanNormalized:repeatTensor(1, 1, 1, 1):cuda()
   --local input = floorplanScaled:repeatTensor(1, 1, 1, 1):cuda()

   local output = model.modules[1]:forward(input)
   local prob, pred = torch.max(output[2]:double(), 2)
   pred = pred[{{}, 1}]:view(-1, 8, 8, 8):transpose(3, 4):transpose(2, 3):double()
   local outputRepresentation = torch.cat(output[1]:double(), pred, 2)

   local representationTensor = outputRepresentation[1]
   local representation = utils.convertTensorToRepresentation(sampleDim, sampleDim, representationTensor, 0.5)
   local representationUnscaled = utils.scaleRepresentation(representation, sampleDim, sampleDim, width, height)
   local representationGeneral = utils.convertRepresentationToGeneral(width, height, representationUnscaled, 'P', lineWidth)
   return representationGeneral
end


function utils.predictSegmentation(floorplan, walls, preview)
   if utils.model == nil then
      utils.model = torch.load('/home/chenliu/Projects/Floorplan/models/segmentation/model_best.t7')
   end

   local width = floorplan:size(3)
   local height = floorplan:size(2)
   local sampleDim = 256
   --local floorplanScaled = image.scale(floorplan, sampleDim, sampleDim)
   local lineWidth = lineWidth or 5

   local model = utils.model
   --model:evaluate()

   --local datasets = require 'datasets/init'
   --local opts = require '../../InverseCAD/opts'
   --local opt = opts.parse(arg)
   package.path = '../InverseCAD/datasets/?.lua;' .. package.path
   package.path = '../InverseCAD/?.lua;' .. package.path
   --local dataset = require('/home/chenliu/Projects/Floorplan/floorplan/InverseCAD/datasets/floorplan-representation')(nil, nil, 'val')
   --local dataset = require('floorplan-representation')(nil, nil, 'val')
   --local dataset = require 'floorplan-representation'({}, nil, 'val')

   local dataset = require('floorplan-representation')
   local floorplanNormalized = dataset:preprocessResize(sampleDim, sampleDim)(floorplan)
   local input = floorplanNormalized:repeatTensor(1, 1, 1, 1):cuda()

   --print(#input)
   local output = model:forward(input)
   --print(output[1])
   local prob, pred = torch.max(output:double(), 2)
   local prediction = pred[{{}, 1}]:view((#input)[1], sampleDim, sampleDim)[1]:double()
   prediction = image.scale(prediction, width, height, 'simple')
   local segmentationImage = utils.drawSegmentation(prediction, torch.max(prediction))
   --segmentationImage = image.scale(segmentationImage, width, height)

   if preview then
      return segmentationImage
   end

   local wallMask
   if walls then
      wallMask = utils.drawLineMask(width, height, walls, lineWidth)
   else
      wallMask = prediction:eq(25):double()
   end
   local rooms, numRooms = utils.findConnectedComponents(1 - wallMask)
   --image.save('test/rooms.png', utils.drawSegmentation(rooms))
   local indexMask = (rooms * 100 + prediction:int())
   local indices = indexMask:view(-1)
   local components = {}
   for i = 1, indices:size(1) do
      components[indices[i]] = true
   end
   local markers = torch.zeros(height, width)
   local markerIndex = 2
   local markerLabelMap = {}
   for index, _ in pairs(components) do
      local label = index % 100
      if index > 100 and label < 24 then
         local mask = indexMask:eq(index)
         local numErosions
         if label <= 10 then
            numErosions = 3
         else
            numErosions = 3
         end
         for i = 1, numErosions do
            mask = image.erode(mask:double())
         end
         mask = mask:gt(0)
         if ##mask:nonzero() > 0 then
            markers[mask] = markerIndex
            --local indices = mask:nonzero()
            --local mean = torch.round(torch.mean(indices:double(), 1)[1])
            --markers[mean[1]][mean[2]] = markerIndex
            --markers[{{mean[1] - 2, mean[1] + 2}, {mean[2] - 2, mean[2] + 2}}] = markerIndex
            markerLabelMap[markerIndex] = label
            markerIndex = markerIndex + 1
         end
      end
   end

   --markers[rooms:eq(rooms[1][1])] = markerIndex
   local backgroundMask = rooms:eq(rooms[1][1])
   wallMask = wallMask:byte()
   markers[backgroundMask] = -1
   markers[wallMask] = -1
   markers = markers:int()
   cv.watershed{(floorplan:transpose(1, 2):transpose(2, 3) * 255):byte(), markers}
   markers[backgroundMask] = 1
   markers[wallMask] = 0

   --image.save('test/markers.png', utils.drawSegmentation(markers))
   --os.exit(1)
   return markers, markerLabelMap
   --return utils.drawSegmentation(markers:double())
   --return segmentationImage
end


function utils.predictWalls(floorplan)
   if utils.model == nil then
      utils.model = torch.load('/home/chenliu/Projects/Floorplan/models/wall/model_best.t7')
      utils.model.modules[3] = nil
      collectgarbage()
   end

   local width = floorplan:size(3)
   local height = floorplan:size(2)
   local sampleDim = 256
   --local floorplanScaled = image.scale(floorplan, sampleDim, sampleDim)
   local lineWidth = lineWidth or 5

   local model = utils.model
   --model:evaluate()

   --local datasets = require 'datasets/init'
   --local opts = require '../../InverseCAD/opts'
   --local opt = opts.parse(arg)
   package.path = '../InverseCAD/datasets/?.lua;' .. package.path
   package.path = '../InverseCAD/?.lua;' .. package.path
   --local dataset = require('/home/chenliu/Projects/Floorplan/floorplan/InverseCAD/datasets/floorplan-representation')(nil, nil, 'val')
   --local dataset = require('floorplan-representation')(nil, nil, 'val')
   --local dataset = require 'floorplan-representation'({}, nil, 'val')

   local dataset = require('floorplan-representation')
   local floorplanNormalized = dataset:preprocessResize(sampleDim, sampleDim)(floorplan)
   local input = floorplanNormalized:repeatTensor(1, 1, 1, 1):cuda()

   --print(#input)
   local output = model:forward(input)
   print(#output[1])
   local wallMask = output[1][1]:gt(0.5):double()
   --print(#wallMask)
   --image.save('test/wall.png', wallMask)
   wallMask = image.scale(wallMask, width, height, 'simple')
   --image.save('test/wall.png', wallMask)
   --os.exit(1)
   return wallMask:gt(0.5)
end



function utils.segmentFloorplan(floorplan, binaryThreshold, numOpenOperations, reverse, considerEdge)

   --local floorplanBinary = torch.ones((#floorplan)[2], (#floorplan)[3])
   --for c = 1, 3 do
   --local mask = floorplan[c]:lt(binaryThreshold):double()
   --floorplanBinary = torch.cmul(floorplanBinary, mask)
   --end
   local floorplanBinary = floorplan:max(1)[1]:lt(binaryThreshold):double()

   if considerEdge then
      local floorplanGray = floorplan:mean(1)[1]
      local horizontalKernel = torch.zeros(3, 3)
      local verticalKernel = torch.zeros(3, 3)
      for c = 1, 3 do
         horizontalKernel[{2, c}] = 1
         horizontalKernel[{1, c}] = -0.5
         horizontalKernel[{3, c}] = -0.5
         verticalKernel[{c, 2}] = 1
         verticalKernel[{c, 1}] = -0.5
         verticalKernel[{c, 3}] = -0.5
      end
      local horizontalEdgeMap = image.convolve(floorplanGray, horizontalKernel, 'same'):lt(-0.1):double()
      local verticalEdgeMap = image.convolve(floorplanGray, verticalKernel, 'same'):lt(-0.1):double()
      --horizontalEdgeMap = image.erode(image.dilate(horizontalEdgeMap))
      --verticalEdgeMap = image.erode(image.dilate(verticalEdgeMap))
      --image.save('test/edge_1.png', horizontalEdgeMap)
      --image.save('test/edge_2.png', verticalEdgeMap)
      floorplanBinary = (floorplanBinary + horizontalEdgeMap + verticalEdgeMap):gt(0):double()
   end
   --floorplanBinary = image.dilate(floorplanBinary)

   local kernel = torch.ones(3, 3)
   if numOpenOperations > 0 then
      for i = 1, numOpenOperations do
         floorplanBinary = image.erode(floorplanBinary)
         floorplanBinary = image.dilate(floorplanBinary)
      end
   elseif numOpenOperations < 0 then
      for i = 1, -numOpenOperations do
         floorplanBinary = image.dilate(floorplanBinary)
         floorplanBinary = image.erode(floorplanBinary)
      end
   end

   floorplanBinaryByte = (floorplanBinary * 255):byte()
   if reverse ~= nil and reverse then
      floorplanBinaryByte = 255 - floorplanBinaryByte
   end
   local floorplanComponent = torch.IntTensor(floorplanBinaryByte:size())
   local numComponents = cv.connectedComponents{255 - floorplanBinaryByte, floorplanComponent}
   floorplanComponent = floorplanComponent + 1
   return floorplanComponent, numComponents, floorplanBinary
end


function utils.findWalls(floorplan, denotedWalls, lineWidth, lineLength)
   local width = floorplan:size(3)
   local height = floorplan:size(2)

   local lineWidth = lineWidth or 5

   local binaryThreshold = 0.7
   local minLength = lineWidth * 2 or 10
   if denotedWalls == nil then
      local floorplanSegmentationReversed, numSegmentsReversed, floorplanBinaryReversed = utils.segmentFloorplan(floorplan, binaryThreshold, 0, true)
      local backgroundSegmentReversed = floorplanSegmentationReversed[1][1]
      local maxCount = 0
      local borderSegmentReversed
      for segmentReversed = 1, numSegmentsReversed do
         if segmentReversed ~= backgroundSegmentReversed then
            local indices = floorplanSegmentationReversed:eq(segmentReversed):nonzero()
            if ##indices > 0 then
               local count = (#indices)[1]
               if count > maxCount then
                  borderSegmentReversed = segmentReversed
                  maxCount = count
               end
            end
         end
      end
      if borderSegmentReversed then
         local borderMask = floorplanSegmentationReversed:eq(borderSegmentReversed)
         binaryThreshold = torch.max(floorplan, 1)[1][borderMask]:max()
      end
   else
      local denotedWallMask = torch.zeros(height, width)
      for _, wall in pairs(denotedWalls) do
         local mins = {}
         local maxs = {}
         for c = 1, 2 do
            mins[c] = math.min(wall[1][c], wall[2][c])
            maxs[c] = math.max(wall[1][c], wall[2][c])
         end
         denotedWallMask[{{mins[2], max[2]}, {mins[1], max[1]}}] = 1
      end
      binaryThreshold = torch.max(floorplan, 1)[1][denotedWallMask]:mean() + 0.1
   end
   local floorplanSegmentation, numSegments, floorplanBinary = utils.segmentFloorplan(floorplan, binaryThreshold, 0)
   floorplanSegmentation = floorplanSegmentation - 1
   numSegments = numSegments - 1

   --[[
      local floorplanSegmentationReversed, numSegmentsReversed, floorplanBinaryReversed = utils.segmentFloorplan(floorplan, binaryThreshold, 0, true)
      local backgroundSegmentReversed = floorplanSegmentationReversed[1][1]
      if partialWallMask ~= nil then
      floorplanSegmentationReversed = torch.cmul(floorplanSegmentationReversed, partialWallMask)
      end
      local maxCount = 0
      local borderSegmentReversed
      for segmentReversed = 1, numSegmentsReversed do
      if segmentReversed ~= backgroundSegmentReversed then
      local indices = floorplanSegmentationReversed:eq(segmentReversed):nonzero()
      if ##indices > 0 then
      local count = (#indices)[1]
      if count > maxCount then
      borderSegmentReversed = segmentReversed
      maxCount = count
      end
      end
      end
      end
      if borderSegmentReversed == nil then
      return torch.zeros(#floorplan)
      end
      local borderMask = floorplanSegmentationReversed:eq(borderSegmentReversed)
   ]]--
   --local borderMask = floorplanSegmentationReversed:gt(1)


   --local floorplanSegmentation = utils.predictSegmentation(floorplan)
   --local numSegments = torch.max(floorplanSegmentation)

   local borderMask = floorplanSegmentation:eq(0)

   --for i = 1, torch.round((math.max(width, height) / 256 - 1) * 5) do
   --for i = 1, 2 do
   --borderMask = image.erode(borderMask)
   --end

   --[[
      local doorWidth = 5
      for i = 1, doorWidth do
      borderMask = image.dilate(borderMask)
      end
      for i = 1, doorWidth do
      borderMask = image.erode(borderMask)
      end
   ]]--
   local lineLengthMask = torch.zeros(4, height, width)
   for x = 1, width do
      local length = 0
      for y = 1, height do
         if borderMask[y][x] == 1 then
            length = length + 1
            lineLengthMask[1][y][x] = length
         else
            length = 0
         end
      end
      length = 0
      for y = height, 1, -1 do
         if borderMask[y][x] == 1 then
            length = length + 1
            lineLengthMask[3][y][x] = length
         else
            length = 0
         end
      end
   end
   for y = 1, height do
      local length = 0
      for x = 1, width do
         if borderMask[y][x] == 1 then
            length = length + 1
            lineLengthMask[4][y][x] = length
         else
            length = 0
         end
      end
      length = 0
      for x = width, 1, -1 do
         if borderMask[y][x] == 1 then
            length = length + 1
            lineLengthMask[2][y][x] = length
         else
            length = 0
         end
      end
   end

   local minLineWidth = 5
   local maxLineWidth = 15
   local minLineLength = 20
   --local maxLineWidth = 15
   --local minLineLength = 20

   local horizontalLineLengthMask = lineLengthMask[2] + lineLengthMask[4] - 1
   local verticalLineLengthMask = lineLengthMask[1] + lineLengthMask[3] - 1
   local lineTypeMask = torch.zeros(height, width)
   lineTypeMask[torch.cmul(torch.cmul(verticalLineLengthMask:ge(minLineWidth), verticalLineLengthMask:le(maxLineWidth)), horizontalLineLengthMask:ge(minLineLength))] = 1
   lineTypeMask[torch.cmul(torch.cmul(horizontalLineLengthMask:ge(minLineWidth), horizontalLineLengthMask:le(maxLineWidth)), verticalLineLengthMask:ge(minLineLength))] = 2


   --local minLineWidth = 5
   local maxDoorWidth = 8
   local minDoorLength = 15
   local backgroundSegment = floorplanSegmentation[1][1]
   for segment = 1, numSegments do
      if segment ~= backgroundSegment then
         local mask = floorplanSegmentation:eq(segment)
         local indices = floorplanSegmentation:eq(segment):nonzero()
         if ##indices > 0 then
            local mins = torch.min(indices, 1)[1]
            local maxs = torch.max(indices, 1)[1]
            for c = 1, 2 do
               if maxs[c] - mins[c] <= maxDoorWidth and maxs[3 - c] - mins[3 - c] >= minDoorLength then
                  lineTypeMask[mask] = c
                  borderMask[mask] = 1
               end
            end
         end
      end
   end

   local pointLineTypeMask = torch.zeros(4, height, width)
   for x = 1, width do
      local lineExists = false
      for y = 1, height do
         if lineTypeMask[y][x] == 2 then
            lineExists = true
         end
         if borderMask[y][x] == 1 then
            if lineExists then
               pointLineTypeMask[1][y][x] = 1
            end
         else
            lineExists = false
         end
      end
      lineExists = false
      for y = height, 1, -1 do
         if lineTypeMask[y][x] == 2 then
            lineExists = true
         end
         if borderMask[y][x] == 1 then
            if lineExists then
               pointLineTypeMask[3][y][x] = 1
            end
         else
            lineExists = false
         end
      end
   end
   for y = 1, height do
      local lineExists = false
      for x = 1, width do
         if lineTypeMask[y][x] == 1 then
            lineExists = true
         end
         if borderMask[y][x] == 1 then
            if lineExists then
               pointLineTypeMask[4][y][x] = 1
            end
         else
            lineExists = false
         end
      end
      lineExists = false
      for x = width, 1, -1 do
         if lineTypeMask[y][x] == 1 then
            lineExists = true
         end
         if borderMask[y][x] == 1 then
            if lineExists then
               pointLineTypeMask[2][y][x] = 1
            end
         else
            lineExists = false
         end
      end
   end

   local pointMask = torch.cmul(pointLineTypeMask[1] + pointLineTypeMask[3], pointLineTypeMask[2] + pointLineTypeMask[4]):gt(0)


   pointMask = image.erode(pointMask)
   pointMask = image.dilate(pointMask)
   pointMask = image.dilate(pointMask)

   local pointIndexedMask, numPoints = utils.findConnectedComponents(pointMask)

   local points = {}
   for pointIndex = 1, numPoints do
      local indices = pointIndexedMask:eq(pointIndex):nonzero()
      if ##indices > 0 then
         local means = torch.mean(indices:double(), 1)[1]
         local x = torch.round(means[2])
         local y = torch.round(means[1])
         local lineTypes = pointLineTypeMask[{{}, y, x}]

         local pointType = lineTypes:sum()
         local pointOrientation
         if pointType == 2 then
            if lineTypes[1] == 1 then
               if lineTypes[2] == 1 then
                  pointOrientation = 2
               elseif lineTypes[4] == 1 then
                  pointOrientation = 1
               end
            elseif lineTypes[3] == 1 then
               if lineTypes[2] == 1 then
                  pointOrientation = 3
               elseif lineTypes[4] == 1 then
                  pointOrientation = 4
               end
            end
         elseif pointType == 3 then
            for c = 1, 4 do
               if lineTypes[c] == 0 then
                  pointOrientation = c
               end
            end
         elseif pointType == 4 then
            pointOrientation = 1
         end
         if pointOrientation then
            table.insert(points, {{x, y}, {x, y}, {'point', pointType, pointOrientation}})
            --print('(' .. x .. ', ' .. y .. ')\t' .. pointType .. ' ' .. pointOrientation)
         end
      end
   end


   --[[
      image.save('test/border.png', borderMask:double())
      image.save('test/segmentation.png', utils.drawSegmentation(floorplanSegmentation))
      for c = 1, 4 do
      image.save('test/points_' .. c .. '.png', pointLineTypeMask[c]:double())
      end
      image.save('test/points.png', pointMask:double())
   ]]--

   local walls = utils.pointsToLines(width, height, points, lineWidth)

   return walls, points
end

function utils.invertFloorplanHeuristic(floorplan)
   pl.dir.makepath('test/')

   local width = floorplan:size(3)
   local height = floorplan:size(2)

   local lineWidth = lineWidth or 5

   local binaryThreshold = 0.7

   if denotedWalls == nil then
      local floorplanSegmentationReversed, numSegmentsReversed, floorplanBinaryReversed = utils.segmentFloorplan(floorplan, binaryThreshold, 0, true)
      local backgroundSegmentReversed = floorplanSegmentationReversed[1][1]
      local maxCount = 0
      local borderSegmentReversed
      for segmentReversed = 1, numSegmentsReversed do
         if segmentReversed ~= backgroundSegmentReversed then
            local indices = floorplanSegmentationReversed:eq(segmentReversed):nonzero()
            if ##indices > 0 then
               local count = (#indices)[1]
               if count > maxCount then
                  borderSegmentReversed = segmentReversed
                  maxCount = count
               end
            end
         end
      end
      if borderSegmentReversed then
         local borderMask = floorplanSegmentationReversed:eq(borderSegmentReversed)
         binaryThreshold = torch.max(floorplan, 1)[1][borderMask]:max()
      end
   else
      local denotedWallMask = torch.zeros(height, width)
      for _, wall in pairs(denotedWalls) do
         local mins = {}
         local maxs = {}
         for c = 1, 2 do
            mins[c] = math.min(wall[1][c], wall[2][c])
            maxs[c] = math.max(wall[1][c], wall[2][c])
         end
         denotedWallMask[{{mins[2], max[2]}, {mins[1], max[1]}}] = 1
      end
      binaryThreshold = torch.max(floorplan, 1)[1][denotedWallMask]:mean() + 0.1
   end
   local floorplanSegmentation, numSegments, floorplanBinary = utils.segmentFloorplan(floorplan, binaryThreshold, 0)
   floorplanSegmentation = floorplanSegmentation - 1
   numSegments = numSegments - 1

   local borderMask = floorplanSegmentation:eq(0)

   local maxDoorWidth = 8
   local minDoorLength = 15
   local backgroundSegment = floorplanSegmentation[1][1]
   --local doorMask = torch.zeros(height, width)
   for segment = 1, numSegments do
      if segment ~= backgroundSegment then
         local mask = floorplanSegmentation:eq(segment)
         local indices = floorplanSegmentation:eq(segment):nonzero()
         if ##indices > 0 then
            local mins = torch.min(indices, 1)[1]
            local maxs = torch.max(indices, 1)[1]
            for c = 1, 2 do
               if maxs[c] - mins[c] <= maxDoorWidth and maxs[3 - c] - mins[3 - c] >= minDoorLength then
                  local borderOverlap = torch.cmul(image.dilate(mask), borderMask):nonzero()
                  if ##borderOverlap > 0 then
                     borderMask[mask] = 1
                     --doorMask[mask] = 1
                     break
                  end
               end
            end
         end
      end
   end


   local lineLengthMask = torch.zeros(4, height, width)
   for x = 1, width do
      local length = 0
      for y = 1, height do
         if borderMask[y][x] == 1 then
            length = length + 1
            lineLengthMask[1][y][x] = length
         else
            length = 0
         end
      end
      length = 0
      for y = height, 1, -1 do
         if borderMask[y][x] == 1 then
            length = length + 1
            lineLengthMask[3][y][x] = length
         else
            length = 0
         end
      end
   end
   for y = 1, height do
      local length = 0
      for x = 1, width do
         if borderMask[y][x] == 1 then
            length = length + 1
            lineLengthMask[4][y][x] = length
         else
            length = 0
         end
      end
      length = 0
      for x = width, 1, -1 do
         if borderMask[y][x] == 1 then
            length = length + 1
            lineLengthMask[2][y][x] = length
         else
            length = 0
         end
      end
   end


   local minLineWidth = 5
   local maxLineWidth = 15
   local minLineLength = 20
   --local maxLineWidth = 15
   --local minLineLength = 20

   local horizontalLineLengthMask = lineLengthMask[2] + lineLengthMask[4] - 1
   local verticalLineLengthMask = lineLengthMask[1] + lineLengthMask[3] - 1

   local lineTypeMask = torch.zeros(height, width)
   local verticalLineMask = torch.cmul(torch.cmul(verticalLineLengthMask:ge(minLineWidth), verticalLineLengthMask:le(maxLineWidth)), horizontalLineLengthMask:ge(minLineLength))
   verticalLineMask = image.erode(verticalLineMask)
   verticalLineMask = image.dilate(verticalLineMask)
   lineTypeMask[verticalLineMask] = 1

   local horizontalLineMask = torch.cmul(torch.cmul(horizontalLineLengthMask:ge(minLineWidth), horizontalLineLengthMask:le(maxLineWidth)), verticalLineLengthMask:ge(minLineLength))
   horizontalLineMask = image.erode(horizontalLineMask)
   horizontalLineMask = image.dilate(horizontalLineMask)
   lineTypeMask[horizontalLineMask] = 2


   local pointLineTypeMask = torch.zeros(4, height, width)
   for x = 1, width do
      local lineExists = false
      for y = 1, height do
         if lineTypeMask[y][x] == 2 then
            lineExists = true
         end
         if borderMask[y][x] == 1 then
            if lineExists then
               pointLineTypeMask[1][y][x] = 1
            end
         else
            lineExists = false
         end
      end
      lineExists = false
      for y = height, 1, -1 do
         if lineTypeMask[y][x] == 2 then
            lineExists = true
         end
         if borderMask[y][x] == 1 then
            if lineExists then
               pointLineTypeMask[3][y][x] = 1
            end
         else
            lineExists = false
         end
      end
   end
   for y = 1, height do
      local lineExists = false
      for x = 1, width do
         if lineTypeMask[y][x] == 1 then
            lineExists = true
         end
         if borderMask[y][x] == 1 then
            if lineExists then
               pointLineTypeMask[4][y][x] = 1
            end
         else
            lineExists = false
         end
      end
      lineExists = false
      for x = width, 1, -1 do
         if lineTypeMask[y][x] == 1 then
            lineExists = true
         end
         if borderMask[y][x] == 1 then
            if lineExists then
               pointLineTypeMask[2][y][x] = 1
            end
         else
            lineExists = false
         end
      end
   end

   local pointMask = torch.cmul(pointLineTypeMask[1] + pointLineTypeMask[3], pointLineTypeMask[2] + pointLineTypeMask[4]):gt(0)


   pointMask = image.erode(pointMask)
   pointMask = image.dilate(pointMask)
   pointMask = image.dilate(pointMask)

   local pointIndexedMask, numPoints = utils.findConnectedComponents(pointMask)

   local points = {}
   for pointIndex = 1, numPoints do
      local indices = pointIndexedMask:eq(pointIndex):nonzero()
      if ##indices > 0 then
         local means = torch.mean(indices:double(), 1)[1]
         local x = torch.round(means[2])
         local y = torch.round(means[1])
         local lineTypes = pointLineTypeMask[{{}, y, x}]

         local pointType = lineTypes:sum()
         local pointOrientation
         if pointType == 2 then
            if lineTypes[1] == 1 then
               if lineTypes[2] == 1 then
                  pointOrientation = 2
               elseif lineTypes[4] == 1 then
                  pointOrientation = 1
               end
            elseif lineTypes[3] == 1 then
               if lineTypes[2] == 1 then
                  pointOrientation = 3
               elseif lineTypes[4] == 1 then
                  pointOrientation = 4
               end
            end
         elseif pointType == 3 then
            for c = 1, 4 do
               if lineTypes[c] == 0 then
                  pointOrientation = c
               end
            end
         elseif pointType == 4 then
            pointOrientation = 1
         end
         if pointOrientation then
            table.insert(points, {{x, y}, {x, y}, {'point', pointType, pointOrientation}})
            --print('(' .. x .. ', ' .. y .. ')\t' .. pointType .. ' ' .. pointOrientation)
         end
      end
   end


   --[[
      image.save('test/border.png', borderMask:double())
      image.save('test/segmentation.png', utils.drawSegmentation(floorplanSegmentation))
      for c = 1, 4 do
      image.save('test/points_' .. c .. '.png', pointLineTypeMask[c]:double())
      end
      image.save('test/points.png', pointMask:double())
   ]]--

   local walls, lineJunctionsMap = utils.pointsToLines(width, height, points, lineWidth)

   -- borderMask = image.erode(borderMask)
   -- borderMask = image.dilate(borderMask)
   -- borderMask = image.erode(borderMask)
   -- borderMask = image.dilate(borderMask)


   -- local minLineWidth = 1
   -- local maxLineWidth = 10
   -- local minLineLength = 20

   -- -- local horizontalLineLengthMask = lineLengthMask[2] + lineLengthMask[4] - 1
   -- -- local verticalLineLengthMask = lineLengthMask[1] + lineLengthMask[3] - 1
   -- -- local lineTypeMask = torch.zeros(height, width)
   -- -- lineTypeMask[torch.cmul(torch.cmul(verticalLineLengthMask:ge(5), verticalLineLengthMask:le(15)), horizontalLineLengthMask:ge(minLineLength))] = 1
   -- -- lineTypeMask[torch.cmul(torch.cmul(horizontalLineLengthMask:ge(5), horizontalLineLengthMask:le(15)), verticalLineLengthMask:ge(minLineLength))] = 2

   -- local points = {}
   -- local pointOrientations = {{{3}, {4}, {1}, {2}}, {{4, 1}, {1, 2}, {2, 3}, {3, 4}}, {{2, 3, 4}, {3, 4, 1}, {4, 1, 2}, {1, 2, 3}}, {{1, 2, 3, 4}}}
   -- for pointType, orientationMaps in pairs(pointOrientations) do
   --    local numOrientations = 4
   --    if pointType == 4 then
   --       numOrientations = 1
   --    end
   --    for pointOrientation, orientations in pairs(orientationMaps) do
   -- 	 local mask = torch.ones(height, width):byte()
   -- 	 local orientationMask = {}
   -- 	 for _, orientation in pairs(orientations) do
   -- 	    mask:cmul(lineLengthMask[orientation]:ge(minLineLength))
   --          orientationMask[orientation] = true
   -- 	 end
   -- 	 for orientation = 1, numOrientations do
   -- 	    if not orientationMask[orientation] then
   -- 	       mask:cmul(lineLengthMask[orientation]:le(maxLineWidth))
   -- 	       mask:cmul(lineLengthMask[orientation]:gt(minLineWidth))
   --          end
   -- 	 end
   -- 	 --mask = image.dilate(mask)
   -- 	 mask = image.dilate(mask)
   -- 	 mask = image.erode(mask)
   -- 	 mask = image.erode(mask)
   -- 	 -- mask = image.erode(mask)
   -- 	 -- mask = image.erode(mask)
   --       local pointMask, numPoints = utils.findConnectedComponents(mask)
   --       image.save('test/points_' .. pointType .. '_' .. pointOrientation .. '.png', pointMask)
   -- 	 for pointIndex = 1, numPoints - 1 do
   -- 	    local indices = pointMask:eq(pointIndex):nonzero()
   -- 	    local means = indices:double():mean(1)[1]
   -- 	    local maxs = indices:max(1)[1]
   -- 	    local mins = indices:min(1)[1]

   -- 	    if maxs[1] - mins[1] <= maxLineWidth * 2 and maxs[2] - mins[2] <= maxLineWidth * 2 then
   -- 	       table.insert(points, {{means[2], means[1]}, {means[2], means[1]}, {'point', pointType, pointOrientation}})
   -- 	    else
   -- 	       if maxs[1] - mins[1] > maxLineWidth * 2 then
   -- 		  table.insert(points, {{means[2], mins[1] + lineWidth}, {means[2], mins[1] + lineWidth}, {'point', pointType, pointOrientation}})
   -- 		  table.insert(points, {{means[2], maxs[1] - lineWidth}, {means[2], maxs[1] - lineWidth}, {'point', pointType, pointOrientation}})
   -- 	       end
   -- 	       if maxs[2] - mins[2] > maxLineWidth * 2 then
   -- 		  table.insert(points, {{mins[2] + lineWidth, means[1]}, {mins[2] + lineWidth, means[1]}, {'point', pointType, pointOrientation}})
   -- 		  table.insert(points, {{maxs[2] - lineWidth, means[1]}, {maxs[2] - lineWidth, means[1]}, {'point', pointType, pointOrientation}})
   -- 	       end
   -- 	    end
   -- 	 end
   --    end
   -- end


   -- local mask = torch.ones(height, width):byte()
   -- mask:cmul(lineLengthMask[1]:ge(minLineLength))
   -- mask:cmul(lineLengthMask[2]:ge(minLineLength))
   -- image.save('test/mask_1.png', mask:double())
   -- mask:cmul(lineLengthMask[3]:le(maxLineWidth))
   -- mask:cmul(lineLengthMask[4]:le(maxLineWidth))
   -- image.save('test/mask_2.png', mask:double())
   -- mask:cmul(lineLengthMask[3]:ge(minLineWidth))
   -- mask:cmul(lineLengthMask[4]:ge(minLineWidth))
   -- image.save('test/mask_3.png', mask:double())
   -- image.save('test/floorplan.png', floorplan)

   -- local walls, lineJunctionsMap = utils.pointsToLines(width, height, points, lineWidth, true)

   -- local maxPooling = nn.SpatialMaxPooling(lineWidth * 2 + 1, lineWidth * 2 + 1, 1, 1, lineWidth, lineWidth)
   -- lineLengthMask = maxPooling:forward(lineLengthMask)

   -- local newWalls = {}
   -- local invalidPointMask = {}
   -- for wallIndex, wall in pairs(walls) do
   --    local lineDim = utils.lineDim(wall)
   --    local endPoints = {}
   --    if lineDim == 1 then
   -- 	 endPoints = {2, 4}
   --    else
   -- 	 endPoints = {3, 1}
   --    end
   --    local lineLength = wall[2][lineDim] - wall[1][lineDim]
   --    local invalid = false
   --    for i = 1, 2 do
   -- 	 if lineLengthMask[endPoints[i]][wall[i][2]][wall[i][1]] < lineLength - lineWidth then
   -- 	    invalid = true
   -- 	    invalidPointMask[lineJunctionsMap[wallIndex][1]] = true
   -- 	    invalidPointMask[lineJunctionsMap[wallIndex][2]] = true
   --          --print(wall)
   -- 	    --print(lineLength)
   -- 	    --print(lineLengthMask[endPoints[i]][wall[i][2]][wall[i][1]])
   -- 	    break
   -- 	 end
   --    end
   --    if not invalid then
   --       table.insert(newWalls, wall)
   --    end
   -- end

   local wallMask = utils.drawLineMask(width, height, walls, lineWidth)
   local segments, numSegments = utils.findConnectedComponents(wallMask)
   local rooms, numRooms = utils.findConnectedComponents(1 - wallMask)

   local backgroundRoomIndex
   local imageCorners = {{1, 1}, {width, 1}, {width, height}, {1, height}}
   for _, imageCorner in pairs(imageCorners) do
      local roomIndex = rooms[imageCorner[2]][imageCorner[1]]
      if roomIndex > 0 then
         if not backgroundRoomIndex then
            backgroundRoomIndex = roomIndex
         elseif roomIndex ~= backgroundRoomIndex then
            rooms[rooms:eq(roomIndex)] = backgroundRoomIndex
         end
      end
   end

   if backgroundRoomIndex then
      local backgroundMask = rooms:eq(backgroundRoomIndex)
      backgroundMask = image.dilate(backgroundMask)
      local backgroundSegmentIndices = torch.cmul(segments, backgroundMask:int()):nonzero()
      if ##backgroundSegmentIndices > 0 then
         local backgroundSegments = {}
         for i = 1, backgroundSegmentIndices:size(1) do
            backgroundSegments[segments[backgroundSegmentIndices[i][1]][backgroundSegmentIndices[i][2]]] = true
         end
         local lineMask = torch.zeros(height, width)
         for segmentIndex, _ in pairs(backgroundSegments) do
            lineMask[segments:eq(segmentIndex)] = 1
         end
         local newPoints = {}
         for pointIndex, point in pairs(points) do
            if lineMask[point[1][2]][point[1][1]] > 0 then
               table.insert(newPoints, point)
            end
         end
         points = newPoints
      end
   end

   local doorMask = torch.cmul((borderMask - floorplanSegmentation:eq(0)):double(), wallMask)
   doorMask = image.dilate(doorMask)
   doorMask = image.dilate(doorMask)
   doorMask = image.erode(doorMask)
   doorMask = image.erode(doorMask)
   local doorsMask, numDoors = utils.findConnectedComponents(doorMask)
   local wallMaskIndexed = utils.drawLineMask(width, height, walls, lineWidth, true)
   local doors = {}
   for doorIndex = 1, numDoors - 1 do
      local doorIndices = doorsMask:eq(doorIndex):nonzero()
      local wallPoints = {}
      for i = 1, doorIndices:size(1) do
         local x = doorIndices[i][2]
         local y = doorIndices[i][1]
         local wallIndex = wallMaskIndexed[y][x]
         if not wallPoints[wallIndex] then
            wallPoints[wallIndex] = {}
         end
         table.insert(wallPoints[wallIndex], {x, y})
      end
      for wallIndex, doorPoints in pairs(wallPoints) do
         local minX, maxX, minY, maxY
         for _, point in pairs(doorPoints) do
            local x = point[1]
            local y = point[2]
            if not minX or x < minX then
               minX = x
            end
            if not maxX or x > maxX then
               maxX = x
            end
            if not minY or y < minY then
               minY = y
            end
            if not maxY or y > maxY then
               maxY = y
            end
         end

         if maxX - minX > math.max(maxY - minY, minDoorLength) then
            table.insert(doors, {{minX, (minY + maxY) / 2}, {maxX, (minY + maxY) / 2}, {'door', 1, 1}})
         elseif maxY - minY > math.max(maxX - minX, minDoorLength) then
            table.insert(doors, {{(minX + maxX) / 2, minY}, {(minX + maxX) / 2, maxY}, {'door', 1, 2}})
         end
      end
   end

   --image.save('test/walls.png', utils.drawLineMask(width, height, walls, lineWidth))
   --image.save('test/walls_new.png', utils.drawLineMask(width, height, newWalls, lineWidth))
   --walls = newWalls
   --points = utils.linesToPoints(width, height, walls, lineWidth)
   --walls = utils.pointsToLines(width, height, walls, lineWidth)
   --walls = utils.linesToPoints(width, height, walls, lineWidth)
   --points = utils.linesToPoints(width, height, walls, lineWidth)
   --print(points)
   --os.exit(1)

   for _, door in pairs(doors) do
      local lineDim = fp_ut.lineDim(door, lineWidth)
      local doorFixedValue = (door[1][3 - lineDim] + door[2][3 - lineDim]) / 2
      local doorMinValue = math.min(door[1][lineDim], door[2][lineDim])
      local doorMaxValue = math.max(door[1][lineDim], door[2][lineDim])
      for _, wall in pairs(walls) do
         if fp_ut.lineDim(wall, lineWidth) == lineDim then
            local wallFixedValue = (wall[1][3 - lineDim] + wall[2][3 - lineDim]) / 2
            local wallMinValue = math.min(wall[1][lineDim], wall[2][lineDim])
            local wallMaxValue = math.max(wall[1][lineDim], wall[2][lineDim])
            if math.abs(doorFixedValue - wallFixedValue) <= lineWidth and math.max(doorMinValue, wallMinValue) < math.min(doorMaxValue, wallMaxValue) then
               door[1][3 - lineDim] = wallFixedValue
               door[2][3 - lineDim] = wallFixedValue
            end
         end
      end
   end

   local representation = {}
   representation.walls = walls
   representation.points = points
   representation.doors = doors
   representation.icons = {}
   representation.labels = {}
   return representation
end

function utils.filterPoints(width, height, points, pointsConfidence, lineWidth, gap)
   local lineWidth = lineWidth or 5
   local gap = gap or lineWidth * 2


   local pointJunctionMap = {}
   local pointOrientations = {}
   for pointIndex, point in pairs(points) do
      pointJunctionMap[pointIndex] = {-1, -1, -1, -1}

      local orientations = {}
      local orientation = point[3][3]
      if point[3][2] == 1 then
         table.insert(orientations, (orientation + 2 - 1) % 4 + 1)
      elseif point[3][2] == 2 then
         table.insert(orientations, orientation)
         table.insert(orientations, (orientation + 3 - 1) % 4 + 1)
      elseif point[3][2] == 3 then
         table.insert(orientations, (orientation + 2 - 1) % 4 + 1)
         --[[
            for i = 1, 4 do
            if i ~= orientation then
            table.insert(orientations, i)
            end
            end
         ]]--
      else
         --[[
            for i = 1, 4 do
            table.insert(orientations, i)
            end
         ]]--
      end
      pointOrientations[pointIndex] = orientations
      for _, orientation in pairs(orientations) do
         pointJunctionMap[pointIndex][orientation] = 0
      end
   end


   for pointIndex, point in pairs(points) do
      local orientations = pointOrientations[pointIndex]

      local x = point[1][1]
      local y = point[1][2]
      for _, orientation in pairs(orientations) do
         if pointJunctionMap[pointIndex][orientation] == 0 then
            local lineDim
            local fixedValue
            local junction
            local startPoint
            if orientation == 1 or orientation == 3 then
               lineDim = 2
               fixedValue = x
               startPoint = y
               if orientation == 1 then
                  junction = 1
               else
                  junction = height
               end
            else
               lineDim = 1
               fixedValue = y
               startPoint = x
               if orientation == 4 then
                  junction = 1
               else
                  junction = width
               end
            end
            local orientationOpposite = (orientation + 2 - 1) % 4 + 1
            local selectedOtherPointIndex
            for otherPointIndex, otherPoint in pairs(points) do
               if otherPointIndex ~= pointIndex and pointJunctionMap[otherPointIndex][orientationOpposite] == 0 then
                  local otherXY = otherPoint[1]
                  if otherXY[lineDim] > math.min(junction, startPoint) and otherXY[lineDim] < math.max(junction, startPoint) and otherXY[3 - lineDim] >= fixedValue - lineWidth and otherXY[3 - lineDim] <= fixedValue + lineWidth then
                     junction = otherXY[lineDim]
                     selectedOtherPointIndex = otherPointIndex
                  end
               end
            end

            local point_1 = {}
            point_1[lineDim] = math.min(startPoint, junction)
            point_1[3 - lineDim] = fixedValue
            local point_2 = {}
            point_2[lineDim] = math.max(startPoint, junction)
            point_2[3 - lineDim] = fixedValue

            if point_1[1] ~= 1 and point_1[1] ~= width and point_1[2] ~= 1 and point_1[2] ~= height and point_2[1] ~= 1 and point_2[1] ~= width and point_2[2] ~= 1 and point_2[2] ~= height then
               --table.insert(lines, {point_1, point_2, {"wall", 1, 1}})
               if selectedOtherPointIndex ~= nil then
                  pointJunctionMap[selectedOtherPointIndex][orientationOpposite] = pointIndex
               end
               pointJunctionMap[pointIndex][orientation] = selectedOtherPointIndex
               --print(pointIndex .. ' ' .. orientation .. ' ' .. selectedOtherPointIndex)
            end
         end
      end
   end

   local removedPoints = {}
   for pointIndex_1, point_1 in pairs(points) do
      if not removedPoints[pointIndex_1] then
         for pointIndex_2, point_2 in pairs(points) do
            if pointIndex_2 > pointIndex_1 and not removedPoints[pointIndex_2] then
               local distance = utils.calcDistance(point_1[1], point_2[1])
               if distance < gap then
                  local confidence_1 = pointsConfidence[pointIndex_1]
                  local confidence_2 = pointsConfidence[pointIndex_2]
                  local isNeighbor = false
                  for orientation, neighborPointIndex in pairs(pointJunctionMap[pointIndex_1]) do
                     if neighborPointIndex > 0 then
                        if neighborPointIndex == pointIndex_2 then
                           isNeighbor = true
                        end
                        confidence_1 = confidence_1 + pointsConfidence[neighborPointIndex]
                     end
                  end
                  for orientation, neighborPointIndex in pairs(pointJunctionMap[pointIndex_2]) do
                     if neighborPointIndex > 0 then
                        confidence_2 = confidence_2 + pointsConfidence[neighborPointIndex]
                     end
                  end
                  if isNeighbor == false then
                     if confidence_1 < confidence_2 then
                        removedPoints[pointIndex_1] = true
                     else
                        removedPoints[pointIndex_2] = true
                     end
                  end
               end
            end
         end
      end
   end
   local newPoints = {}
   for pointIndex, point in pairs(points) do
      if not removedPoints[pointIndex] then
         table.insert(newPoints, point)
      end
   end
   return newPoints
end

function utils.invertFloorplan(model, floorplan, withoutQP, relaxedQP, useStack)
   local lineWidth = lineWidth or 3
   local useStack = useStack or false

   local oriWidth = floorplan:size(3)
   local oriHeight = floorplan:size(2)
   local width = 256
   local height = 256
   local floorplanOri = floorplan:clone()
   image.save('test/floorplan.png', floorplanOri)
   local floorplan = image.scale(floorplan, width, height)


   local junctionHeatmaps, doorHeatmaps, iconHeatmaps, segmentations = utils.estimateHeatmaps(model, floorplanOri:clone(), 'single', useStack)
   --local junctionHeatmaps, doorHeatmaps, iconHeatmaps, _ = utils.estimateHeatmaps(floorplanOri:clone(), 'single', true)


   pl.dir.makepath('test/heatmaps/')
   for i = 1, 13 do
      image.save('test/heatmaps/junction_heatmap_' .. i .. '.png', junctionHeatmaps[i])

   end
   for i = 1, 4 do
      image.save('test/heatmaps/door_heatmap_' .. i .. '.png', doorHeatmaps[i])
      image.save('test/heatmaps/icon_heatmap_' .. i .. '.png', iconHeatmaps[i])
   end


   pl.dir.makepath('test/segmentation/')
   for segmentIndex = 1, 30 do
      image.save('test/segmentation/segment_' .. segmentIndex .. '.png', segmentations[segmentIndex])
   end

   local representation = {}
   py.execute('import os')

   if withoutQP then
      py.execute('os.system("python PostProcessing/QP.py 1")')
      representation.points = utils.loadItems('test/points_out.txt')
      representation.doors = utils.loadItems('test/doors_out.txt')
      representation.icons = utils.loadItems('test/icons_out.txt')
      representation.walls = utils.pointsToLines(oriWidth, oriHeight, representation.points, lineWidth, true)

      local wallMask = utils.drawLineMask(oriWidth, oriHeight, representation.walls, lineWidth)
      --image.save('test/floorplan.png', floorplan)
      --image.save('test/wall_mask.png', wallMask)
      local rooms, numRooms = utils.findConnectedComponents(1 - wallMask)

      local backgroundRoomIndex
      local imageCorners = {{1, 1}, {oriWidth, 1}, {oriWidth, oriHeight}, {1, oriHeight}}
      for _, imageCorner in pairs(imageCorners) do
         local roomIndex = rooms[imageCorner[2]][imageCorner[1]]
         if roomIndex > 0 then
            if not backgroundRoomIndex then
               backgroundRoomIndex = roomIndex
            elseif roomIndex ~= backgroundRoomIndex then
               rooms[rooms:eq(roomIndex)] = backgroundRoomIndex
            end
         end
      end
      if not backgroundRoomIndex then
         backgroundRoomIndex = numRooms
      end
      representation.labels = {}

      for roomIndex = 1, numRooms - 1 do
         if roomIndex ~= backgroundRoomIndex then
            local roomMask = rooms:eq(roomIndex)
            if ##roomMask:nonzero() > 0 then
               local means = roomMask:nonzero():double():mean(1)[1]
               local y = means[1]
               local x = means[2]
               local maxSum
               local maxSumSegmentIndex
               for segmentIndex = 1, 10 do
                  local sum = segmentations[segmentIndex][roomMask]:sum()
                  if not maxSum or sum > maxSum then
                     maxSum = sum
                     maxSumSegmentIndex = segmentIndex
                  end
               end
               if maxSumSegmentIndex then
                  table.insert(representation.labels, {{x - 20, y - 10}, {x + 20, y + 10}, utils.getItemInfo('labels', maxSumSegmentIndex)})
               end
            end
         end
      end
      return representation
   end

   py.execute('os.system("python PostProcessing/QP.py")')


   --os.exit(1)
   local points = utils.loadItems('test/points_out.txt')
   local pointLabelsFile = csvigo.load({path='test/point_labels.txt', mode="large", header=false, separator='\t', verbose=false})
   local pointLabels = {}
   for _, labels in pairs(pointLabelsFile) do
      table.insert(pointLabels, {tonumber(labels[1]), tonumber(labels[2]), tonumber(labels[3]), tonumber(labels[4])})
   end


   representation.points = points

   representation.walls, wallJunctionsMap = utils.pointsToLines(oriWidth, oriHeight, points, lineWidth, true)

   for wallIndex, junctions in pairs(wallJunctionsMap) do
      local lineDim = utils.lineDim(representation.walls[wallIndex])
      local labels_1 = pointLabels[junctions[1]]
      local labels_2 = pointLabels[junctions[2]]
      local label_1, label_2
      if lineDim == 1 then
         label_1 = math.min(labels_1[1], labels_2[4])
         label_2 = math.min(labels_1[2], labels_2[3])
      elseif lineDim == 2 then
         label_1 = math.min(labels_1[3], labels_2[4])
         label_2 = math.min(labels_1[2], labels_2[1])
      end
      if label_1 == 0 then
         label_1 = 11
      end
      if label_2 == 0 then
         label_2 = 11
      end
      table.insert(representation.walls[wallIndex], {label_1, label_2})
   end


   local wallMask = utils.drawLineMask(oriWidth, oriHeight, representation.walls, lineWidth)

   local rooms, numRooms = utils.findConnectedComponents(1 - wallMask)
   --image.save('test/walls_backup.png', wallMask)
   --image.save('test/rooms_backup.png', utils.drawSegmentation(rooms))

   local deltas = {{1, -1}, {1, 1}, {-1, 1}, {-1, -1}}
   local roomLabelsMap = {}
   for pointIndex, point in pairs(points) do
      local roomLabels = {}
      for orientation, delta in pairs(deltas) do
         local label = pointLabels[pointIndex][orientation]
         if label >= 1 then
            local x = torch.round(point[1][1])
            local y = torch.round(point[1][2])
            --x = math.max(math.min(x, width), 1)
            --y = math.max(math.min(y, height), 1)
            for i = 1, 10 do
               if x < 1 or x > oriWidth or y < 1 or y > oriHeight then
                  break
               end
               local roomIndex = rooms[y][x]
               if roomIndex > 0 then
                  if not roomLabels[roomIndex] then
                     roomLabels[roomIndex] = {}
                  end
                  roomLabels[roomIndex][label] = true
                  break
               end
               x = x + delta[1]
               y = y + delta[2]
            end
         end
      end
      for roomIndex, labels in pairs(roomLabels) do
         if not roomLabelsMap[roomIndex] then
            roomLabelsMap[roomIndex] = {}
         end
         for label, _ in pairs(labels) do
            if not roomLabelsMap[roomIndex][label] then
               roomLabelsMap[roomIndex][label] = {}
            end
            local x = point[1][1]
            local y = point[1][2]
            table.insert(roomLabelsMap[roomIndex][label], {x, y})
         end
      end
   end

   representation.labels = {}
   local labelWidth = 50
   local labelHeight = 20
   for roomIndex, labels in pairs(roomLabelsMap) do
      local numLabels = 0
      for label, locations in pairs(labels) do
         numLabels = numLabels + 1
      end
      if numLabels == 1 then
         local means = rooms:eq(roomIndex):nonzero():double():mean(1)[1]
         local y = means[1]
         local x = means[2]
         for label, locations in pairs(labels) do
            table.insert(representation.labels, {{x - labelWidth / 2, y - labelHeight / 2}, {x + labelWidth / 2, y + labelHeight / 2}, utils.getItemInfo('labels', label)})
         end
      else
         for label, locations in pairs(labels) do
            local locationGroupMap = {}
            local groupIndex = 1
            for locationIndex, location in pairs(locations) do
               if not locationGroupMap[locationIndex] then
                  locationGroupMap[locationIndex] = groupIndex
                  local groupLocations = {location}
                  while true do
                     local hasChange = false
                     for _, groupLocation in pairs(groupLocations) do
                        for neighborLocationIndex, neighborLocation in pairs(locations) do
                           if not locationGroupMap[neighborLocationIndex] and (math.abs(neighborLocation[1] - groupLocation[1]) < lineWidth or math.abs(neighborLocation[2] - groupLocation[2]) < lineWidth) then
                              local lineDim = utils.lineDim({groupLocation, neighborLocation}, lineWidth)
                              local fixedValue = torch.round((groupLocation[3 - lineDim] + neighborLocation[3 - lineDim]) / 2)
                              local minValue = torch.round(math.min(groupLocation[lineDim], neighborLocation[lineDim]))
                              local maxValue = torch.round(math.max(groupLocation[lineDim], neighborLocation[lineDim]))
                              local onWall = true
                              for value = minValue, maxValue do
                                 if (lineDim == 1 and wallMask[fixedValue][value] == 0) or (lineDim == 2 and wallMask[value][fixedValue] == 0) then
                                    onWall = false
                                 end
                              end
                              if onWall then
                                 table.insert(groupLocations, neighborLocation)
                                 locationGroupMap[neighborLocationIndex] = groupIndex
                                 hasChange = true
                              end
                           end
                        end
                     end

                     if not hasChange then
                        break
                     end
                  end
                  groupIndex = groupIndex + 1
               end
            end

            for groupIndex = 1, groupIndex - 1 do
               local groupLocations = {}
               for locationIndex, index in pairs(locationGroupMap) do
                  if index == groupIndex then
                     table.insert(groupLocations, locations[locationIndex])
                  end
               end

               if #groupLocations > 2 then
                  local x = 0
                  local y = 0
                  for _, location in pairs(groupLocations) do
                     x = x + location[1]
                     y = y + location[2]
                  end
                  x = x / #groupLocations
                  y = y / #groupLocations

                  table.insert(representation.labels, {{x - labelWidth / 2, y - labelHeight / 2}, {x + labelWidth / 2, y + labelHeight / 2}, utils.getItemInfo('labels', label)})
               end
            end
         end
      end
   end

   representation.doors = utils.loadItems('test/doors_out.txt')
   representation.icons = utils.loadItems('test/icons_out.txt')
   return representation
end

function utils.postprocessRepresentation(width, height, representation)

   local lineWidth = lineWidth or 5
   local lineMask
   if representation.walls then
      lineMask = utils.drawLineMask(width, height, representation.walls, lineWidth)
   else
      local lines = utils.pointsToLines(width, height, representation.points, lineWidth, true)
      local lineMask = utils.drawLineMask(width, height, lines, lineWidth)
   end

   for __, item in pairs(representation.icons) do
      item[3] = utils.getItemInfo('icons', utils.getNumber('icons', item[3]))

      local rectangle = {{math.min(item[1][1], item[2][1]), math.min(item[1][2], item[2][2])}, {math.max(item[1][1], item[2][1]), math.max(item[1][2], item[2][2])}}
      for pointIndex = 1, 2 do
         rectangle[pointIndex][1] = torch.round(math.max(math.min(rectangle[pointIndex][1], width), 1))
         rectangle[pointIndex][2] = torch.round(math.max(math.min(rectangle[pointIndex][2], height), 1))
      end

      local minDistance = math.max(width, height)
      local minDistanceOrientation = 1
      if (math.abs(rectangle[2][1] - rectangle[1][1]) > math.abs(rectangle[2][2] - rectangle[1][2]) and item[3][1] ~= 'toilet' and item[3][1] ~= 'stairs') or (math.abs(rectangle[2][1] - rectangle[1][1]) < math.abs(rectangle[2][2] - rectangle[1][2]) and (item[3][1] == 'toilet' or item[3][1] == 'stairs')) or item[3][1] == 'washing_basin' then
         local min = math.min(rectangle[1][2], rectangle[2][2])
         local max = math.max(rectangle[1][2], rectangle[2][2])
         local center = (rectangle[1][1] + rectangle[2][1]) / 2
         local deltaMin = 0
         for delta = 1, min - 1 do
            deltaMin = delta
            if lineMask[min - delta][center] == 1 then
               break
            end
         end
         local deltaMax = 0
         for delta = 1, height - max do
            deltaMax = delta
            if lineMask[max + delta][center] == 1 then
               break
            end
         end

         if deltaMax < minDistance then
            minDistance = deltaMax
            minDistanceOrientation = 1
         end
         if deltaMin < minDistance then
            minDistance = deltaMin
            minDistanceOrientation = 3
         end
      end

      if (math.abs(rectangle[2][1] - rectangle[1][1]) < math.abs(rectangle[2][2] - rectangle[1][2]) and item[3][1] ~= 'toilet') or (math.abs(rectangle[2][1] - rectangle[1][1]) > math.abs(rectangle[2][2] - rectangle[1][2]) and item[3][1] == 'toilet') or item[3][1] == 'washing_basin' then
         local min = math.min(rectangle[1][1], rectangle[2][1])
         local max = math.max(rectangle[1][1], rectangle[2][1])
         local center = (rectangle[1][2] + rectangle[2][2]) / 2
         local deltaMin = 0
         for delta = 1, min - 1 do
            deltaMin = delta
            if lineMask[center][min - delta] == 1 then
               break
            end
         end
         local deltaMax = 0
         for delta = 1, width - max do
            deltaMax = delta
            if lineMask[center][max + delta] == 1 then
               break
            end
         end

         if deltaMax < minDistance then
            minDistance = deltaMax
            minDistanceOrientation = 4
         end
         if deltaMin < minDistance then
            minDistance = deltaMin
            minDistanceOrientation = 2
         end
      end

      item[3][3] = minDistanceOrientation
   end
end

function utils.findWallsPrediction(floorplan)
   local lineWidth = lineWidth or 5
   local oriWidth = floorplan:size(3)
   local oriHeight = floorplan:size(2)
   local width = 256
   local height = 256
   local floorplanOri = floorplan:clone()
   local floorplan = image.scale(floorplan, width, height)


   local useStack = false
   if utils.modelWall == nil then
      if useStack then
         utils.modelJunction = torch.load('/home/chenliu/Projects/Floorplan/models/junction-wall-stack-16/model_best.t7')
      else
         utils.modelJunction = torch.load('/home/chenliu/Projects/Floorplan/models/junction-heatmap/model_best.t7')
      end
   end


   local sampleDim = 256
   local gridDim = 8
   local numAnchorBoxes = 13
   local nClasses = 13
   --local floorplanScaled = image.scale(floorplan, sampleDim, sampleDim)

   --model:evaluate()

   --local datasets = require 'datasets/init'
   --local opts = require '../../InverseCAD/opts'
   --local opt = opts.parse(arg)
   package.path = '../InverseCAD/datasets/?.lua;' .. package.path
   package.path = '../InverseCAD/?.lua;' .. package.path
   --local dataset = require('/home/chenliu/Projects/Floorplan/floorplan/InverseCAD/datasets/floorplan-representation')(nil, nil, 'val')
   --local dataset = require('floorplan-representation')(nil, nil, 'val')
   --local dataset = require 'floorplan-representation'({}, nil, 'val')

   local dataset = require('floorplan-representation')
   local floorplanNormalized = dataset:preprocessResize(sampleDim, sampleDim)(floorplan)
   local input = floorplanNormalized:repeatTensor(1, 1, 1, 1):cuda()

   --print(#input)
   local output = utils.modelJunction:forward(input)
   local wallsResult
   local labelsResult

   image.save('test/floorplan.png', floorplanOri)

   for stackIndex = 1, 2 do
      local prediction
      if useStack then
         prediction = output[stackIndex][1]
      else
         prediction = output[1]
      end

      --print(torch.max(prediction))
      --print(torch.min(prediction))
      local points = {}
      local pointsConfidence = {}
      local pointLabels = {}
      for i = 1, 13 do
         --print(i)
         local pointMask = prediction[i]:double():gt(0.5)
         pointMask = image.erode(pointMask)
         --pointMask = image.erode(pointMask)
         if ##pointMask:nonzero() > 0 then
            local components, numComponents = utils.findConnectedComponents(pointMask)
            --image.save('test/mask_' .. i .. '.png', pointMask:double())
            --image.save('test/mask_' .. i .. '.png', utils.drawSegmentation(components))
            numComponents = numComponents - 1
            --print(torch.max(components) .. ' ' .. numComponents)
            local itemInfo = utils.getItemInfo('points', i)
            for componentIndex = 1, numComponents do
               local indices = components:eq(componentIndex):nonzero()
               local mean = torch.mean(indices:double(), 1)[1]
               --print(mean)
               local x = mean[2] / width * oriWidth
               local y = mean[1] / height * oriHeight
               table.insert(points, {{x, y}, {x, y}, itemInfo})

               x = math.max(math.min(torch.round(mean[2]), width), 1)
               y = math.max(math.min(torch.round(mean[1]), height), 1)
               table.insert(pointsConfidence, prediction[i][y][x])
            end
         end
      end
      --points = utils.filterPoints(width, height, points, pointsConfidence, lineWidth)
      --os.exit(1)

      local walls = utils.pointsToLines(oriWidth, oriHeight, points, lineWidth)
      --wallsResult = walls
      local wallMask = utils.drawLineMask(oriWidth, oriHeight, walls, lineWidth)

      if true then
         wallMask:mul(0.3)
         wallMask = wallMask:repeatTensor(3, 1, 1)
         local junctionMasks = utils.drawJunctionMasks(oriWidth, oriHeight, points, #points)
         for i = 1, junctionMasks:size(1) do
            for c = 1, 3 do
               wallMask[c][junctionMasks[i]:gt(0)] = torch.uniform()
            end
         end
      end

      if useStack then
         image.save('test/junction_' .. stackIndex .. '.png', image.scale(wallMask, oriWidth, oriHeight))
      else
         image.save('test/junction.png', image.scale(wallMask, oriWidth, oriHeight))
      end

      if true then
         local wallMask = torch.ones(oriHeight, oriWidth)
         if useStack then
            wallMask = image.scale(prediction[14]:double(), oriWidth, oriHeight, 'simple')
         else
            if utils.modelWall == nil then
               utils.modelWall = torch.load('/home/chenliu/Projects/Floorplan/models/wall/model_best.t7')
            end
            wallMask = image.scale(utils.modelWall:forward(input)[1]:double(), oriWidth, oriHeight, 'simple')
         end
         image.save('test/wall.png', wallMask)

         utils.saveRepresentation('test/points.txt', {points = points})

         local representation = {}
         representation.points = points
         representation.doors = {}
         representation.icons = {}
         representation.labels = {}



         if true then
            pl.dir.makepath('test/segmentation/')
            if utils.modelSegmentation == nil then
               utils.modelSegmentation = torch.load('/home/chenliu/Projects/Floorplan/models/segmentation/model_best.t7')
            end
            local outputSegmentation = utils.modelSegmentation:forward(input)
            local prob, predictionSegmentation = torch.max(outputSegmentation, 2)
            predictionSegmentation = predictionSegmentation[{{}, 1}]:view(sampleDim, sampleDim)
            for segmentIndex = 1, 10 do
               image.save('test/segmentation/segment_' .. segmentIndex .. '.png', image.scale(predictionSegmentation:eq(segmentIndex):double(), oriWidth, oriHeight, 'simple'))
            end
            local backgroundSegmentIndex = 26
            image.save('test/segmentation/segment_0.png', image.scale(predictionSegmentation:eq(backgroundSegmentIndex):double(), oriWidth, oriHeight, 'simple'))
         end

         if false then
            if utils.modelDoor == nil then
               utils.modelDoor = torch.load('/home/chenliu/Projects/Floorplan/models/anchor-junction-door/model_best.t7')
            end
            local outputDoor = utils.modelDoor:forward(input)

            local coordinates = outputDoor[1]:double():transpose(2, 3):transpose(3, 4):contiguous()
            coordinates = coordinates:view(coordinates:size(1), coordinates:size(2), coordinates:size(3), -1, 4)
            local objectness = outputDoor[2]:double():transpose(2, 3):transpose(3, 4):contiguous()
            objectness = objectness:view(objectness:size(1), objectness:size(2), objectness:size(3), objectness:size(4), 1)
            local prob, pred = torch.max(outputDoor[3]:double(), 2)
            pred = pred[{{}, 1}]:view(-1, gridDim, gridDim, numAnchorBoxes, 1):double()
            pred[pred:eq(nClasses + 1)] = 0
            local representationTensors = torch.cat(torch.cat(coordinates, pred:gt(0):double(), 5), pred, 5)
            local representationTensor = representationTensors[1]
            representationTensor = torch.cat(torch.cat(torch.zeros(representationTensor:size(1), representationTensor:size(2), nClasses, representationTensor:size(4)), representationTensor:double(), 3), torch.zeros(representationTensor:size(1), representationTensor:size(2), nClasses * 2, representationTensor:size(4)), 3)
            local representationPrediction = utils.convertTensorAnchorToRepresentation(sampleDim, sampleDim, representationTensor, 0.1)
            representationPrediction= utils.scaleRepresentation(representationPrediction, sampleDim, sampleDim, oriWidth, oriHeight)

            representation.doors = representationPrediction.doors
         end

         if false then
            if utils.modelIcon == nil then
               utils.modelIcon = torch.load('/home/chenliu/Projects/Floorplan/models/anchor-junction-icon-64/model_best.t7')
            end
            local outputIcon = utils.modelIcon:forward(input)

            local coordinates = outputIcon[1]:double():transpose(2, 3):transpose(3, 4):contiguous()
            coordinates = coordinates:view(coordinates:size(1), coordinates:size(2), coordinates:size(3), -1, 4)
            local objectness = outputIcon[2]:double():transpose(2, 3):transpose(3, 4):contiguous()
            objectness = objectness:view(objectness:size(1), objectness:size(2), objectness:size(3), objectness:size(4), 1)
            local prob, pred = torch.max(outputIcon[3]:double(), 2)
            pred = pred[{{}, 1}]:view(-1, gridDim, gridDim, numAnchorBoxes, 1):double()
            pred[pred:eq(nClasses + 1)] = 0
            local representationTensors = torch.cat(torch.cat(coordinates, pred:gt(0):double(), 5), pred, 5)
            local representationTensor = representationTensors[1]
            representationTensor = torch.cat(torch.cat(torch.zeros(representationTensor:size(1), representationTensor:size(2), nClasses * 2, representationTensor:size(4)), representationTensor:double(), 3), torch.zeros(representationTensor:size(1), representationTensor:size(2), nClasses, representationTensor:size(4)), 3)
            local representationPrediction = utils.convertTensorAnchorToRepresentation(sampleDim, sampleDim, representationTensor, 0.1)
            representationPrediction= utils.scaleRepresentation(representationPrediction, sampleDim, sampleDim, oriWidth, oriHeight)

            representation.icons = representationPrediction.icons
         end

         utils.saveRepresentation('test/representation.txt', representation)

         --if false then
         --utils.filterJunctions(oriWidth, oriHeight, points, wallMask)
         --end

         py.execute('import os')
         py.execute('os.system("python ../InverseCAD/PostProcessing/QP_backup.py")')
         --os.exit(1)
         points = utils.loadItems('test/points_out.txt')
         if true then
            local pointLabelsFile = csvigo.load({path='test/point_labels.txt', mode="large", header=false, separator='\t', verbose=false})
            pointLabels = {}
            for _, labels in pairs(pointLabelsFile) do
               table.insert(pointLabels, {tonumber(labels[1]), tonumber(labels[2]), tonumber(labels[3]), tonumber(labels[4])})
            end
         end

         --os.exit(1)
      end
      --os.exit(1)
      local walls = utils.pointsToLines(oriWidth, oriHeight, points, lineWidth)
      wallsResult = walls

      local wallMask = utils.drawLineMask(oriWidth, oriHeight, walls, lineWidth)

      local rooms, numRooms = utils.findConnectedComponents(1 - wallMask)

      local deltas = {{1, -1}, {1, 1}, {-1, 1}, {-1, -1}}
      local roomLabelsMap = {}
      for pointIndex, point in pairs(points) do
         for orientation, delta in pairs(deltas) do
            local label = pointLabels[pointIndex][orientation]
            if label >= 1 then
               local x = torch.round(point[1][1])
               local y = torch.round(point[1][2])
               --x = math.max(math.min(x, width), 1)
               --y = math.max(math.min(y, height), 1)
               for i = 1, 10 do
                  if x < 1 or x > oriWidth or y < 1 or y > oriHeight then
                     break
                  end
                  local roomIndex = rooms[y][x]
                  if roomIndex > 0 then
                     if not roomLabelsMap[roomIndex] then
                        roomLabelsMap[roomIndex] = {}
                     end
                     roomLabelsMap[roomIndex][label] = true
                     break
                  end
                  x = x + delta[1]
                  y = y + delta[2]
               end
            end
         end
      end

      labelsResult = {}
      for roomIndex, labels in pairs(roomLabelsMap) do
         local means = rooms:eq(roomIndex):nonzero():double():mean(1)[1]
         local y = means[1]
         local x = means[2]
         for label, _ in pairs(labels) do
            --print(roomIndex .. ' ' .. x .. ' ' .. y .. ' ' .. label)
            table.insert(labelsResult, {{x - 20, y - 10}, {x + 20, y + 10}, utils.getItemInfo('labels', label)})
         end
      end

      --[[
         image.save('test/floorplan.png', floorplanOri)
         floorplanOri[1][wallMask:gt(0)] = 1
         floorplanOri[2][wallMask:gt(0)] = 0
         floorplanOri[3][wallMask:gt(0)] = 0
         image.save('test/walls.png', floorplanOri)
      ]]--
      break

      -- if true then
      -- 	 wallMask:mul(0.3)
      -- 	 wallMask = wallMask:repeatTensor(3, 1, 1)
      -- 	 local junctionMasks = utils.drawJunctionMasks(oriWidth, oriHeight, points, #points)
      -- 	 for i = 1, junctionMasks:size(1) do
      -- 	    for c = 1, 3 do
      -- 	       wallMask[c][junctionMasks[i]:gt(0)] = torch.uniform()
      -- 	    end
      -- 	 end
      -- end

      -- if useStack then
      --    image.save('test/junction_' .. stackIndex .. '.png', image.scale(wallMask, oriWidth, oriHeight))
      -- else
      --    image.save('test/junction.png', image.scale(wallMask, oriWidth, oriHeight))
      -- 	 break
      -- end
   end

   return wallsResult, labelsResult
end

function utils.saveJunctions(filename, points)
   local junctionFile = io.open(filename, 'w')
   for _, item in pairs(points) do
      for __, field in pairs(item) do
         if __ <= 3 then
            for ___, value in pairs(field) do
               junctionFile:write(value .. '\t')
            end
         end
      end
      junctionFile:write('\n')
   end
   junctionFile:close()
end

function utils.findDoors(floorplan, denotedDoors, walls, floorplanSegmentation)
end

function utils.extractRepresentation(floorplan)
   local representation = {}
   local denotedRepresentation = denotedRepresentation or {}

   representation.walls, representation.points = utils.findWalls(floorplan, denotedRepresentation.walls, 5)
   --representation.doors = utils.findDoors(floorplan, denotedRepresentation.doors, representation.walls, floorplanSegmentation)

   if true then
      representation.doors = {}
      representation.icons = {}
      representation.labels = {}
      return representation
   end


   representation.doors = {}
   local candidateRegions, maskImage, labels = utils.extractCandidateRegions(floorplan, floorplanSegmentation, representation.walls)

   for _, mode in pairs({'doors'}) do
      local numRegions = torch.max(candidateRegions[mode])
      print(numRegions)
      for regionIndex = 1, numRegions do
         local mask = candidateRegions[mode]:eq(regionIndex)
         local indices = mask:nonzero()
         if ##indices > 0 then
            local mins = torch.min(indices, 1)[1]
            local maxs = torch.max(indices, 1)[1]
            local point_1, point_2
            if mode == 'doors' then
               if maxs[1] - mins[1] > maxs[2] - mins[2] then
                  local meanX = (maxs[2] + mins[2]) / 2
                  point_1 = {meanX, mins[1]}
                  point_2 = {meanX, maxs[1]}
               else
                  local meanY = (maxs[1] + mins[1]) / 2
                  point_1 = {mins[2], meanY}
                  point_2 = {maxs[2], meanY}
               end
            else
               point_1 = {mins[2] - 1, mins[1] - 1}
               point_2 = {maxs[2] + 1, maxs[1] + 1}
            end
            if mode == 'doors' then
               table.insert(representation[mode], {point_1, point_2, {'door', 1, 1}})
            else
               table.insert(representation[mode], {point_1, point_2, {'bathtub', 1, 1}})
            end
         end
      end
   end

   --representation.icons = utils.detectItems(floorplan, 'icons')
   representation.icons = {}
   representation.labels = labels
   return representation
end

function utils.extractCandidateRegions(floorplan, floorplanSegmentation, walls, lineWidth)
   local width = floorplan:size(3)
   local height = floorplan:size(2)

   local candidateRegions = {}
   candidateRegions.doors = {}
   candidateRegions.icons = {}
   --candidateRegions.labels = {}

   local lineWidth = lineWidth or 5

   local lineMask = utils.drawLineMask(width, height, walls, lineWidth)
   if floorplanSegmentation == nil then
      local binaryThreshold = torch.max(floorplan, 1)[1][lineMask:byte()]:mean() + 0.1
      floorplanSegmentation, numSegments, floorplanBinary = utils.segmentFloorplan(floorplan, binaryThreshold, 0, false, true)
   end

   local doorMask = torch.cmul(floorplanSegmentation:gt(1):double(), image.dilate(lineMask))
   for segment = 2, torch.max(floorplanSegmentation) do
      local segmentMask = floorplanSegmentation:eq(segment)
      local indices = doorMask[segmentMask]:nonzero()
      if ##indices > 0 then
         if (#indices)[1] < (#segmentMask:nonzero())[1] then
            doorMask[segmentMask] = 0
         end
      end
   end
   doorMask = image.dilate(doorMask)
   local doors, numDoors = utils.findConnectedComponents(doorMask)
   local wallMask = utils.drawLineMask(width, height, walls, lineWidth, true)
   local doorIndex = 1
   while doorIndex <= numDoors do
      local door = doors:eq(doorIndex)
      local indices = door:nonzero()
      if ##indices > 0 then
         local wallIndex = wallMask[indices[1]:totable()]
         local notInWall = wallMask:ne(wallIndex)
         local doorNotInWall = torch.cmul(door, notInWall)
         if ##doorNotInWall:nonzero() > 0 then
            numDoors = numDoors + 1
            doors[doorNotInWall] = numDoors
         end
      end
      doorIndex = doorIndex + 1
   end

   floorplanSegmentation = torch.cmul(floorplanSegmentation, (1 - lineMask):int())
   local smallSegments = {}
   for segment = 2, torch.max(floorplanSegmentation) do
      local segmentMask = floorplanSegmentation:eq(segment)
      local indices = segmentMask:nonzero()
      if ##indices > 0 then
         local mins = torch.min(indices, 1)[1]
         local maxs = torch.max(indices, 1)[1]
         if (#indices)[1] < width * height * 0.03 and maxs[1] - mins[1] < height * 0.25 and maxs[2] - mins[2] < width * 0.25 then
            table.insert(smallSegments, segmentMask)
         end
      end
   end
   local rooms, numRooms = utils.findConnectedComponents(1 - lineMask)

   local backgroundRoomIndex
   local imageCorners = {{1, 1}, {width, 1}, {width, height}, {1, height}}
   for _, imageCorner in pairs(imageCorners) do
      local roomIndex = rooms[imageCorner[2]][imageCorner[1]]
      if roomIndex > 0 then
         if not backgroundRoomIndex then
            backgroundRoomIndex = roomIndex
         elseif roomIndex ~= backgroundRoomIndex then
            rooms[rooms:eq(roomIndex)] = backgroundRoomIndex
         end
      end
   end
   if not backgroundRoomIndex then
      backgroundRoomIndex = numRooms
   end


   local iconMask = torch.zeros(height, width)
   for roomIndex = 1, numRooms do
      if roomIndex ~= backgroundRoomIndex then
         local roomMask = rooms:eq(roomIndex)
         --local maxCount
         --local maxCountSegmentIndex
         if ##roomMask:nonzero() > 0 then
            local roomCount = (#roomMask:nonzero())[1]
            local iconSegments = {}
            for segmentIndex, segmentMask in pairs(smallSegments) do
               local indices = torch.cmul(segmentMask, roomMask):nonzero()
               if ##indices > 0 then
                  local count = (#indices)[1]
                  if count == (#segmentMask:nonzero())[1] and count < roomCount * 0.5 then
                     table.insert(iconSegments, segmentIndex)
                  end
               end
            end
            --table.insert(invalidSegments, maxCountSegmentIndex)
            for _, segmentIndex in pairs(iconSegments) do
               local indices = smallSegments[segmentIndex]:nonzero()
               local mins = torch.min(indices, 1)[1]
               local maxs = torch.max(indices, 1)[1]
               --local segmentMask = torch.zeros(height, width)
               --segmentMask[{{mins[1], maxs[1]}, {mins[2], maxs[2]}}] = 1
               --iconMask[torch.cmul(segmentMask:byte(), roomMask)] = 0
               iconMask[{{mins[1], maxs[1]}, {mins[2], maxs[2]}}] = 1
            end
         end
      end
   end

   --image.save('test/mask_1.png', iconMask:double())

   --iconMask = image.dilate(iconMask)
   local icons, numIcons = utils.findConnectedComponents(iconMask)

   local segmentation, labelMap = utils.predictSegmentation(floorplan, walls)
   --local icons = torch.zeros(#segmentation)
   local iconIndex = numIcons
   local labelSizeThresholds = {{5, 50}, {10, 100}}
   local roomLabels = {}
   for segmentIndex = 2, torch.max(segmentation) do
      local mask = segmentation:eq(segmentIndex)
      local label = labelMap[segmentIndex]
      if label <= 10 then
         local indices = mask:nonzero():double()
         if ##indices > 0 then
            local means = torch.mean(indices, 1)[1]
            local maxs = torch.max(indices, 1)[1]
            local mins = torch.min(indices, 1)[1]
            if maxs[1] - mins[1] >= labelSizeThresholds[1][1] and maxs[2] - mins[2] >= labelSizeThresholds[2][1] then
               local labelSize = {}
               for c = 1, 2 do
                  labelSize[c] = math.min((maxs[c] - mins[c]) * 4 / 5, labelSizeThresholds[c][2])
               end

               local roomIndex = rooms[indices[1][1]][indices[1][2]]
               if roomLabels[roomIndex] == nil then
                  roomLabels[roomIndex] = {}
               end
               table.insert(roomLabels[roomIndex], {indices:size(1), {{means[2] - labelSize[2] / 2, means[1] - labelSize[1] / 2}, {means[2] + labelSize[2] / 2, means[1] + labelSize[1] / 2}, utils.getItemInfo('labels', label)}})
               --table.insert(labels, {{means[2] - labelSize[2] / 2, means[1] - labelSize[1] / 2}, {means[2] + labelSize[2] / 2, means[1] + labelSize[1] / 2}, utils.getItemInfo('labels', label)})
            end
         end
      else
         mask = torch.cmul(mask, 1 - iconMask:byte())
         icons[mask] = iconIndex
         iconIndex = iconIndex + 1
      end
   end
   local labels = {}
   for roomIndex, sortedLabels in pairs(roomLabels) do
      table.sort(sortedLabels, function(a, b) return a[1] > b[1] end)
      table.insert(labels, sortedLabels[1][2])
   end

   iconMask = icons:gt(0)
   --icons = image.convolve(icons:double(), torch.ones(3, 3), 'same'):int()

   --image.save('test/binary.png', floorplanBinary:double())
   --image.save('test/floorplan.png', floorplan)
   --image.save('test/segmentation.png', utils.drawSegmentation(floorplanSegmentation, torch.max(floorplanSegmentation)))
   --image.save('test/mask.png', utils.drawSegmentation(icons))
   --image.save('test/mask.png', (1 - torch.cmul(doors:eq(0), icons:eq(0))):double())
   --os.exit(1)
   --[[
      if true then
      return 1 - torch.cmul(doors:eq(0), icons:eq(0))
      end
   ]]--
   local candidateRegions = {}
   candidateRegions.doors = doors
   candidateRegions.icons = icons
   --return candidateRegions, torch.clamp(floorplan * 0.2 + torch.cat(torch.cat(doors:eq(0):repeatTensor(1, 1, 1):double(), icons:eq(0):repeatTensor(1, 1, 1):double(), 1), torch.ones(1, height, width), 1), 0, 1)

   return candidateRegions, torch.cat(torch.cat(doors:eq(0):repeatTensor(1, 1, 1):double(), icons:eq(0):repeatTensor(1, 1, 1):double(), 1), torch.ones(1, height, width), 1), labels
end

function utils.getWallPlacements(width, height, representation, lineWidth, representationType)
   local lineWidth = lineWidth or 5
   local representationType = representationType or 'L'

   local points
   if representationType == 'L' then
      representation.walls = utils.mergeLines(representation.walls, lineWidth)
      points = utils.linesToPoints(width, height, representation.walls, lineWidth)
   else
      points = representation.points
   end

   local walls, wallJunctionsMap = utils.pointsToLines(width, height, points, lineWidth, true)
   local imageSize = {width, height}

   --[[
      local wallIndices = {6, 32}
      for _, wallIndex in pairs(wallIndices) do
      print(wallIndex)
      for index = 1, 2 do
      for c = 1, 2 do
      print(walls[wallIndex][index][c])
      end
      end
      print(wallJunctionsMap[wallIndex][1] .. ' ' .. wallJunctionsMap[wallIndex][2])
      end

      local pointIndices = {3, 20}
      for _, pointIndex in pairs(pointIndices) do
      print(pointIndex)
      for index = 1, 3, 2 do
      for c = 1, 3 do
      print(points[pointIndex][index][c])
      end
      end
      --print(wallJunctionsMap[wallIndex][1] .. ' ' .. wallJunctionsMap[wallIndex][2])
      end
      os.exit(1)

      for wallIndex, wall in pairs(representation.walls) do
      print(wallIndex)
      print(wall[1][1] .. ' ' .. wall[1][2] .. ' ' .. wall[2][1] .. ' ' .. wall[2][2])
      end

      for pointIndex, point in pairs(points) do
      print(pointIndex)
      print(point[1][1] .. ' ' .. point[1][2] .. ' ' .. point[3][2] .. ' ' .. point[3][3])
      end
      --os.exit(1)
   ]]--

   local wallOrderMap = {}
   local orderPlacementTypeMap = {}
   orderPlacementTypeMap[0] = 0
   local wallMask = utils.drawLineMask(width, height, walls, lineWidth, true, 1)
   local rooms, numRooms = utils.findConnectedComponents(1 - wallMask:gt(0))

   local backgroundRoomIndex
   local imageCorners = {{1, 1}, {width, 1}, {width, height}, {1, height}}
   for _, imageCorner in pairs(imageCorners) do
      local roomIndex = rooms[imageCorner[2]][imageCorner[1]]
      if roomIndex > 0 then
         if not backgroundRoomIndex then
            backgroundRoomIndex = roomIndex
         elseif roomIndex ~= backgroundRoomIndex then
            rooms[rooms:eq(roomIndex)] = backgroundRoomIndex
         end
      end
   end
   if not backgroundRoomIndex then
      backgroundRoomIndex = numRooms
   end


   local backgroundMask = rooms:eq(backgroundRoomIndex)
   local backgroundMaskDiff = image.dilate(backgroundMask) - backgroundMask
   backgroundMaskDiff[{1, {}}] = 1
   backgroundMaskDiff[{height, {}}] = 1
   backgroundMaskDiff[{{}, 1}] = 1
   backgroundMaskDiff[{{}, width}] = 1
   --image.save('test/walls.png', utils.drawSegmentation(wallMask))
   --image.save('test/rooms.png', utils.drawSegmentation(rooms))
   --image.save('test/background.png', backgroundMask:double())
   --image.save('test/background_diff.png', backgroundMaskDiff:double())
   local wallMaskDiff = torch.cmul(wallMask, backgroundMaskDiff:double())
   local outmostWalls = wallMask[backgroundMaskDiff]
   for i = 1, outmostWalls:size(1) do
      local wallIndex = outmostWalls[i]
      if wallIndex > 0 and not wallOrderMap[wallIndex] then

         wallOrderMap[wallIndex] = 0
         --print(0 .. ' ' .. wallIndex)

         --[[
            local lineDim = utils.lineDim(walls[wallIndex])
            local indices = wallMaskDiff:eq(wallIndex):nonzero()
            local mins = torch.min(indices, 1)[1]
            local maxs = torch.max(indices, 1)[1]

            local diffLineDim = 0
            if maxs[1] - mins[1] <= maxs[2] - mins[2] and maxs[1] - mins[1] <= 1 then
            diffLineDim = 1
            elseif maxs[1] - mins[1] >= maxs[2] - mins[2] and maxs[2] - mins[2] <= 1 then
            diffLineDim = 2
            end

            if lineDim == 0 or lineDim == diffLineDim then
            wallOrderMap[wallIndex] = 0
            print(0 .. ' ' .. wallIndex)
            end
         ]]--
      end
   end

   local junctionWallMap = {}
   for wallIndex, junctions in pairs(wallJunctionsMap) do
      for c = 1, 2 do
         if junctionWallMap[junctions[c]] == nil then
            junctionWallMap[junctions[c]] = {}
         end
         table.insert(junctionWallMap[junctions[c]], wallIndex)
      end
   end

   local wallLengthDimMap = {}
   for wallIndex, wall in pairs(walls) do
      wallLengthDimMap[wallIndex] = {utils.calcDistance(wall[1], wall[2]), utils.lineDim(wall)}
   end

   --[[
      local wallNeighbors = {}
      for wallIndex, wall in pairs(walls) do
      if wallNeighbors[wallIndex] == nil then
      wallNeighbors[wallIndex] = {}
      end
      end
      for junctionIndex, wallIndices in pairs(junctionWallMap) do
      for _, wallIndex in pairs(wallIndices) do
      wallNeighbors[wallIndex][junctionIndex] = {}
      end
      end

      for junctionIndex, wallIndices in pairs(junctionWallMap) do
      for _, wallIndex_1 in pairs(wallIndices) do
      for _, wallIndex_2 in pairs(wallIndices) do
      if wallIndex_1 < wallIndex_2 then
      local lineDim_1 = utils.lineDim(walls[wallIndex_1])
      local lineDim_2 = utils.lineDim(walls[wallIndex_2])
      local neighborType
      if lineDim_1 == 0 or lineDim_2 == 0 then
      neighborType = 0
      elseif lineDim_1 == lineDim_2 then
      neighborType = 1
      else
      neighborType = 2
      end
      wallNeighbors[wallIndex_1][junctionIndex][wallIndex_2] = neighborType
      wallNeighbors[wallIndex_2][junctionIndex][wallIndex_1] = neighborType
      end
      end
      end
      end
   ]]--

   local order = 1
   while true do
      local junctionTypeMap = {}
      for wallIndex, junctions in pairs(wallJunctionsMap) do
         if wallOrderMap[wallIndex] and wallOrderMap[wallIndex] < order then
            for c = 1, 2 do
               junctionTypeMap[junctions[c]] = 1
            end
         end
      end

      local placements = {}
      for wallIndex, junctions in pairs(wallJunctionsMap) do
         if not wallOrderMap[wallIndex] then
            local wallPlacements = {}
            if junctionTypeMap[junctions[1]] == 1 and junctionTypeMap[junctions[2]] == 1 then
               table.insert(placements, {{wallIndex}, 0, 0})
            elseif junctionTypeMap[junctions[1]] == 1 or junctionTypeMap[junctions[2]] == 1 then
               if junctionTypeMap[junctions[1]] ~= 1 then
                  table.insert(wallPlacements, {{wallIndex}, junctions[1], 0, 0})
               else
                  table.insert(wallPlacements, {{wallIndex}, junctions[2], 0, 0})
               end
            end
            while #wallPlacements > 0 do
               local newWallPlacements = {}
               for _, placement in pairs(wallPlacements) do
                  local activeWallIndex = placement[1][#placement[1]]
                  local lineDim = utils.lineDim(walls[activeWallIndex])
                  local unnecessaryTurn = 0
                  local lineDimCounter = {0, 0}
                  lineDimCounter[lineDim] = 1
                  for _, neighborWallIndex in pairs(junctionWallMap[placement[2]]) do
                     if neighborWallIndex ~= activeWallIndex then
                        local neighborLineDim = utils.lineDim(walls[neighborWallIndex])
                        if neighborLineDim > 0 then
                           if lineDimCounter[neighborLineDim] == 1 then
                              unnecessaryTurn = 1
                              break
                           end
                           lineDimCounter[neighborLineDim] = lineDimCounter[neighborLineDim] + 1
                        end
                     end
                  end
                  for _, neighborWallIndex in pairs(junctionWallMap[placement[2]]) do
                     if neighborWallIndex ~= activeWallIndex then
                        local turn = 0
                        if utils.lineDim(walls[neighborWallIndex]) ~= lineDim then
                           turn = 1
                        end
                        local numTurns = placement[3] + turn
                        local numUnnecessaryTurns = placement[4] + math.min(unnecessaryTurn, turn)
                        if numTurns <= 2 then
                           local newWallSequence = {}
                           for _, placementWallIndex in pairs(placement[1]) do
                              table.insert(newWallSequence, placementWallIndex)
                           end
                           table.insert(newWallSequence, neighborWallIndex)

                           local neighborWallActiveJunction
                           local neighborWallJunctions = wallJunctionsMap[neighborWallIndex]
                           for c = 1, 2 do
                              local junction = neighborWallJunctions[c]
                              if junction ~= placement[2] then
                                 neighborWallActiveJunction = junction
                              end
                           end
                           if junctionTypeMap[neighborWallActiveJunction] == 1 then
                              table.insert(placements, {newWallSequence, numTurns, numUnnecessaryTurns})
                           else
                              table.insert(newWallPlacements, {newWallSequence, neighborWallActiveJunction, numTurns, numUnnecessaryTurns})
                              --[[
                                 print(#newWallSequence)
                                 print(newWallSequence[1])
                                 print(newWallSequence[2])
                                 print(numTurns .. ' ' .. neighborWallActiveJunction)
                              --]]
                           end
                        end
                     end
                  end
               end
               wallPlacements = newWallPlacements
               --os.exit(1)
            end
         end
      end

      if #placements == 0 then
         break
      end

      local minCost
      local minCostWallSequence
      local minCostNumTurns
      --print('num placements: ' .. #placements)
      for _, placement in pairs(placements) do
         local cost = placement[2] + placement[3] * 2

         local lengths = {0, 0, 0}
         for __, wallIndex in pairs(placement[1]) do
            --print(_ .. ' ' .. __ .. ' ' .. wallIndex)
            --cost = cost + 1 / wallLengthMap[wallIndex]
            lengths[wallLengthDimMap[wallIndex][2] + 1] = lengths[wallLengthDimMap[wallIndex][2] + 1] + wallLengthDimMap[wallIndex][1]
         end
         local length = lengths[1] + lengths[2] + lengths[3]
         if length > 0 then
            cost = cost + 1 / length
         end

         if not minCost or cost < minCost then
            minCost = cost
            minCostWallSequence = placement[1]
            minCostNumTurns = placement[2]
         end


         --[[
            if order == 6 or order == 7 then
            print('order: ' .. order)
            print('index: ' .. _)
            print('cost: ' .. cost)
            for __, wallIndex in pairs(placement[1]) do
            print(wallIndex)
            end
            end
         ]]--
      end
      for _, wallIndex in pairs(minCostWallSequence) do
         --print(order .. ' ' .. wallIndex)
         wallOrderMap[wallIndex] = order
      end
      orderPlacementTypeMap[order] = minCostNumTurns + 1
      order = order + 1
      --if order == 3 then
      --os.exit(1)
      --end
   end
   local maxOrder = order - 1
   --print(maxOrder)

   for order = 0, maxOrder do
      local orderWalls = {}
      for wallIndex, wall in pairs(walls) do
         if wallOrderMap[wallIndex] and wallOrderMap[wallIndex] <= order then
            table.insert(orderWalls, wall)
         end
      end
      --image.save('test/walls_' .. order .. '.png', utils.drawLineMask(width, height, orderWalls, lineWidth))
      order = order + 1
   end

   return walls, wallOrderMap, orderPlacementTypeMap, points, wallJunctionsMap
end

function utils.getWallPlacement(width, height, representation, lineWidth, representationType, getHeatmap)
   local lineWidth = lineWidth or 5

   local walls, wallOrderMap, orderPlacementTypeMap = utils.getWallPlacements(width, height, representation, lineWidth, representationType)

   -- if not orderPlacementTypeMap[1] then
   --    image.save('test/floorplan.png', floorplan)
   --    image.save('test/walls.png', utils.drawSegmentation(utils.drawLineMask(floorplan:size(3), floorplan:size(2), representation.walls, lineWidth, true)))
   --    --print(wallOrderMap)
   --    --assert(false, 'placement type empty')
   -- end

   local inputWalls = {}
   local outputWalls = {}
   local inputOrder = 0
   local outputOrder = 1
   for wallIndex, wall in pairs(walls) do
      if wallOrderMap[wallIndex] then
         if wallOrderMap[wallIndex] == inputOrder then
            table.insert(inputWalls, wall)
         elseif wallOrderMap[wallIndex] == outputOrder then
            table.insert(outputWalls, wall)
         end
      end
   end
   local inputWallMask = utils.drawLineMask(width, height, inputWalls, lineWidth)
   local outputWallRepresentation
   if getHeatmap then
      local outputWallJunctionHeatmap = torch.zeros(height, width)
      if orderPlacementTypeMap[outputOrder] then
         local kernelSize = kernelSize or 7
         for _, wall in pairs(outputWalls) do
            for pointIndex = 1, 2 do
               local point = wall[pointIndex]
               local x = torch.round(point[1])
               local y = torch.round(point[2])
               if x >= 1 and x <= width and y >= 1 and y <= height then
                  outputWallJunctionHeatmap[y][x] = 1
               end
            end
         end
         local kernel = image.gaussian(kernelSize)
         outputWallJunctionHeatmap = image.convolve(outputWallJunctionHeatmap, kernel, 'same')
      end
      outputWallJunctionHeatmap = outputWallJunctionHeatmap:repeatTensor(1, 1, 1)
      outputWallRepresentation = outputWallJunctionHeatmap
   else
      local maxNumJunctions = 4
      local outputWallJunctions = torch.zeros(maxNumJunctions * 2)
      if orderPlacementTypeMap[outputOrder] then
         local junctions = {}
         for _, wall in pairs(outputWalls) do
            for pointIndex = 1, 2 do
               local point = wall[pointIndex]
               table.insert(junctions, point)
            end
         end
         local sortedJunctions = {}
         for _, junction in pairs(junctions) do
            local exists = false
            for __, sortedJunction in pairs(sortedJunctions) do
               if math.abs(junction[1] - sortedJunction[1]) <= lineWidth and math.abs(junction[2] - sortedJunction[2]) <= lineWidth then
                  sortedJunction[1] = (junction[1] + sortedJunction[1]) / 2
                  sortedJunction[2] = (junction[2] + sortedJunction[2]) / 2
                  exists = true
               end
            end
            if not exists then
               table.insert(sortedJunctions, junction)
            end
         end
         table.sort(sortedJunctions, function(a, b) return a[2] < b[2] or (a[2] == b[2] and a[1] < b[1]) end)
         for index = 1, math.min(maxNumJunctions, #sortedJunctions) do
            for c = 1, 2 do
               outputWallJunctions[(index - 1) * 2 + c] = sortedJunctions[index][c]
            end
         end
      end
      outputWallRepresentation = outputWallJunctions
   end

   if not orderPlacementTypeMap[outputOrder] then
      orderPlacementTypeMap[outputOrder] = 4
   end

   return inputWallMask, outputWallRepresentation, orderPlacementTypeMap[outputOrder]
end

function utils.getJunctionPlacement(width, height, representation, lineWidth, representationType, kernelSize)
   local lineWidth = lineWidth or 5
   local kernelSize = kernelSize or 7
   local walls, wallOrderMap, orderPlacementTypeMap, points, wallJunctionsMap = utils.getWallPlacements(width, height, representation, lineWidth, representationType)
   -- if not orderPlacementTypeMap[1] then
   --    image.save('test/floorplan.png', floorplan)
   --    image.save('test/walls.png', utils.drawSegmentation(utils.drawLineMask(floorplan:size(3), floorplan:size(2), representation.walls, lineWidth, true)))
   --    --print(wallOrderMap)
   --    --assert(false, 'placement type empty')
   -- end


   local orderWallsMap = {}
   for wallIndex, order in pairs(wallOrderMap) do
      if not orderWallsMap[order] then
         orderWallsMap[order] = {}
      end
      --print(order .. ' ' .. wallIndex .. ' ' .. wallJunctionsMap[wallIndex][1] .. ' ' .. wallJunctionsMap[wallIndex][2])
      table.insert(orderWallsMap[order], wallIndex)
   end

   --print(orderWallsMap[0])
   local orderedJunctions = {}
   local activeOrder = -1
   local activeJunction = -1
   local usedJunctionMask = {}
   local firstJunction = 0
   while true do
      local nextJunctionFound = false
      if activeOrder >= 0 then
         local orderWalls = orderWallsMap[activeOrder]
         for _, wallIndex in pairs(orderWalls) do
            for pointIndex = 1, 2 do
               if wallJunctionsMap[wallIndex][pointIndex] == activeJunction and not usedJunctionMask[wallJunctionsMap[wallIndex][3 - pointIndex]] then
                  nextJunctionFound = true
                  activeJunction = wallJunctionsMap[wallIndex][3 - pointIndex]
                  usedJunctionMask[activeJunction] = true
                  --print(activeOrder .. ' ' .. activeJunction)
                  table.insert(orderedJunctions, {activeJunction, activeOrder})
                  break
               end
            end
            if nextJunctionFound then
               break
            end
         end
      end
      if not nextJunctionFound then
         if firstJunction > 0 then
            table.insert(orderedJunctions, {firstJunction, activeOrder})
            nextJunctionFound = true
            firstJunction = 0
         end
      end

      if not nextJunctionFound then
         activeOrder = activeOrder + 1
         usedJunctionMask = {}
         local orderWalls =  orderWallsMap[activeOrder]
         if not orderWalls then
            break
         end
         local minValue
         local minValueWallIndex
         local minValuePointIndex
         for _, wallIndex in pairs(orderWalls) do
            for pointIndex = 1, 2 do
               local junction = wallJunctionsMap[wallIndex][pointIndex]
               local value = points[junction][1][1] * height + points[junction][1][2]
               if not minValue or value < minValue then
                  minValue = value
                  minValueWallIndex = wallIndex
                  minValuePointIndex = pointIndex
               end
            end
         end
         activeJunction = wallJunctionsMap[minValueWallIndex][minValuePointIndex]
         usedJunctionMask[activeJunction] = true
         --print(activeOrder .. ' ' .. activeJunction)
         table.insert(orderedJunctions, {activeJunction, activeOrder})
         if activeOrder == 0 then
            firstJunction = activeJunction
         end
      end
   end

   local orderedPoints = {}
   --image.save('test/walls.png', utils.drawLineMask(width, height, walls, lineWidth))
   for index, junction in pairs(orderedJunctions) do
      table.insert(orderedPoints, points[junction[1]])
      if index >= 2 then
         local orderedWalls = utils.pointsToLines(width, height, orderedPoints, lineWidth, true, nil, true)
         --image.save('test/walls_' .. index .. '.png', utils.drawLineMask(width, height, orderedWalls, lineWidth))
      end
   end
   assert(activeOrder > 0 and #orderedJunctions > 1)
   local index = math.random(#orderedJunctions - 1)
   while orderedJunctions[index][2] ~= orderedJunctions[index + 1][2] do
      index = math.random(#orderedJunctions - 1)
   end
   local previousPoints = {}
   for i = 1, index do
      table.insert(previousPoints, points[orderedJunctions[i][1]])
   end
   local wallMask = utils.drawLineMask(width, height, utils.pointsToLines(width, height, previousPoints, lineWidth, true, nil, true), lineWidth)

   local activeJunction = orderedJunctions[index][1]
   local activeJunctionMask = torch.zeros(height, width)
   activeJunctionMask[math.max(math.min(torch.round(points[activeJunction][1][2]), height), 1)][math.max(math.min(torch.round(points[activeJunction][1][1]), width), 1)] = 1

   local nextJunction = orderedJunctions[index + 1][1]
   local nextJunctionMask = torch.zeros(height, width)
   nextJunctionMask[math.max(math.min(torch.round(points[nextJunction][1][2]), height), 1)][math.max(math.min(torch.round(points[nextJunction][1][1]), width), 1)] = 1

   if kernelSize > 0 then
      local kernel = image.gaussian(kernelSize)
      activeJunctionMask = image.convolve(activeJunctionMask, kernel, 'same')
      nextJunctionMask = image.convolve(nextJunctionMask, kernel, 'same')
   end

   return wallMask, activeJunctionMask, nextJunctionMask
end

function utils.getIconTensor(width, height, representation)
   local nameIconsMap = {}
   for _, icon in pairs(representation.icons) do
      local name = icon[3][1]
      if not nameIconsMap[name] then
         nameIconsMap[name] = {}
      end
      table.insert(nameIconsMap[name], icon)
   end
   local iconTensor = torch.zeros(4, 5)
   local iconNums = {}

   iconNums['bathtub'] = 1
   iconNums['cooking_counter'] = 1
   iconNums['toilet'] = 1
   iconNums['entrance'] = 1
   --numberMap.icons['washing_basin'] = {6, 7, 8, 9}
   --numberMap.icons['special'] = {10, 11, 12}
   --numberMap.icons['stairs'] = {13}

   local index = 1
   for name, num in pairs(iconNums) do
      for i = 1, num do
         if nameIconsMap[name] and nameIconsMap[name][i] then
            local icon = nameIconsMap[name][i]
            iconTensor[index][1] = (icon[1][1] + icon[2][1]) / 2 / width
            iconTensor[index][2] = (icon[1][2] + icon[2][2]) / 2 / height
            iconTensor[index][3] = math.abs(icon[1][1] - icon[2][1]) / width
            iconTensor[index][4] = math.abs(icon[1][2] - icon[2][2]) / height
            iconTensor[index][5] = 1
            index = index + 1
         end
      end
   end
   return iconTensor
end


function utils.getSegmentationWithConflict(width, height, representation, lineWidth)
   local lineWidth = lineWidth or 5
   local lineMask = utils.drawLineMask(width, height, representation.walls, lineWidth)
   local rooms, numRooms = utils.findConnectedComponents(1 - lineMask)

   local backgroundRoomIndex
   local imageCorners = {{1, 1}, {width, 1}, {width, height}, {1, height}}
   for _, imageCorner in pairs(imageCorners) do
      local roomIndex = rooms[imageCorner[2]][imageCorner[1]]
      if roomIndex > 0 then
         if not backgroundRoomIndex then
            backgroundRoomIndex = roomIndex
         elseif roomIndex ~= backgroundRoomIndex then
            rooms[rooms:eq(roomIndex)] = backgroundRoomIndex
         end
      end
   end

   local floorplanSegmentation = torch.zeros(#rooms)
   for _, label in pairs(representation.labels) do
      local center = {torch.round((label[1][1] + label[2][1]) / 2), torch.round((label[1][2] + label[2][2]) / 2)}
      local number = utils.getNumber('labels', label[3])
      local roomIndex = rooms[{center[2], center[1]}]
      if roomIndex > 0 and roomIndex ~= backgroundRoomIndex then
         local segmentIndex = floorplanSegmentation[{center[2], center[1]}]
         if segmentIndex == 0 or (number < segmentIndex and (number ~= 2 or segmentIndex ~= 3)) or (number == 3 and segmentIndex == 2) then
            floorplanSegmentation[rooms:eq(roomIndex)] = number
         end
      end
   end
   floorplanSegmentation[rooms:eq(backgroundRoomIndex)] = 0

   for _, icon in pairs(representation.icons) do
      local number = utils.getNumber('icons', icon[3])
      floorplanSegmentation[{{math.max(math.min(icon[1][2], icon[2][2]), 1), math.min(math.max(icon[1][2], icon[2][2]), height)}, {math.max(math.min(icon[1][1], icon[2][1]), 1), math.min(math.max(icon[1][1], icon[2][1]), width)}}] = number + 10
      --[[
         local success, _ = pcall(function()
         floorplanSegmentation[{{math.max(icon[1][2], 1), math.min(icon[2][2], height)}, {math.max(icon[1][1], 1), math.min(icon[2][1], width)}}] = number + 10
         end
         )
         if not success then
         print(width)
         print(height)
         print(icon[1][1])
         print(icon[1][2])
         print(icon[2][1])
         print(icon[2][2])
         end
      ]]--
   end
   floorplanSegmentation[rooms:eq(0)] = -1

   --image.save('test/floorplan_segmentation.png', utils.drawSegmentation(floorplanSegmentation))
   --os.exit(1)
   local doorWidth = doorWidth or 3
   local doorMask = utils.drawLineMask(width, height, representation.doors, doorWidth, nil, 0)
   floorplanSegmentation[doorMask:byte()] = -2
   return floorplanSegmentation
end


function utils.getRoomSegmentationQP(width, height, representation, lineWidth, floorplan)
   local lineWidth = lineWidth or 5
   representation.walls = utils.mergeLines(representation.walls, lineWidth)

   for _, wall in pairs(representation.walls) do
      local lineDim = utils.lineDim(wall)
      if lineDim > 0 then
         if wall[1][lineDim] > wall[2][lineDim] then
            print('opposite wall exists')
            os.exit(1)
         end
      end
   end

   local points = utils.linesToPoints(width, height, representation.walls, lineWidth)

   local wallMask = utils.drawLineMask(width, height, representation.walls, lineWidth)
   --image.save('test/wall.png', wallMask)

   local rooms, numRooms = utils.findConnectedComponents(1 - wallMask)
   local backgroundRoomIndex
   local imageCorners = {{width, 1}, {width, height}, {1, height}}
   for _, imageCorner in pairs(imageCorners) do
      local roomIndex = rooms[imageCorner[2]][imageCorner[1]]
      if roomIndex > 0 and not backgroundRoomIndex then
         backgroundRoomIndex = roomIndex
      end
      if roomIndex > 0 and roomIndex ~= backgroundRoomIndex then
         rooms[rooms:eq(roomIndex)] = backgroundRoomIndex
      end
   end
   if not backgroundRoomIndex then
      backgroundRoomIndex = numRooms
   end

   local roomLabels = {}
   for _, label in pairs(representation.labels) do
      local center = {torch.round((label[1][1] + label[2][1]) / 2), torch.round((label[1][2] + label[2][2]) / 2)}
      --local number = utils.getNumber('labels', label[3])
      local roomIndex = rooms[{center[2], center[1]}]
      if roomIndex > 0 and roomIndex ~= backgroundRoomIndex then
         if not roomLabels[roomIndex] then
            roomLabels[roomIndex] = {}
         end
         table.insert(roomLabels[roomIndex], label)
      end
   end


   utils.saveRepresentation('test/points.txt', {points = points})

   local segmentations = torch.zeros(10, height, width)
   local radius = 5
   for _, label in pairs(representation.labels) do
      local number = utils.getNumber('labels', label[3])
      local center = {torch.round((label[1][1] + label[2][1]) / 2), torch.round((label[1][2] + label[2][2]) / 2)}
      local minX = math.max(center[1] - radius, 1)
      local minY = math.max(center[2] - radius, 1)
      local maxX = math.min(center[1] + radius, width)
      local maxY = math.min(center[2] + radius, height)
      segmentations[{number, {minY, maxY}, {minX, maxX}}] = 1
   end

   for roomIndex, labels in pairs(roomLabels) do
      if #labels == 1 then
         local number = utils.getNumber('labels', labels[1][3])
         segmentations[number][rooms:eq(roomIndex)] = 1
      elseif #labels == 0 then
         segmentations[10][rooms:eq(roomIndex)] = 1
      end
   end

   for segmentIndex = 1, 10 do
      image.save('test/segment_' .. segmentIndex .. '.png', segmentations[segmentIndex])
   end
   image.save('test/segment_0.png', torch.zeros(height, width))

   py.execute('import os')
   local ret = py.execute('os.system("python ../InverseCAD/PostProcessing/QP_segmentation.py")')


   local floorplanSegmentation = torch.zeros(height, width)
   for segmentIndex = 1, 10 do
      local success, segmentImage = pcall(function()
            return image.load('test/segment_result_' .. segmentIndex .. '.png', 1)
      end)
      if not success then
         image.save('test/floorplan.png', floorplan)
         os.exit(1)
         return utils.getRoomSegmentationHeuristic(width, height, representation, lineWidth, floorplan)
      end
      floorplanSegmentation[segmentImage:gt(0.5)] = segmentIndex
   end
   floorplanSegmentation[rooms:eq(backgroundRoomIndex)] = 0
   floorplanSegmentation[wallMask:gt(0)] = -1

   for roomIndex, labels in pairs(roomLabels) do
      if #labels == 1 then
         local number = utils.getNumber('labels', labels[1][3])
         floorplanSegmentation[rooms:eq(roomIndex)] = number
      elseif #labels == 0 then
         floorplanSegmentation[rooms:eq(roomIndex)] = 10
      end
   end


   local hasConflict = false
   for roomIndex, labels in pairs(roomLabels) do
      if #labels > 1 then
         hasConflict = true
         break
      end
   end

   if hasConflict then
      image.save('test/floorplan.png', floorplan)
      representation.points = points
      --image.save('test/representation.png', utils.drawRepresentationImage(floorplan:size(3), floorplan:size(2), nil, nil, floorplan, representation, 'P', 'L'))
      image.save('test/segmentation.png', utils.drawSegmentation(floorplanSegmentation))
      os.exit(1)
   end
   return floorplanSegmentation:repeatTensor(1, 1, 1)
end


function utils.getRoomSegments(width, height, representation, lineWidth, floorplan, getHeatmaps)
   local lineWidth = lineWidth or 5
   lineWidth = 3
   --representation.walls = utils.mergeLines(representation.walls, lineWidth)

   --representation.walls = utils.pointsToLines(width, height, representation.points, lineWidth, true)
   --local lineMask = utils.drawLineMask(width, height, lines, lineWidth)
   local boundaryMask = utils.drawLineMask(width, height, representation.walls, lineWidth)
   local rooms, numRooms = utils.findConnectedComponents(1 - boundaryMask)
   image.save('test/walls.png', boundaryMask)
   image.save('test/rooms.png', utils.drawSegmentation(rooms))

   local backgroundRoomIndex
   local imageCorners = {{1, 1}, {width, 1}, {width, height}, {1, height}}
   for _, imageCorner in pairs(imageCorners) do
      local roomIndex = rooms[imageCorner[2]][imageCorner[1]]
      if roomIndex > 0 then
         if not backgroundRoomIndex then
            backgroundRoomIndex = roomIndex
         elseif roomIndex ~= backgroundRoomIndex then
            rooms[rooms:eq(roomIndex)] = backgroundRoomIndex
         end
      end
   end
   if not backgroundRoomIndex then
      backgroundRoomIndex = numRooms
   end

   local roomLabels = {}
   for _, label in pairs(representation.labels) do
      local center = {torch.round((label[1][1] + label[2][1]) / 2), torch.round((label[1][2] + label[2][2]) / 2)}
      --local number = utils.getNumber('labels', label[3])
      local roomIndex = rooms[{center[2], center[1]}]
      if roomIndex > 0 and roomIndex ~= backgroundRoomIndex then
         if not roomLabels[roomIndex] then
            roomLabels[roomIndex] = {}
         end
         table.insert(roomLabels[roomIndex], label)
      end
   end

   local roomSegments = {}
   for roomIndex, labels in pairs(roomLabels) do
      local roomMask = rooms:eq(roomIndex)
      if roomMask:nonzero():size(1) > lineWidth * lineWidth * 2 then
         for _, label in pairs(labels) do
            local roomLabel = utils.getNumber('labels', label[3])
            table.insert(roomSegments, {roomMask, roomLabel})
         end
      end
      --[[
         local roomLabel
         if #labels == 1 then
         roomLabel = utils.getNumber('labels', labels[1][3])
         elseif #labels > 1 then
         for _, label in pairs(labels) do
         local number = utils.getNumber('labels', label[3])
         if not roomLabel or (number < roomLabel and roomLabel ~= 3) or (number == 3 and roomLabel == 2) then
         roomLabel = number
         end
         end
         end
         local roomMask = rooms:eq(roomIndex)
         if roomLabel and roomMask:nonzero():size(1) > lineWidth * lineWidth * 2 then
         table.insert(roomSegments, {roomMask, roomLabel})
         end
      ]]--
   end
   return roomSegments
end

function utils.getSegmentation(width, height, representation, lineWidth, floorplan, getHeatmaps)

   local lineWidth = lineWidth or 5

   --representation.walls = utils.mergeLines(representation.walls, lineWidth)
   --local boundaryMask = utils.drawLineMask(width, height, representation.walls, lineWidth)

   local points
   if representation.points then
      points = representation.points
   else
      points = utils.linesToPoints(width, height, representation.walls, lineWidth)
   end
   --local shortWalls, wallJunctionsMap = utils.pointsToLines(width, height, points, lineWidth, true, lineWidth)
   local shortWalls = representation.walls
   local wallJunctionsMap = {}
   for _, wall in pairs(shortWalls) do
      local junctions = {}
      for index = 1, 2 do
         local minDistance = math.max(width, height)
         local minDistancePointIndex
         for pointIndex, point in pairs(points) do
            point = point[1]
            local distance = utils.calcDistance(point, wall[index])
            if distance < minDistance then
               minDistancePointIndex = pointIndex
               minDistance = distance
            end
         end
         table.insert(junctions, minDistancePointIndex)
      end
      table.insert(wallJunctionsMap, junctions)
   end
   for _, wall in pairs(shortWalls) do
      break
      local lineDim = utils.lineDim(wall, lineWidth)
      local wallFixedValue = (wall[1][3 - lineDim] + wall[2][3 - lineDim]) / 2
      local wallMinValue = math.min(wall[1][lineDim], wall[2][lineDim])
      local wallMaxValue = math.max(wall[1][lineDim], wall[2][lineDim])
      for _, longWall in pairs(representation.walls) do
         if utils.lineDim(longWall, lineWidth) == lineDim then
            local longWallFixedValue = (longWall[1][3 - lineDim] + longWall[2][3 - lineDim]) / 2
            local longWallMinValue = math.min(longWall[1][lineDim], longWall[2][lineDim])
            local longWallMaxValue = math.max(longWall[1][lineDim], longWall[2][lineDim])
            if math.abs(longWallFixedValue - wallFixedValue) <= lineWidth and longWallMinValue - lineWidth <= wallMinValue and longWallMaxValue + lineWidth >= wallMaxValue then
               if #longWall == 4 then
                  table.insert(shortWalls[_], longWall[4])
                  break
               end
            end
         end
      end
   end

   local wallMask = utils.drawLineMask(width, height, shortWalls, lineWidth, true, 0)

   local boundaryMask = utils.drawLineMask(width, height, shortWalls, lineWidth)
   --image.save('test/boundary.png', boundaryMask)
   --image.save('test/walls.png', wallMask)
   local rooms, numRooms = utils.findConnectedComponents(1 - boundaryMask)
   local backgroundRoomIndex
   local imageCorners = {{1, 1}, {width, 1}, {width, height}, {1, height}}
   for _, imageCorner in pairs(imageCorners) do
      local roomIndex = rooms[imageCorner[2]][imageCorner[1]]
      if roomIndex > 0 then
         if not backgroundRoomIndex then
            backgroundRoomIndex = roomIndex
         elseif roomIndex ~= backgroundRoomIndex then
            rooms[rooms:eq(roomIndex)] = backgroundRoomIndex
         end
      end
   end
   if not backgroundRoomIndex then
      backgroundRoomIndex = numRooms
   end
   local floorplanSegmentation = torch.zeros(#rooms)
   floorplanSegmentation[rooms:eq(backgroundRoomIndex)] = 11
   --floorplanSegmentation[rooms:eq(backgroundRoomIndex)] = 0
   local roomLabels = {}
   for _, label in pairs(representation.labels) do
      local center = {torch.round((label[1][1] + label[2][1]) / 2), torch.round((label[1][2] + label[2][2]) / 2)}
      --local number = utils.getNumber('labels', label[3])
      local roomIndex = rooms[{center[2], center[1]}]
      if roomIndex > 0 and roomIndex ~= backgroundRoomIndex then
         if not roomLabels[roomIndex] then
            roomLabels[roomIndex] = {}
         end
         table.insert(roomLabels[roomIndex], label)
      end
   end


   local hasConflict = false
   if true then
      for roomIndex, labels in pairs(roomLabels) do
         if #labels == 1 then
            floorplanSegmentation[rooms:eq(roomIndex)] = utils.getNumber('labels', labels[1][3])
         elseif #labels > 1 then
            hasConflict = true

            local majorNumber
            for _, label in pairs(labels) do
               local number = utils.getNumber('labels', label[3])
               if not majorNumber or (number < majorNumber and majorNumber ~= 3) or (majorNumber == 2 and number == 3) then
                  majorNumber = number
               end
            end

            local inferiorLabels = {}
            for _, label in pairs(labels) do
               local number = utils.getNumber('labels', label[3])
               if number ~= majorNumber then
                  table.insert(inferiorLabels, label)
               end
            end

            local roomMask = rooms:eq(roomIndex)

            roomMask = image.dilate(roomMask)
            local roomWallsTensor = wallMask[roomMask]
            local roomWallsIndices = roomWallsTensor:nonzero()
            assert(##roomWallsIndices > 0, 'conflict room without a wall')
            roomWallsTensor = roomWallsTensor:index(1, roomWallsIndices[{{}, 1}])
            local roomWalls = {}
            for i = 1, roomWallsTensor:size(1) do
               roomWalls[roomWallsTensor[i]] = true
            end
            local junctionWallsMap = {}
            for wallIndex, _ in pairs(roomWalls) do
               for index = 1, 2 do
                  local junctionIndex = wallJunctionsMap[wallIndex][index]
                  if not junctionWallsMap[junctionIndex] then
                     junctionWallsMap[junctionIndex] = {}
                  end
                  table.insert(junctionWallsMap[junctionIndex], wallIndex)
               end
            end


            for _, label in pairs(inferiorLabels) do
               local labelPoint = {(label[1][1] + label[2][1]) / 2, (label[1][2] + label[2][2]) / 2}
               local junctionWallPairMap = {}

               local wallNeighbors = {}
               for junction, walls in pairs(junctionWallsMap) do
                  if #walls == 2 and utils.lineDim(shortWalls[walls[1]]) == utils.lineDim(shortWalls[walls[2]]) then
                     for index = 1, 2 do
                        if not wallNeighbors[walls[index]] then
                           wallNeighbors[walls[index]] = {}
                        end
                        table.insert(wallNeighbors[walls[index]], walls[3 - index])
                     end
                  end

                  if #walls >= 2 then
                     local junctionPoint = points[junction][1]
                     for _, wallIndex in pairs(walls) do
                        local lineDim = utils.lineDim(shortWalls[wallIndex])
                        local wallPoint
                        for _, pointIndex in pairs(wallJunctionsMap[wallIndex]) do
                           if pointIndex ~= junction then
                              wallPoint = points[pointIndex][1]
                           end
                        end
                        for _, neighborWallIndex in pairs(walls) do
                           if neighborWallIndex > wallIndex and utils.lineDim(shortWalls[neighborWallIndex]) + lineDim == 3 then
                              local neighborWallPoint
                              for _, pointIndex in pairs(wallJunctionsMap[neighborWallIndex]) do
                                 if pointIndex ~= junction then
                                    neighborWallPoint = points[pointIndex][1]
                                 end
                              end
                              if (labelPoint[3 - lineDim] - junctionPoint[3 - lineDim]) * (neighborWallPoint[3 - lineDim] - junctionPoint[3 - lineDim]) > 0 and (labelPoint[lineDim] - junctionPoint[lineDim]) * (wallPoint[lineDim] - junctionPoint[lineDim]) > 0 then
                                 junctionWallPairMap[junction] = {wallIndex, neighborWallIndex}
                              elseif #walls == 2 and math.abs(labelPoint[3 - lineDim] - junctionPoint[3 - lineDim]) >= math.abs(labelPoint[3 - lineDim] - neighborWallPoint[3 - lineDim]) - lineWidth then
                                 for index = 1, 2 do
                                    if not wallNeighbors[walls[index]] then
                                       wallNeighbors[walls[index]] = {}
                                    end
                                    table.insert(wallNeighbors[walls[index]], walls[3 - index])
                                 end
                              end
                           end
                        end
                     end
                  end
               end



               local wallGroups = {}
               local wallGroupMap = {}
               local visitedWalls = {}
               for wallIndex, _ in pairs(wallNeighbors) do
                  if not visitedWalls[wallIndex] then
                     local wallGroup = {}
                     wallGroup[wallIndex] = true
                     visitedWalls[wallIndex] = true
                     while true do
                        local hasChange = false
                        for groupWall, _ in pairs(wallGroup) do
                           for _, neighbor in pairs(wallNeighbors[groupWall]) do
                              if not wallGroup[neighbor] then
                                 wallGroup[neighbor] = true
                                 visitedWalls[neighbor] = true
                                 hasChange = true
                              end
                           end
                        end
                        if not hasChange then
                           break
                        end
                     end
                     local group = {}
                     for groupWall, _ in pairs(wallGroup) do
                        table.insert(group, groupWall)
                        wallGroupMap[groupWall] = #wallGroups + 1
                     end
                     table.insert(wallGroups, group)
                  end
               end
               for wallIndex, _ in pairs(roomWalls) do
                  if not wallGroupMap[wallIndex] then
                     wallGroupMap[wallIndex] = #wallGroups + 1
                     table.insert(wallGroups, {wallIndex})
                  end
               end


               --[[
                  if label[3][1] == 'corridor' then
                  for i = 1, #wallGroups do
                  local testingWalls = {}
                  for _, wallIndex in pairs(wallGroups[i]) do
                  table.insert(testingWalls, shortWalls[wallIndex])
                  end
                  image.save('test/walls_' .. i .. '.png', utils.drawLineMask(width, height, testingWalls, lineWidth))
                  end
                  os.exit(1)
                  end
               ]]--

               local candidateRegions = {}
               for junction, wallPair in pairs(junctionWallPairMap) do
                  for neighborJunction, neighborWallPair in pairs(junctionWallPairMap) do
                     if neighborJunction < junction then
                        for index = 1, 2 do
                           for neighborIndex = 1, 2 do
                              if wallGroupMap[wallPair[index]] == wallGroupMap[neighborWallPair[neighborIndex]] then
                                 local lineDim = utils.lineDim(shortWalls[wallPair[3 - index]])
                                 local wallGroup = wallGroups[wallGroupMap[wallPair[3 - index]]]
                                 local minValue
                                 local maxValue
                                 for _, wallIndex in pairs(wallGroup) do
                                    local wall = shortWalls[wallIndex]
                                    if not minValue or wall[1][lineDim] < minValue then
                                       minValue = wall[1][lineDim]
                                    end
                                    if not maxValue or wall[2][lineDim] > maxValue then
                                       maxValue = wall[2][lineDim]
                                    end
                                 end

                                 --local minValue = math.min(shortWalls[wallPair[3 - index]][1][lineDim], shortWalls[wallPair[3 - index]][2][lineDim])
                                 --local maxValue = math.max(shortWalls[wallPair[3 - index]][1][lineDim], shortWalls[wallPair[3 - index]][2][lineDim])

                                 local neighborWallGroup = wallGroups[wallGroupMap[neighborWallPair[3 - neighborIndex]]]
                                 local neighborMinValue
                                 local neighborMaxValue
                                 for _, wallIndex in pairs(neighborWallGroup) do
                                    local wall = shortWalls[wallIndex]
                                    if not neighborMinValue or wall[1][lineDim] < neighborMinValue then
                                       neighborMinValue = wall[1][lineDim]
                                    end
                                    if not neighborMaxValue or wall[2][lineDim] > neighborMaxValue then
                                       neighborMaxValue = wall[2][lineDim]
                                    end
                                 end
                                 local minValue = math.max(minValue, neighborMinValue)
                                 local maxValue = math.min(maxValue, neighborMaxValue)
                                 local fixedValue_1 = shortWalls[wallPair[3 - index]][1][3 - lineDim]
                                 local fixedValue_2 = shortWalls[neighborWallPair[3 - neighborIndex]][1][3 - lineDim]
                                 fixedValue_1, fixedValue_2 = math.min(fixedValue_1, fixedValue_2), math.max(fixedValue_1, fixedValue_2)
                                 if minValue + lineWidth < maxValue and fixedValue_1 + lineWidth < fixedValue_2 then
                                    if lineDim == 1 then
                                       table.insert(candidateRegions, {{minValue, fixedValue_1}, {maxValue, fixedValue_2}})
                                    else
                                       table.insert(candidateRegions, {{fixedValue_1, minValue}, {fixedValue_2, maxValue}})
                                    end
                                 end
                              end
                           end
                        end
                     end
                  end
               end
               if #candidateRegions > 0 then
                  --print(labelPoint[1] .. ' ' .. labelPoint[2])
                  local minDistance
                  local selectedRegion
                  for _, region in pairs(candidateRegions) do
                     local center = {(region[1][1] + region[2][1]) / 2, (region[1][2] + region[2][2]) / 2}
                     local distance = utils.calcDistance(center, labelPoint)
                     --print(distance)
                     --print(region[1][1] .. ' ' ..  region[1][2] .. ' ' ..  region[2][1] .. ' ' ..  region[2][2])
                     if not minDistance or distance < minDistance then
                        selectedRegion = region
                        minDistance = distance
                     end
                  end
		  for pointIndex = 1, 2 do
		     selectedRegion[pointIndex][1] = math.min(math.max(selectedRegion[pointIndex][1], 1), width)
		     selectedRegion[pointIndex][2] = math.min(math.max(selectedRegion[pointIndex][2], 1), height)
		  end

                  floorplanSegmentation[{{selectedRegion[1][2], selectedRegion[2][2]}, {selectedRegion[1][1], selectedRegion[2][1]}}] = utils.getNumber('labels', label[3])
                  roomMask[{{selectedRegion[1][2], selectedRegion[2][2]}, {selectedRegion[1][1], selectedRegion[2][1]}}] = 0
               end
            end
            floorplanSegmentation[roomMask] = majorNumber
         end
      end
      for roomIndex = 1, numRooms - 1 do
         break
         if roomIndex ~= backgroundRoomIndex and not roomLabels[roomIndex] then
            floorplanSegmentation[rooms:eq(roomIndex)] = 10
         end
      end
   else
      for roomIndex = 1, numRooms - 1 do
         local roomMask = rooms:eq(roomIndex)
         local roomSegmentation = torch.ones(height, width) * 11

         local majorNumber

         roomMask = image.dilate(roomMask)
         local roomWallsTensor = wallMask[roomMask]
         local roomWallsIndices = roomWallsTensor:nonzero()
         assert(##roomWallsIndices > 0, 'conflict room without a wall')
         roomWallsTensor = roomWallsTensor:index(1, roomWallsIndices[{{}, 1}])
         local roomWalls = {}
         for i = 1, roomWallsTensor:size(1) do
            roomWalls[roomWallsTensor[i]] = true
         end
         for wallIndex_1, _ in pairs(roomWalls) do
            for wallIndex_2, __ in pairs(roomWalls) do
               if wallIndex_1 < wallIndex_2 then
                  local wall_1 = shortWalls[wallIndex_1]
                  local wall_2 = shortWalls[wallIndex_2]
                  local lineDim_1 = utils.lineDim(wall_1)
                  local lineDim_2 = utils.lineDim(wall_2)
                  if lineDim_1 == lineDim_2 and lineDim_1 > 0 and #wall_1 == 4 and #wall_2 == 4 then
                     local lineDim = lineDim_1
                     local fixedValue_1, fixedValue_2, roomLabel

                     local minValue = math.max(wall_1[1][lineDim], wall_2[1][lineDim])
                     local maxValue = math.min(wall_1[2][lineDim], wall_2[2][lineDim])
                     if minValue < maxValue then
                        --print({wall_1, wall_2})
                        if wall_1[1][3 - lineDim] < wall_2[1][3 - lineDim] and wall_1[4][2] == wall_2[4][1] then
                           roomLabel = wall_1[4][2]
                           fixedValue_1 = wall_1[1][3 - lineDim]
                           fixedValue_2 = wall_2[1][3 - lineDim]
                        end
                        if wall_1[1][3 - lineDim] > wall_2[1][3 - lineDim] and wall_1[4][1] == wall_2[4][2] then
                           roomLabel = wall_1[4][1]
                           fixedValue_1 = wall_2[1][3 - lineDim]
                           fixedValue_2 = wall_1[1][3 - lineDim]
                        end

                        if roomLabel then
                           if not majorNumber or (roomLabel < majorNumber and majorNumber ~= 3) or (majorNumber == 2 and roomLabel == 3) then
                              majorNumber = roomLabel
                           end

                           local invalidMask = false
                           for wallIndex, _ in pairs(roomWalls) do
                              if wallIndex ~= wallIndex_1 and wallIndex ~= wallIndex_2 then
                                 local wall = shortWalls[wallIndex]
                                 if utils.lineDim(wall) == lineDim and wall[1][3 - lineDim] > fixedValue_1 and wall[1][3 - lineDim] < fixedValue_2 and math.max(wall[1][lineDim], minValue) < math.min(wall[2][lineDim], maxValue) then
                                    invalidMask = true
                                    break
                                 end
                              end
                           end
                           if not invalidMask then
                              local mask = torch.zeros(height, width)
                              mask:narrow(3 - lineDim, minValue, maxValue - minValue + 1):narrow(lineDim, fixedValue_1, fixedValue_2 - fixedValue_1 + 1):fill(1)
                              mask = mask:byte()
                              mask:cmul(roomSegmentation:gt(roomLabel))
                              if roomLabel == 2 then
                                 mask:csub(roomSegmentation:eq(3))
                                 mask = mask:gt(0)
                              elseif roomLabel == 3 then
                                 mask:add(roomSegmentation:eq(2))
                                 mask = mask:gt(0)
                              end
                              --image.save('test/mask_' .. roomLabel .. '_' .. wallIndex_1 .. '_' .. wallIndex_2 .. '.png', mask:double())
                              roomSegmentation[mask] = roomLabel
                           end
                        end
                     end
                  end
               end
            end
         end

         local mask = torch.cmul(roomMask, roomSegmentation:eq(11))
         if roomIndex ~= backgroundRoomIndex then
            if majorNumber then
               roomSegmentation[mask] = majorNumber
            else
               roomSegmentation[mask] = 10
            end
         end

         --image.save('test/segmentation_' .. roomIndex .. '.png', utils.drawSegmentation(roomSegmentation))
         floorplanSegmentation[roomMask] = roomSegmentation[roomMask]
      end
   end


   if getHeatmaps then
      --image.save('test/floorplan.png', floorplan)
      --image.save('test/segmentation.png', utils.drawSegmentation(floorplanSegmentation))

      local heatmaps = torch.zeros(30, height, width)
      for segmentIndex = 1, 11 do
         heatmaps[segmentIndex]:copy(floorplanSegmentation:eq(segmentIndex):double())
      end

      local indexOffset = 11
      for _, icon in pairs(representation.icons) do
         local number = utils.getNumber('icons', icon[3])
         heatmaps[indexOffset + number][{{math.max(math.min(icon[1][2], icon[2][2]), 1), math.min(math.max(icon[1][2], icon[2][2]), height)}, {math.max(math.min(icon[1][1], icon[2][1]), 1), math.min(math.max(icon[1][1], icon[2][1]), width)}}] = 1
      end

      indexOffset = indexOffset + 10
      local groupWalls = {}
      for _, wall in pairs(representation.walls) do
         local group = wall[3][2]
         if not groupWalls[group] then
            groupWalls[group] = {}
         end
         table.insert(groupWalls[group], wall)
      end
      for group, walls in pairs(groupWalls) do
         local lineMask = utils.drawLineMask(width, height, walls, lineWidth):byte()
         heatmaps[indexOffset + group][lineMask] = 1
      end

      indexOffset = indexOffset + 2
      local doorWidth = doorWidth or lineWidth - 2
      local groupDoors = {}
      local doorNumberGroupMap = {}
      doorNumberGroupMap[1] = 1
      doorNumberGroupMap[2] = 1
      doorNumberGroupMap[3] = 2
      doorNumberGroupMap[4] = 3
      doorNumberGroupMap[5] = 3
      doorNumberGroupMap[6] = 4
      doorNumberGroupMap[7] = 5
      doorNumberGroupMap[8] = 5
      doorNumberGroupMap[9] = 6
      doorNumberGroupMap[10] = 2
      doorNumberGroupMap[11] = 2
      for _, door in pairs(representation.doors) do
         local number = door[3][2]
         local group = doorNumberGroupMap[number]
         if not groupDoors[group] then
            groupDoors[group] = {}
         end
         table.insert(groupDoors[group], door)
      end
      for group, doors in pairs(groupDoors) do
         local lineMask = utils.drawLineMask(width, height, doors, doorWidth):byte()
         heatmaps[indexOffset + group][lineMask] = 1
      end

      return heatmaps
   end


   if true then
      local indexOffset = 11
      local groupWalls = {}
      for _, wall in pairs(representation.walls) do
         local group = wall[3][2]
         if not groupWalls[group] then
            groupWalls[group] = {}
         end
         table.insert(groupWalls[group], wall)
      end

      for group = 2, 1, -1 do
         local walls = groupWalls[group]
         if walls then
            local lineMask = utils.drawLineMask(width, height, walls, lineWidth):byte()
            floorplanSegmentation[lineMask] = indexOffset + group
         end
      end

      --[[
         for group, walls in pairs(groupWalls) do
         local lineMask = utils.drawLineMask(width, height, walls, lineWidth):byte()
         floorplanSegmentation[lineMask] = indexOffset + group
         end
      ]]--
      --floorplanSegmentation[floorplanSegmentation:eq(0)] = 11


      local floorplanSegmentation_2 = torch.zeros(#floorplanSegmentation)
      local indexOffset = 0
      for _, icon in pairs(representation.icons) do
         local number = utils.getNumber('icons', icon[3])
	 floorplanSegmentation_2[{{math.max(math.min(icon[1][2], icon[2][2], height), 1), math.min(math.max(icon[1][2], icon[2][2], 1), height)}, {math.max(math.min(icon[1][1], icon[2][1], width), 1), math.min(math.max(icon[1][1], icon[2][1], 1), width)}}] = indexOffset + number
      end
      indexOffset = indexOffset + 10

      local doorWidth = doorWidth or lineWidth - 2
      local groupDoors = {}
      local doorNumberGroupMap = {}
      doorNumberGroupMap[1] = 1
      doorNumberGroupMap[2] = 1
      doorNumberGroupMap[3] = 2
      doorNumberGroupMap[4] = 3
      doorNumberGroupMap[5] = 3
      doorNumberGroupMap[6] = 4
      doorNumberGroupMap[7] = 5
      doorNumberGroupMap[8] = 5
      doorNumberGroupMap[9] = 6
      doorNumberGroupMap[10] = 2
      doorNumberGroupMap[11] = 2
      for _, door in pairs(representation.doors) do
         local number = door[3][2]
         local group = doorNumberGroupMap[number]
         if not groupDoors[group] then
            groupDoors[group] = {}
         end
         table.insert(groupDoors[group], door)
      end
      for group, doors in pairs(groupDoors) do
         local lineMask = utils.drawLineMask(width, height, doors, doorWidth):byte()
         floorplanSegmentation_2[lineMask] = indexOffset + group
      end

      indexOffset = indexOffset + 6
      --floorplanSegmentation_2[floorplanSegmentation_2:eq(0)] = indexOffset + 1

      return torch.cat(floorplanSegmentation:repeatTensor(1, 1, 1), floorplanSegmentation_2:repeatTensor(1, 1, 1), 1), shortWalls
   end


   local indexOffset = 11
   for _, icon in pairs(representation.icons) do
      local number = utils.getNumber('icons', icon[3])
      floorplanSegmentation[{{math.max(math.min(icon[1][2], icon[2][2]), 1), math.min(math.max(icon[1][2], icon[2][2]), height)}, {math.max(math.min(icon[1][1], icon[2][1]), 1), math.min(math.max(icon[1][1], icon[2][1]), width)}}] = indexOffset + number
   end

   indexOffset = indexOffset + 10
   local groupWalls = {}
   for _, wall in pairs(representation.walls) do
      local group = wall[3][2]
      if not groupWalls[group] then
         groupWalls[group] = {}
      end
      table.insert(groupWalls[group], wall)
   end
   for group, walls in pairs(groupWalls) do
      local lineMask = utils.drawLineMask(width, height, walls, lineWidth):byte()
      floorplanSegmentation[lineMask] = indexOffset + group
   end

   indexOffset = indexOffset + 2
   local doorWidth = doorWidth or lineWidth - 2
   local groupDoors = {}
   local doorNumberGroupMap = {}
   doorNumberGroupMap[1] = 1
   doorNumberGroupMap[2] = 1
   doorNumberGroupMap[3] = 2
   doorNumberGroupMap[4] = 3
   doorNumberGroupMap[5] = 3
   doorNumberGroupMap[6] = 4
   doorNumberGroupMap[7] = 5
   doorNumberGroupMap[8] = 5
   doorNumberGroupMap[9] = 6
   doorNumberGroupMap[10] = 2
   doorNumberGroupMap[11] = 2
   for _, door in pairs(representation.doors) do
      local number = door[3][2]
      local group = doorNumberGroupMap[number]
      if not groupDoors[group] then
         groupDoors[group] = {}
      end
      table.insert(groupDoors[group], door)
   end
   for group, doors in pairs(groupDoors) do
      local lineMask = utils.drawLineMask(width, height, doors, doorWidth):byte()
      floorplanSegmentation[lineMask] = indexOffset + group
   end



   if hasConflict and false then
      image.save('test/floorplan.png', floorplan)
      representation.points = points
      --image.save('test/representation.png', utils.drawRepresentationImage(floorplan:size(3), floorplan:size(2), nil, nil, floorplan, representation, 'P', 'L'))
      image.save('test/segmentation.png', utils.drawSegmentation(floorplanSegmentation))
      os.exit(1)
   end
   return floorplanSegmentation:repeatTensor(1, 1, 1), shortWalls
end

function utils.getPatch(floorplan, representation, opt, mode, head, regression, numLabels)
   local lineWidth = opt.lineWidth or 5
   local shift = opt.shift or lineWidth

   local width, height = floorplan:size(3), floorplan:size(2)

   local numberItems = {}
   local numbers = {}
   if mode == 'points' then
      representation.points = utils.linesToPoints(width, height, representation.walls, lineWidth)
   end

   for _, item in pairs(representation[mode]) do
      local number = utils.getNumber(mode, item[3])
      if not numberItems[number] then
         numberItems[number] = {}
         table.insert(numbers, number)
      end
      table.insert(numberItems[number], {{math.min(item[1][1], item[2][1]), math.min(item[1][2], item[2][2])}, {math.max(item[1][1], item[2][1]), math.max(item[1][2], item[2][2])}})
   end

   if head == 1 and #numbers == 0 then
      return nil, nil
   end

   local negativeProb = 0.5
   if numLabels then
      negativeProb = 1.0 / (numLabels + 1)
   end

   if head == 2 and (torch.uniform() < negativeProb or #numbers == 0) then
      local cx, cy, w, h
      for i = 1, 100 do
         cx = torch.random(width)
         cy = torch.random(height)
         local scale = 2 ^ torch.uniform(-1, 2)
         w = torch.round(opt.patchDim * scale)
         h = torch.round(opt.patchDim * scale)
         local isNegativeSample = true
         for number, items in pairs(numberItems) do
            for _, item in pairs(items) do
               if math.abs((item[1][1] + item[2][1]) / 2 - cx) < opt.shift and math.abs((item[1][2] + item[2][2]) / 2 - cy) < opt.shift then
                  isNegativeSample = false
                  break
               elseif item[1][1] > cx - w / 2 and item[1][2] > cy - h / 2 and item[2][1] < cx + w / 2 and item[2][2] < cy + h / 2 then
                  isNegativeSample = false
                  break
               end
            end
            if not isNegativeSample then
               break
            end
         end
         if isNegativeSample then
            break
         end
      end

      --[[
         local success, _ = pcall(function()
         local patch = image.crop(floorplan, torch.round(math.max(cx - w / 2, 0)), torch.round(math.max(cy - h / 2, 0)), torch.round(math.min(cx + w / 2, width)), torch.round(math.min(cy + h / 2, height)))
         end)
         if not success then
         print(#floorplan)
         print(cx .. ' ' .. cy .. ' ' .. w .. ' ' .. h)
         os.exit(1)
         end
      ]]--

      local patch = image.crop(floorplan, torch.round(math.max(cx - w / 2, 0)), torch.round(math.max(cy - h / 2, 0)), torch.round(math.min(cx + w / 2, width)), torch.round(math.min(cy + h / 2, height)))
      patch = image.scale(patch, opt.patchDim, opt.patchDim)

      patch:mul(2):add(-1)

      local label = -torch.ones(1)
      if numLabels then
         label:fill(numLabels + 1)
      end

      return patch, label
   end

   local numberSelected = numbers[torch.random(#numbers)]
   local itemsSelected = numberItems[numberSelected]
   local itemIndexSelected = torch.random(#itemsSelected)
   local itemSelected = itemsSelected[itemIndexSelected]
   local cx = itemSelected[1][1] + (itemSelected[2][1] - itemSelected[1][1]) * torch.uniform()
   local cy = itemSelected[1][2] + (itemSelected[2][2] - itemSelected[1][2]) * torch.uniform()
   local centerFound = false
   for attempt = 1, 10 do
      local closest = true
      local distanceSelected = (((itemSelected[2][1] + itemSelected[1][1]) / 2 - cx)^2 + ((itemSelected[2][2] + itemSelected[1][2]) / 2 - cy)^2)^0.5

      for number, items in pairs(numberItems) do
         for itemIndex, item in pairs(items) do
            if number ~= numberSelected or itemIndex ~= itemIndexSelected then
               local distance = (((item[2][1] + item[1][1]) / 2 - cx)^2 + ((item[2][2] + item[1][2]) / 2 - cy)^2)^0.5
               if 0.8 * distance < distanceSelected then
                  closest = false
                  break
               end
            end
         end
         if not closest then
            break
         end
      end
      if closest then
         centerFound = true
         break
      end
      cx = itemSelected[1][1] + math.max(itemSelected[2][1] - itemSelected[1][1], shift) * torch.uniform()
      cy = itemSelected[1][2] + math.max(itemSelected[2][2] - itemSelected[1][2], shift) * torch.uniform()
   end
   if not centerFound then
      return nil, nil
   end

   local item = itemSelected

   local maxDim = math.max(item[2][1] - item[1][1], item[2][2] - item[1][2], lineWidth)
   local minScale = opt.minScale or 1
   local maxScale = opt.maxScale or 2.5
   if head == 2 and regression then
      maxScale = 2
   end
   if model == 'points' then
      minScale = 2
      maxScale = 3
   end

   local w = math.max(math.min(maxDim * (2 ^ torch.uniform(minScale, maxScale) - 1), cx * 2, cy * 2, (width - cx) * 2, (height - cy) * 2), cx - item[1][1], cy - item[1][2], item[2][1] - cx, item[2][2] - cy, lineWidth)
   local h = w
   if maxDim == 0 then
      return nil, nil
   end
   --print(maxDim)
   --print(cx .. ' ' .. cy .. ' ' .. w .. ' ' .. h)
   --print(item[1][1] .. ' ' .. item[1][2] .. ' ' .. item[2][1] .. ' ' .. item[2][2])

   local patch = image.crop(floorplan, torch.round(math.max(cx - w / 2, 0)), torch.round(math.max(cy - h / 2, 0)), torch.round(math.min(cx + w / 2, width)), torch.round(math.min(cy + h / 2, height)))
   patch = image.scale(patch, opt.patchDim, opt.patchDim)
   patch:mul(2):add(-1)

   if head == 1 then
      if not regression then
         local mask = torch.zeros(height, width)
         mask:narrow(1, item[1][2], item[2][2] - item[1][2] + 1):narrow(2, item[1][1], item[2][1] - item[1][1] + 1):fill(1)
         mask = image.crop(mask, torch.round(math.max(cx - w / 2, 0)), torch.round(math.max(cy - h / 2, 0)), torch.round(math.min(cx + w / 2, width)), torch.round(math.min(cy + h / 2, height)))
         mask = image.scale(mask, opt.outputDim, opt.outputDim, 'simple'):gt(0.5):double()
         mask:mul(2):add(-1)

         if torch.uniform() < 0.5 then
            patch = image.hflip(patch)
            mask = image.hflip(mask)
         end

         return patch, mask
      else
         local cxBox = (item[1][1] + item[2][1]) / 2 - torch.round(math.max(cx - w / 2, 0))
         local cyBox = (item[1][2] + item[2][2]) / 2 - torch.round(math.max(cy - h / 2, 0))
         local wBox = item[2][1] - item[1][1]
         local hBox = item[2][2] - item[1][2]
         wBox = math.max(wBox, lineWidth)
         hBox = math.max(hBox, lineWidth)
         local wPatch = torch.round(math.min(cx + w / 2, width)) - torch.round(math.max(cx - w / 2, 0))
         local hPatch = torch.round(math.min(cy + h / 2, height)) - torch.round(math.max(cy - h / 2, 0))

         local coordinates = torch.Tensor({cxBox / wPatch, cyBox / hPatch, math.log(wBox / wPatch), math.log(hBox / hPatch)})

         --local lineDim = utils.lineDim(item)
         --if lineDim > 0 then
         --coordinates[5 - lineDim] =
         --end

         if torch.uniform() < 0.5 then
            patch = image.hflip(patch)
            coordinates[1] = 1 - coordinates[1]
         end

         return patch, coordinates
      end
   else
      local label = torch.ones(1)
      if numLabels then
         label:fill(numberSelected)
      end
      return patch, label
   end
end


function utils.getPatchGrid(floorplan, representation, opt, mode, head, regression, numLabels)
   local lineWidth = opt.lineWidth or 5
   local oriWidth, oriHeight = floorplan:size(3), floorplan:size(2)
   local sampleDim = opt.sampleDim or 448
   local gridDim = sampleDim / 16
   local patchDim = opt.patchDim or 16 * 7



   local minScale = opt.minScale or 0
   local maxScale = opt.maxScale or 1
   local scale = 2^torch.uniform(minScale, maxScale)

   local width = torch.round(oriWidth * scale)
   local height = torch.round(oriHeight * scale)

   local sample = image.scale(floorplan, width, height)
   representation = utils.scaleRepresentation(representation, oriWidth, oriHeight, width, height)


   if width < sampleDim and height < sampleDim then
      local newSample = torch.zeros(3, sampleDim, sampleDim)
      newSample[{{}, {1, height}, {1, width}}]:copy(sample)
      sample = newSample
   elseif width < sampleDim then
      local newSample = torch.zeros(3, height, sampleDim)
      newSample[{{}, {1, height}, {1, width}}]:copy(sample)
      sample = newSample
   elseif height < sampleDim then
      local newSample = torch.zeros(3, sampleDim, width)
      newSample[{{}, {1, height}, {1, width}}]:copy(sample)
      sample = newSample
   end

   width = sample:size(3)
   height = sample:size(2)

   local x = 0
   if width > sampleDim then
      x = torch.random(width - sampleDim)
   end
   local y = 0
   if height > sampleDim then
      y = torch.random(height - sampleDim)
   end

   --print(#sample)
   --print(x .. ' ' .. y)
   --print(sampleDim)
   sample = image.crop(sample, x, y, x + sampleDim, y + sampleDim)
   representation = utils.cropRepresentation(representation, x, y, x + sampleDim, y + sampleDim)

   local items = representation[mode]

   local cellWidth = sampleDim / gridDim
   local cellHeight = sampleDim / gridDim
   local gridTensor = torch.zeros(6, gridDim, gridDim)

   for gridY = 1, gridDim do
      for gridX = 1, gridDim do
         local cx = cellWidth * (gridX - 1 + 0.5)
         local cy = cellHeight * (gridY - 1 + 0.5)
         local w = patchDim
         local h = patchDim
         local maxIOU
         local maxIOUCoordinates
         local maxIOUNumber
         local sumIOU = 0
         local atCenter = false
         for _, item in pairs(items) do
            if math.max(item[1][1], cx - w / 2) <= math.min(item[2][1], cx + w / 2) and math.max(item[1][2], cy - h / 2) <= math.min(item[2][2], cy + h / 2) then
               local intersection = (math.min(cx + w / 2, item[2][1] + 1) - math.max(cx - w / 2, item[1][1])) * (math.min(cy + h / 2, item[2][2] + 1) - math.max(cy - h / 2, item[1][2]))
               --local union = w * h + (item[2][1] - item[1][1]) * (item[2][2] - item[1][2]) - intersection
               local union = (item[2][1] - item[1][1] + 1) * (item[2][2] - item[1][2] + 1)
               local IOU = intersection / union
               if not maxIOU or IOU > maxIOU then
                  maxIOU = IOU
                  local x_1 = math.max(item[1][1], cx - w / 2)
                  local x_2 = math.min(item[2][1], cx + w / 2)
                  local y_1 = math.max(item[1][2], cy - h / 2)
                  local y_2 = math.min(item[2][2], cy + h / 2)

                  local boxX = ((x_1 + x_2) / 2 - (cx - w / 2)) / w
                  local boxY = ((y_1 + y_2) / 2 - (cy - h / 2)) / h
                  local boxW = math.log(math.max(x_2 - x_1 + 1, lineWidth) / w)
                  local boxH = math.log(math.max(y_2 - y_1 + 1, lineWidth) / h)
                  maxIOUCoordinates = torch.Tensor({boxX, boxY, boxW, boxH})
                  maxIOUNumber = utils.getNumber(mode, item[3])
                  if item[1][1] < cx and item[2][1] > cx and item[1][2] < cy and item[2][2] > cy then
                     atCenter = true
                  end
               end
               sumIOU = sumIOU + IOU
            end
         end

         if maxIOU then
            --[[
               print(maxIOUNumber)
               print(gridX .. ' ' .. gridY)
               print(maxIOU .. ' ' .. sumIOU)
               print(maxIOUCoordinates)
            ]]--

            if not atCenter then
               maxIOU = math.min(maxIOU / sumIOU, maxIOU)
            end

            gridTensor[{{1, 4}, gridY, gridX}] = maxIOUCoordinates
            gridTensor[{5, gridY, gridX}] = maxIOU
            gridTensor[{6, gridY, gridX}] = maxIOUNumber

            if maxIOU > 0.95 and false then
               print(gridTensor[{{}, gridY, gridX}])
               local x_1 = math.max(0, cx - w / 2)
               local x_2 = math.min(sampleDim, cx + w / 2)
               local y_1 = math.max(0, cy - h / 2)
               local y_2 = math.min(sampleDim, cy + h / 2)
               image.save('test/sample_' .. maxIOUNumber .. '.png', image.crop(sample, x_1, y_1, x_2, y_2))
            end
         end
      end
   end


   if false then
      representation.points = utils.linesToPoints(sample:size(3), sample:size(2), representation.walls, lineWidth)
      image.save('test/floorplan.png', sample)
      image.save('test/representation.png', utils.drawRepresentationImage(sample:size(3), sample:size(2), nil, nil, sample, representation, 'P', 'L'))
      os.exit(1)
   end



   sample:mul(2):add(-1)

   return sample, gridTensor
end

function utils.drawJunctionMasks(width, height, points, maxNumPoints, pointLineLength, kernelSize)
   local junctionMasks = torch.zeros(maxNumPoints, height, width)

   local pointLineLength = pointLineLength or 15
   local kernelSize = kernelSize or 7
   local pointOrientations = {}
   for pointIndex, point in pairs(points) do
      local orientations = {}
      local orientation = point[3][3]
      if point[3][2] == 1 then
         table.insert(orientations, (orientation + 2 - 1) % 4 + 1)
      elseif point[3][2] == 2 then
         table.insert(orientations, orientation)
         table.insert(orientations, (orientation + 3 - 1) % 4 + 1)
      elseif point[3][2] == 3 then
         for i = 1, 4 do
            if i ~= orientation then
               table.insert(orientations, i)
            end
         end
      else
         for i = 1, 4 do
            table.insert(orientations, i)
         end
      end
      pointOrientations[pointIndex] = orientations
   end

   local deltas = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}}
   local maxNumPoints = maxNumPoints or #points
   for pointIndex, point in pairs(points) do
      if pointIndex > maxNumPoints then
         break
      end
      for _, orientation in pairs(pointOrientations[pointIndex]) do
         local x = torch.round(point[1][1])
         local y = torch.round(point[1][2])
         local delta = deltas[orientation]
         x = math.max(math.min(x, width), 1)
         y = math.max(math.min(y, height), 1)
         for i = 1, pointLineLength do
            if x < 1 or x > width or y < 1 or y > height then
               break
            end
            junctionMasks[pointIndex][y][x] = 1
            x = x + delta[1]
            y = y + delta[2]
         end
      end
   end

   if kernelSize > 0 then
      local kernel = image.gaussian(kernelSize)
      for i = 1, junctionMasks:size(1) do
         junctionMasks[i] = image.convolve(junctionMasks[i], kernel, 'same')
      end
   end
   return junctionMasks
end

function utils.getRoomJunctions(width, height, representation, lineWidth, maxNumPoints)
   local lineWidth = lineWidth or 5

   local walls = utils.pointsToLines(width, height, representation.points, lineWidth)
   local wallMask = utils.drawLineMask(width, height, walls, lineWidth)
   local rooms, numRooms = utils.findConnectedComponents(1 - wallMask)
   numRooms = numRooms - 1
   local backgroundRoomIndex
   local imageCorners = {{1, 1}, {width, 1}, {width, height}, {1, height}}
   for _, imageCorner in pairs(imageCorners) do
      local roomIndex = rooms[imageCorner[2]][imageCorner[1]]
      if roomIndex > 0 then
         if not backgroundRoomIndex then
            backgroundRoomIndex = roomIndex
         elseif roomIndex ~= backgroundRoomIndex then
            rooms[rooms:eq(roomIndex)] = backgroundRoomIndex
         end
      end
   end
   if not backgroundRoomIndex then
      backgroundRoomIndex = numRooms
   end

   local roomIndexMap = {}
   roomIndexMap[rooms[1][1]] = 0
   for _, label in pairs(representation.labels) do
      local center = {torch.round((label[1][1] + label[2][1]) / 2), torch.round((label[1][2] + label[2][2]) / 2)}
      local number = utils.getNumber('labels', label[3])
      local roomIndex = rooms[{center[2], center[1]}]
      if roomIndex > 0 and roomIndex ~= backgroundRoomIndex then
         local segmentIndex = roomIndexMap[roomIndex]
         if not segmentIndex or (number < segmentIndex and (number ~= 2 or segmentIndex ~= 3)) or (number == 3 and segmentIndex == 2) then
            roomIndexMap[roomIndex] = number
         end
      end
   end

   local roomJunctionCounter = {}
   local maxNumPoints = maxNumPoints or 40
   local deltas = {{-1, -1}, {-1, 1}, {1, -1}, {1, 1}}

   for pointIndex, point in pairs(representation.points) do
      if pointIndex > maxNumPoints then
         break
      end

      for _, delta in pairs(deltas) do
         local x = torch.round(point[1][1])
         local y = torch.round(point[1][2])
         while x >= 1 and x <= width and y >= 1 and y <= height and wallMask[y][x] == 1 do
            x = x + delta[1]
            y = y + delta[2]
         end
         if x >= 1 and x <= width and y >= 1 and y <= height then
            local roomIndex = rooms[y][x]
            if roomJunctionCounter[roomIndex] == nil then
               roomJunctionCounter[roomIndex] = {}
            end
            if roomJunctionCounter[roomIndex][pointIndex] == nil then
               roomJunctionCounter[roomIndex][pointIndex] = 0
            end
            roomJunctionCounter[roomIndex][pointIndex] = roomJunctionCounter[roomIndex][pointIndex] + 1
         end
      end
   end

   local roomJunctions = torch.zeros(10, maxNumPoints)
   for roomIndex = 1, numRooms do
      local label = roomIndexMap[roomIndex]
      if label == nil then
         label = 10
      end
      if label >= 1 and label <= 10 and roomIndex ~= backgroundRoomIndex then
         local junctionCounter = roomJunctionCounter[roomIndex]
         if junctionCounter then
            for pointIndex, count in pairs(junctionCounter) do
               roomJunctions[label][pointIndex] = 1
            end
         end
      end
   end

   local junctionMasks = utils.drawJunctionMasks(width, height, representation.points, maxNumPoints)
   return junctionMasks, roomJunctions
end

function utils.parseFloorplan(floorplanInput)

   local binaryThreshold = 0.7

   --image.save('test/floorplan.png', floorplanInput)
   --image.save('test/floorplan_segmentation.png', ut.drawSegmentation(floorplanSegmentation, numSegments))
   --image.save('test/floorplan_binary.png', floorplanBinary)

   if borderSegmentReversed == 0 then
      return
   end

   local characterMasks = torch.cmul(1 - floorplanSegmentationReversed:eq(backgroundSegmentReversed), 1 - floorplanSegmentationReversed:eq(borderSegmentReversed))
   --image.save('test/invalid_mask_1.png', 1 - floorplanSegmentationReversed:eq(foregroundSegment))
   --image.save('test/invalid_mask_2.png', 1 - floorplanSegmentationReversed:eq(maxCountSegment))
   --image.save('test/character_masks.png', characterMasks:double())

   local borderMask = floorplanSegmentationReversed:eq(borderSegmentReversed)
   local borderIndices = borderMask:nonzero()
   local borderSegment = floorplanSegmentation[{borderIndices[1][1], borderIndices[1][2]}]

   --[[
      local borderThickness = 0
      local borderMaskEroded = borderMask:clone()
      while true do
      if ##borderMaskEroded:eq(1):nonzero() > 0 then
      borderMaskEroded = image.erode(borderMaskEroded)
      borderThickness = borderThickness + 2
      else
      borderThickness = borderThickness + 1
      break
      end
      end
   ]]--
   --print("borderThickness: " .. borderThickness)
   borderMask = image.dilate(borderMask)
   local floorplanSegmentationErodedOnce = torch.cmul(floorplanSegmentation, (1 - borderMask):int())
   --floorplanSegmentationErodedOnce = floorplanSegmentation:clone()

   --[[
      local numDilations = math.floor(borderThickness / 2)
      for i = 2, numDilations do
      borderMask = image.dilate(borderMask)
      end
      local floorplanSegmentationEroded = torch.cmul(floorplanSegmentation, (1 - borderMask):int())
   ]]--

   local floorplanSegmentationRefined = floorplanSegmentation:clone()
   local backgroundSegment = floorplanSegmentation[1][1]
   floorplanSegmentationRefined[floorplanSegmentation:eq(backgroundSegment)] = 1
   floorplanSegmentationRefined[floorplanSegmentation:eq(borderSegment)] = 0

   local segmentInfo = {
      mins = {},
      maxs = {},
      means = {},
      nums = {},
      samples = {},
   }
   for segment = 1, numSegments do
      if segment ~= backgroundSegment and segment ~= borderSegment then
         local indices = floorplanSegmentation:eq(segment):nonzero()
         segmentInfo.mins[segment] = torch.min(indices, 1)[1]
         segmentInfo.maxs[segment] = torch.max(indices, 1)[1]
         segmentInfo.means[segment] = torch.mean(indices:double(), 1)[1]
         segmentInfo.nums[segment] = (#indices)[1]
         segmentInfo.samples[segment] = indices[1]
      end
   end

   local largeSegments = {}
   local smallSegments = {}
   for segment = 1, numSegments do
      if segment ~= backgroundSegment and segment ~= borderSegment then
         --if ##floorplanSegmentationEroded:eq(segment):nonzero() == 0 then
         --floorplanSegmentationRefined[floorplanSegmentation:eq(segment)] = 0
         if ##floorplanSegmentationErodedOnce:eq(segment):nonzero() > 0 and (#floorplanSegmentationErodedOnce:eq(segment):nonzero())[1] == segmentInfo.nums[segment] then
            table.insert(smallSegments, segment)
         elseif segmentInfo.maxs[segment][1] - segmentInfo.mins[segment][1] < borderThickness or segmentInfo.maxs[segment][2] - segmentInfo.mins[segment][2] < borderThickness then
            floorplanSegmentationRefined[floorplanSegmentation:eq(segment)] = 0
         else
            table.insert(largeSegments, segment)
         end
      end
   end
   local characterSegmentsReversed = {}
   for segmentReversed = 1, numSegmentsReversed do
      if segmentReversed ~= backgroundSegmentReversed and segmentReversed ~= borderSegmentReversed then
         table.insert(characterSegmentsReversed, segmentReversed)
      end
   end
   --print(smallSegments)

   local characterSegmentInfo = {
      mins = {},
      maxs = {},
      means = {},
      nums = {},
   }
   for _, characterSegmentReversed in pairs(characterSegmentsReversed) do
      local indices = floorplanSegmentationReversed:eq(characterSegmentReversed):nonzero()
      characterSegmentInfo.mins[characterSegmentReversed] = torch.min(indices, 1)[1]
      characterSegmentInfo.maxs[characterSegmentReversed] = torch.max(indices, 1)[1]
      characterSegmentInfo.means[characterSegmentReversed] = torch.mean(indices:double(), 1)[1]
      characterSegmentInfo.means[characterSegmentReversed] = (#indices)[1]
   end

   for _, smallSegment in pairs(smallSegments) do
      local minDistance
      local minDistanceLargeSegment
      for _, largeSegment in pairs(largeSegments) do
         if segmentInfo.mins[smallSegment][1] >= segmentInfo.mins[largeSegment][1] and segmentInfo.mins[smallSegment][2] >= segmentInfo.mins[largeSegment][2] and segmentInfo.maxs[smallSegment][1] <= segmentInfo.maxs[largeSegment][1] and segmentInfo.maxs[smallSegment][2] <= segmentInfo.maxs[largeSegment][2] then
            local distance = torch.norm(segmentInfo.means[smallSegment] - segmentInfo.means[largeSegment])
            if minDistance == nil or distance < minDistance then
               minDistanceLargeSegment = largeSegment
               minDistance = distance
            end
         end
      end
      if minDistanceLargeSegment == nil then
         minDistanceLargeSegment = 1
      end
      floorplanSegmentationRefined[floorplanSegmentation:eq(smallSegment)] = minDistanceLargeSegment
   end

   for _, characterSegmentReversed in pairs(characterSegmentsReversed) do
      local minDistance
      local minDistanceLargeSegment
      for _, largeSegment in pairs(largeSegments) do
         if characterSegmentInfo.mins[characterSegmentReversed][1] >= segmentInfo.mins[largeSegment][1] and characterSegmentInfo.mins[characterSegmentReversed][2] >= segmentInfo.mins[largeSegment][2] and characterSegmentInfo.maxs[characterSegmentReversed][1] <= segmentInfo.maxs[largeSegment][1] and characterSegmentInfo.maxs[characterSegmentReversed][2] <= segmentInfo.maxs[largeSegment][2] then
            local distance = torch.norm(characterSegmentInfo.means[characterSegmentReversed] - segmentInfo.means[largeSegment])
            if minDistance == nil or distance < minDistance then
               minDistanceLargeSegment = largeSegment
               minDistance = distance
            end
         end
      end
      if minDistanceLargeSegment == nil then
         minDistanceLargeSegment = 1
      end
      floorplanSegmentationRefined[floorplanSegmentationReversed:eq(characterSegmentReversed)] = minDistanceLargeSegment
      characterMasks[floorplanSegmentationReversed:eq(characterSegmentReversed)] = minDistanceLargeSegment

   end

   --[[
      segmentInfo.indices = {}
      for _, largeSegment in pairs(largeSegments) do
      local indices = floorplanSegmentationRefined:eq(largeSegment):nonzero()
      segmentInfo.indices[largeSegment] = indices
      segmentInfo.mins[largeSegment] = torch.min(indices, 1)[1]
      segmentInfo.maxs[largeSegment] = torch.max(indices, 1)[1]
      segmentInfo.means[largeSegment] = torch.mean(indices:double(), 1)[1]
      segmentInfo.nums[largeSegment] = (#indices)[1]
      end
   ]]--

   local borderMask = floorplanSegmentationRefined:eq(0)
   borderMask[floorplanSegmentationRefined:eq(1)] = 1
   borderMask = image.erode(borderMask)
   local borderMaskByte = (borderMask * 255):byte()
   local floorplanSegmentationCoarse = torch.IntTensor(borderMaskByte:size())
   local numSegmentCoarse = cv.connectedComponents{255 - borderMaskByte, floorplanSegmentationCoarse}
   floorplanSegmentationCoarse = floorplanSegmentationCoarse + 1
   --image.save('test/floorplan_segmentation_coarse.png', ut.drawSegmentation(floorplanSegmentationCoarse, numSegmentCoarse))
   local coarseToFineSegmentMap = {}
   for segment = 1, numSegmentCoarse do
      coarseToFineSegmentMap[segment] = {}
   end
   for _, largeSegment in pairs(largeSegments) do
      table.insert(coarseToFineSegmentMap[floorplanSegmentationCoarse[segmentInfo.samples[largeSegment][1]][segmentInfo.samples[largeSegment][2]]], largeSegment)
   end
   for segmentCoarse = 1, numSegmentCoarse do
      local mins
      local maxs
      local maxNum
      local maxNumSegment
      local count = 0
      for _, largeSegment in pairs(coarseToFineSegmentMap[segmentCoarse]) do
         count = count + 1
         if maxNum == nil or segmentInfo.nums[largeSegment] > maxNum then
            maxNumSegment = largeSegment
            maxNum = segmentInfo.nums[largeSegment]
         end
         if mins == nil then
            mins = segmentInfo.mins[largeSegment]
            maxs = segmentInfo.maxs[largeSegment]
         else
            for i = 1, 2 do
               mins[i] = math.min(mins[i], segmentInfo.mins[largeSegment][i])
               maxs[i] = math.max(maxs[i], segmentInfo.maxs[largeSegment][i])
            end
         end
      end
      if count > 1 then
         local newSegmentWidth = maxs[1] - mins[1] + 1
         local newSegmentHeight = maxs[2] - mins[2] + 1
         local cornerMask = torch.zeros((#floorplanSegmentation)[1], (#floorplanSegmentation)[2])
         cornerMask:narrow(1, mins[1], newSegmentWidth):narrow(2, mins[2], newSegmentHeight):fill(1)
         cornerMask = torch.cmul(cornerMask:byte(), 1 - floorplanSegmentationCoarse:eq(segmentCoarse))
         cornerMask:narrow(1, segmentInfo.mins[maxNumSegment][1], segmentInfo.maxs[maxNumSegment][1] - segmentInfo.mins[maxNumSegment][1] + 1):narrow(2, segmentInfo.mins[maxNumSegment][2], segmentInfo.maxs[maxNumSegment][2] - segmentInfo.mins[maxNumSegment][2] + 1):fill(0)

         --local oriSegmentArea = (segmentInfo.maxs[maxNumSegment][1] - segmentInfo.mins[maxNumSegment][1] + 1) * (segmentInfo.maxs[maxNumSegment][2] - segmentInfo.mins[maxNumSegment][2] + 1)
         if ##cornerMask:nonzero() == 0 or (#cornerMask:nonzero())[1] < newSegmentWidth * newSegmentHeight * 0.1 then
            for _, largeSegment in pairs(coarseToFineSegmentMap[segmentCoarse]) do
               if largeSegment ~= maxNumSegment then
                  floorplanSegmentationRefined[floorplanSegmentationRefined:eq(largeSegment)] = maxNumSegment
                  characterMasks[characterMasks:eq(largeSegment)] = maxNumSegment
               end
            end
         end
      end
   end

   local newSegment = 1
   for segment = 1, numSegments do
      if ##floorplanSegmentationRefined:eq(segment):nonzero() > 0 then
         floorplanSegmentationRefined[floorplanSegmentationRefined:eq(segment)] = newSegment
         characterMasks[characterMasks:eq(segment)] = newSegment
         newSegment = newSegment + 1
      end
   end
   local numSegmentsRefined = newSegment - 1
   return floorplanSegmentationRefined, characterMasks, numSegmentsRefined
end

function utils.checkSanity(floorplan, representation, lineWidth)
   local lineWidth = lineWidth or 5

   local width = floorplan:size(3)
   local height = floorplan:size(2)

   for mode, items in pairs(representation) do
      if #items == 0 then
         print('no ' .. mode)
         return false
      end
   end

   for labelIndex_1, label_1 in pairs(representation.labels) do
      for labelIndex_2, label_2 in pairs(representation.labels) do
         if labelIndex_2 > labelIndex_1 then
            if math.abs((label_1[1][1] + label_1[2][1]) / 2 - (label_2[1][1] + label_2[2][1]) / 2) < 5 and math.abs((label_1[1][2] + label_1[2][2]) / 2 - (label_2[1][2] + label_2[2][2]) / 2) < 5 then
               print('two labels overlap: ' .. (label_1[1][1] + label_1[2][1]) / 2 .. ' ' .. (label_1[1][2] + label_1[2][2]) / 2 .. ' ' .. label_1[3][1] .. ' ' .. label_2[3][1])
               return false
            end
         end
      end
   end

   local wallMask = utils.drawLineMask(width, height, representation.walls, lineWidth)
   local rooms, numRooms = utils.findConnectedComponents(1 - wallMask)

   local backgroundRoomIndex
   local imageCorners = {{1, 1}, {width, 1}, {width, height}, {1, height}}
   for _, imageCorner in pairs(imageCorners) do
      local roomIndex = rooms[imageCorner[2]][imageCorner[1]]
      if roomIndex > 0 then
         if not backgroundRoomIndex then
            backgroundRoomIndex = roomIndex
         elseif roomIndex ~= backgroundRoomIndex then
            rooms[rooms:eq(roomIndex)] = backgroundRoomIndex
         end
      end
   end
   if not backgroundRoomIndex then
      backgroundRoomIndex = numRooms
   end

   local roomLabelsMap = {}
   for roomIndex = 1, numRooms - 1 do
      roomLabelsMap[roomIndex] = {}
   end

   for _, label in pairs(representation.labels) do
      local center = {torch.round((label[1][1] + label[2][1]) / 2), torch.round((label[1][2] + label[2][2]) / 2)}
      local number = utils.getNumber('labels', label[3])
      local roomIndex = rooms[{center[2], center[1]}]
      if roomIndex == 0 then
         print('label ' .. label[1][1] .. ' ' .. label[1][2] .. ' ' .. label[2][1] .. ' ' .. label[2][2] .. ' ' .. label[3][1] .. ' is on walls')
         return false
      end
      if roomIndex == backgroundRoomIndex then
         if label[3][1] ~= 'corridor' then
            print('label ' .. label[1][1] .. ' ' .. label[1][2] .. ' ' .. label[2][1] .. ' ' .. label[2][2] .. ' ' .. label[3][1] .. ' is on background')
            return false
         end
      end

      table.insert(roomLabelsMap[roomIndex], label[3][1])
   end

   local sanityLabelsPairs = {{'living_room', 'kitchen'}, {'kitchen', 'bedroom'}, {'kitchen', 'corridor'}, {'living_room', 'corridor'}, {'bedroom', 'corridor'}, {'closet', 'corridor'}, {'corridor', 'corridor'}, {'corridor', 'washing_room'}, {'bedroom', 'washing_room'}, {'living_room', 'washing_room'}, {'kitchen', 'washing_room'}, {'restroom', 'washing_room'}}
   sanityLabelMap = {}
   for _, sanityLabelsPair in pairs(sanityLabelsPairs) do
      if not sanityLabelMap[sanityLabelsPair[1]] then
         sanityLabelMap[sanityLabelsPair[1]] = {}
      end
      sanityLabelMap[sanityLabelsPair[1]][sanityLabelsPair[2]] = true
      if not sanityLabelMap[sanityLabelsPair[2]] then
         sanityLabelMap[sanityLabelsPair[2]] = {}
      end
      sanityLabelMap[sanityLabelsPair[2]][sanityLabelsPair[1]] = true
   end

   for roomIndex, labels in pairs(roomLabelsMap) do
      if #labels > 1 then
         for _, label_1 in pairs(labels) do
            for __, label_2 in pairs(labels) do
               if __ > _ then
                  if not sanityLabelMap[label_1] or not sanityLabelMap[label_1][label_2] then
                     print(label_1 .. ' and ' .. label_2 .. ' exist in the same room')
                     return
                  end
               end
            end
         end
      end
   end

   local doorWidth = lineWidth - 2
   local doorMask = utils.drawLineMask(width, height, representation.doors, doorWidth, true, 0)
   local indices = doorMask:nonzero()

   if ##indices == 0 and false then
      print('no door pixel')
      return false
   end

   for i = 1, indices:size(1) do
      local y = indices[i][1]
      local x = indices[i][2]
      local wallIndex = wallMask[y][x]
      local doorIndex = doorMask[y][x]
      local doorDim = utils.lineDim(representation.doors[doorIndex])
      if wallIndex == 0 and doorDim > 0 then
         --image.save('test/doors.png', utils.drawSegmentation(doorMask))
         --image.save('test/door.png', doorMask:eq(2):double())
         --print(doorIndex)
         --print(representation.doors[doorIndex][1][1])
         --print(representation.doors[doorIndex][1][2])
         --nprint(representation.doors[doorIndex][2][1])
         --print(representation.doors[doorIndex][2][2])
         print('door pixel ' .. x .. ' ' .. y .. ' is not on a wall')
         --.. representation.doors[doorIndex][1][doorDim] .. ' ' .. representation.doors[doorIndex][2][doorDim] .. ' ' .. doorDim)
         return false
      end
   end

   local gap = lineWidth
   for lineIndex_1, line_1 in pairs(representation.doors) do
      local lineDim_1 = utils.lineDim(line_1)
      if lineDim_1 > 0 then
         local fixedValue_1 = (line_1[1][3 - lineDim_1] + line_1[2][3 - lineDim_1]) / 2
         for lineIndex_2, line_2 in pairs(representation.doors) do
            if lineIndex_2 > lineIndex_1 then
               local lineDim_2 = utils.lineDim(line_2)
               if lineDim_2 == lineDim_1 then
                  local fixedValue_2 = (line_2[1][3 - lineDim_2] + line_2[2][3 - lineDim_2]) / 2
                  --local nearestPair, minDistance = utils.findNearestJunctionPair(line_1, line_2, gap, false)
                  --print(minDistance .. ' ' .. lineDim_1 .. ' ' .. lineDim_2)
                  local lineDim = lineDim_1
                  if math.abs(fixedValue_2 - fixedValue_1) <= gap and math.min(math.max(line_2[1][lineDim], line_2[2][lineDim]), math.max(line_1[1][lineDim], line_1[2][lineDim])) > math.max(math.min(line_2[1][lineDim], line_2[2][lineDim]), math.min(line_1[1][lineDim], line_1[2][lineDim])) then
                     --local pointIndex_1 = nearestPair[1]
                     --local pointIndex_2 = nearestPair[2]
                     --print(lineIndex_1 .. ' ' .. lineIndex_2)
                     print('two door overlap ' .. line_1[1][1] .. ' ' .. line_1[1][2])
                     --.. ' ' .. line_1[3 - pointIndex_1][lineDim_1] .. ' ' .. line_2[3 - pointIndex_2][lineDim_2] .. ' ' .. lineDim_1)
                     --print('line dim ' .. lineDim_1)
                     return false
                  end
               end
            end
         end
      end
   end

   local gap = lineWidth
   for lineIndex_1, line_1 in pairs(representation.walls) do
      local lineDim_1 = utils.lineDim(line_1)
      if lineDim_1 > 0 then
         local fixedValue_1 = (line_1[1][3 - lineDim_1] + line_1[2][3 - lineDim_1]) / 2
         for lineIndex_2, line_2 in pairs(representation.walls) do
            if lineIndex_2 > lineIndex_1 and line_2[3][2] == line_1[3][2] then
               local lineDim_2 = utils.lineDim(line_2)
               if lineDim_2 == lineDim_1 then
                  local fixedValue_2 = (line_2[1][3 - lineDim_2] + line_2[2][3 - lineDim_2]) / 2
                  local nearestPair, minDistance = utils.findNearestJunctionPair(line_1, line_2, gap, false)
                  --print(minDistance .. ' ' .. lineDim_1 .. ' ' .. lineDim_2)
                  if minDistance <= gap then
                     local pointIndex_1 = nearestPair[1]
                     local pointIndex_2 = nearestPair[2]
                     --print(lineIndex_1 .. ' ' .. lineIndex_2)
                     if pointIndex_1 > 0 and pointIndex_2 > 0 then
                        print('two walls should be merged at pixel ' .. line_1[pointIndex_1][1] .. ' ' .. line_1[pointIndex_1][2])
                        --.. ' ' .. line_1[3 - pointIndex_1][lineDim_1] .. ' ' .. line_2[3 - pointIndex_2][lineDim_2] .. ' ' .. lineDim_1)
                        --print('line dim ' .. lineDim_1)
                        return false
                     end
                  end
               end
            end
         end
      end
   end
   return true
end

function utils.drawDoorMasks(width, height, doors, doorWidth)
   local labelDoorsMap = {}
   for _, door in pairs(doors) do
      local label = utils.getNumber('doors', door[3])
      if not labelDoorsMap[label] then
         labelDoorsMap[label] = {}
      end
      table.insert(labelDoorsMap[label], door)
   end
   local doorMasks = torch.zeros(13, width, height)
   for label, labelDoors in pairs(labelDoorsMap) do
      doorMasks[label] = utils.drawLineMask(width, height, labelDoors, doorWidth)
   end
   return doorMasks
end

function utils.filterJunctions(width, height, points, wallMask)
   local pointOrientations = {{{3}, {4}, {1}, {2}}, {{4, 1}, {1, 2}, {2, 3}, {3, 4}}, {{2, 3, 4}, {3, 4, 1}, {4, 1, 2}, {1, 2, 3}}, {{1, 2, 3, 4}}}
   local orientationRanges = torch.Tensor({{width, 0, 0, 0}, {width, height, width, 0}, {width, height, 0, height}, {0, height, 0, 0}})
   local candidateLines = {}
   local pointOrientationLinesMap = {}
   local pointNeighbors = {}
   for pointIndex, point in pairs(points) do
      table.insert(pointOrientationLinesMap, {})
      local pointType = point[3][2]
      local orientations = pointOrientations[pointType][point[3][3]]
      for _, orientation in pairs(orientations) do
         pointOrientationLinesMap[pointIndex][orientation] = {}
      end
      table.insert(pointNeighbors, {})
   end

   local gap = 10

   local gapWeight = 1
   local wallEvidenceWeight = 10
   local shortLineWeight = 10
   --local pointWeight = 1000
   local pointMissingLineWeight = 100
   local closePointWeight = 1000
   local overlappingLineWeight = 1000
   local hugeWeight = 10000


   for pointIndex, point in pairs(points) do
      local pointType = point[3][2]
      local orientations = pointOrientations[pointType][point[3][3]]
      for _, orientation in pairs(orientations) do
         local oppositeOrientation = (orientation + 2 - 1) % 4 + 1
         local ranges = orientationRanges[orientation]:clone()
         local lineDim = 0
         if orientation == 1 or orientation == 3 then
            lineDim = 2
         else
            lineDim = 1
         end

         deltas = {0, 0}

         deltas[3 - lineDim] = gap


         for c = 1, 2 do
            ranges[c] = math.min(ranges[c], point[1][c] - deltas[c])
            ranges[c + 2] = math.max(ranges[c + 2], point[1][c] + deltas[c])
         end

         for neighborPointIndex, neighborPoint in pairs(points) do
            if neighborPointIndex > pointIndex then
               for __, neighborOrientation in pairs(pointOrientations[neighborPoint[3][2]][neighborPoint[3][3]]) do
                  if neighborOrientation == oppositeOrientation then
                     local inRange = true
                     for c = 1, 2 do
                        if neighborPoint[1][c] < ranges[c] or neighborPoint[1][c] > ranges[c + 2] then
                           inRange = false
                        end
                     end
                     if inRange and math.abs(neighborPoint[1][lineDim] - point[1][lineDim]) > math.max(math.abs(neighborPoint[1][3 - lineDim] - point[1][3 - lineDim]), gap) then
                        --print(pointIndex .. ' ' .. neighborPointIndex .. ' ' .. lineDim .. ' ' .. orientation)
                        --print(ranges[1] .. ' ' .. ranges[2] .. ' ' .. ranges[3] .. ' ' .. ranges[4])
                        --print(point[1][lineDim] .. ' ' .. neighborPoint[1][lineDim] .. ' ' .. point[1][3 - lineDim] .. ' ' .. neighborPoint[1][3 - lineDim])
                        local lineIndex = #candidateLines + 1
                        table.insert(pointOrientationLinesMap[pointIndex][orientation], lineIndex)
                        table.insert(pointOrientationLinesMap[neighborPointIndex][oppositeOrientation], lineIndex)
                        pointNeighbors[pointIndex][neighborPointIndex] = true
                        pointNeighbors[neighborPointIndex][pointIndex] = true

                        local cost = 0
                        cost = cost + math.abs(neighborPoint[1][3 - lineDim] - point[1][3 - lineDim]) / gap * gapWeight

                        --local fixedValue = torch.round((neighborPoint[1][3 - lineDim] + point[1][3 - lineDim]) / 2)
                        --local numNonWallPoints = 0
                        --for delta in xrange(int(abs(neighborPoint[lineDim] - point[lineDim]) + 1)):
                        --intermediatePoint = [0, 0]
                        --intermediatePoint[lineDim] = int(min(neighborPoint[lineDim], point[lineDim]) + delta)
                        --intermediatePoint[3 - lineDim] = fixedValue
                        --if wall_evidence[intermediatePoint[1]][intermediatePoint[0]] < 0.5:
                        --numNonWallPoints += 1
                        --cost += numNonWallPoints / abs(neighborPoint[lineDim] - point[lineDim]) * wallEvidenceWeight
                        table.insert(candidateLines, {pointIndex, neighborPointIndex, cost})
                     end
                  end
               end
            end
         end
      end
   end

   local conflictLinePairs = {}

   local D_p = torch.zeros(#points)
   for pointIndex = 1, #points do
      D_p[pointIndex] = #pointOrientationLinesMap[pointIndex]
   end
   D_p = torch.diag(D_p)
   local D_l = torch.zeros(#candidateLines)
   for lineIndex, line in pairs(candidateLines) do
      D_l[lineIndex] = line[3]
   end
   D_l = torch.diag(D_l)

   local PLs = torch.zeros(4, #points, #candidateLines)
   for pointIndex, orientationLinesMap in pairs(pointOrientationLinesMap) do
      for orientation, lines in pairs(orientationLinesMap) do
         for _, line in pairs(lines) do
            PLs[orientation][pointIndex][line] = 1
         end
      end
   end

   local PP = torch.zeros(#points, #points)
   for pointIndex, point in pairs(points) do
      for neighborPointIndex, neighborPoint in pairs(points) do
         if neighborPointIndex ~= pointIndex then
            local distance = math.pow(math.pow(point[1][1] - neighborPoint[1][1], 2) + math.pow(point[1][2] - neighborPoint[1][2], 2), 0.5)
            if distance < gap and not pointNeighbors[pointIndex][neighborPointIndex] then
               PP[pointIndex][neighborPointIndex] = 1
            end
         end
      end
   end

   --for conflictLinePair in conflictLinePairs:
   --model.addConstr(l[conflictLinePair[0]] + l[conflictLinePair[1]] <= 1)
   local PL2_sum = torch.zeros(#candidateLines, #candidateLines)
   local PL_sum = torch.zeros(#points, #candidateLines)
   for orientation = 1, 4 do
      --PLs[orientation]:fill(0)
      PL2_sum = PL2_sum + PLs[orientation]:transpose(1, 2) * PLs[orientation]
      PL_sum = PL_sum + PLs[orientation]
   end

   --[[
      for i = 1, #points do
      for j = 1, #points do
      if i ~= j then
      local same = true
      for k = 1, #candidateLines do
      if PL_sum[i][k] ~= PL_sum[j][k] then
      same = false
      break
      end
      end
      if same then
      print(i)
      print(j)
      os.exit(1)
      end
      end
      end
      end
   ]]--
   --print(PL2_sum:sum(1))
   --print(PL2_sum:sum(2))

   --print(torch.min(torch.diag(D_l)))
   local D_p_weight = 50
   local D_l_weight = 1
   local PL_weight = 100
   local PP_weight = 1000

   local L_coef = PL_weight * PL2_sum + D_l_weight * D_l
   --PL2_sum = PL2_sum + torch.randn(#PL2_sum) * 0.0001
   local L_coef_inv = torch.inverse(L_coef)
   local L_p = L_coef_inv * (PL_weight * PL_sum:transpose(1, 2))
   --local L_c = -0.5 * L_coef_inv * D_l

   local P_l = PL_weight * PL_sum
   local P_coef = 4 * PL_weight * torch.diag(torch.ones(#points)) + PP_weight * PP:transpose(1, 2) + D_p_weight * D_p - P_l * L_p
   local P_coef_inv = torch.inverse(P_coef)
   local P_x = P_coef_inv * D_p_weight * D_p
   --local P_c = P_coef_inv * (P_l * L_c)
   local p = P_x * torch.ones(#points)

   local function f(x, p)
      local l = L_p * p
      print(l)
      local f = D_p_weight * D_p * (x - p) * (x - p) + D_l_weight * D_l * l * l
      for orientation = 1, 4 do
         f = f + PL_weight * (p - PLs[orientation] * l) * (p - PLs[orientation] * l)
      end
      f = f + PP_weight * PP * p * p
      return f
   end

   print(torch.cat(torch.range(1, p:size(1)), p, 2))
   print(f(torch.ones(#points), p))
   print(f(torch.ones(#points), torch.ones(#points)))
   --print(f(torch.ones(#points), torch.zeros(#points)))
   os.exit(1)
end


function utils.attachDoorsOnWalls(width, height, representation, lineWidth, doorWidth, maxNumWalls)
   local lineWidth = lineWidth or 5
   local maxNumWalls = maxNumWalls or 100

   --utils.printRepresentation(representation)
   --os.exit(1)
   --print(representation.points)
   local walls, wallJunctionsMap = utils.pointsToLines(width, height, representation.points, lineWidth, true)
   local wallMask = utils.drawLineMask(width, height, walls, lineWidth, true)
   local doorWidth = doorWidth or lineWidth - 2
   local doorMask = utils.drawLineMask(width, height, representation.doors, doorWidth, true, 0)
   local indices = doorMask:nonzero()
   local wallDoorPointsMap = {}
   local doorCounters = {}
   if ##indices > 0 then
      for i = 1, indices:size(1) do
         local y = indices[i][1]
         local x = indices[i][2]
         local doorIndex = doorMask[y][x]
         local wallIndex = wallMask[y][x]
         if wallIndex > 0 then
            if not wallDoorPointsMap[wallIndex] then
               wallDoorPointsMap[wallIndex] = {}
            end
            if not wallDoorPointsMap[wallIndex][doorIndex] then
               wallDoorPointsMap[wallIndex][doorIndex] = {}
            end
            table.insert(wallDoorPointsMap[wallIndex][doorIndex], {x, y})
         end

         if not doorCounters[doorIndex] then
            doorCounters[doorIndex] = 0
         end
         doorCounters[doorIndex] = doorCounters[doorIndex] + 1
      end
   end

   local wallDoorTensor = torch.zeros(maxNumWalls, 3)
   for wallIndex, doorPoints in pairs(wallDoorPointsMap) do
      if wallIndex > maxNumWalls then
         break
      end

      local maxCount
      local maxCountDoor
      local lineDim = utils.lineDim(walls[wallIndex])
      for doorIndex, points in pairs(doorPoints) do
         local doorDim = utils.lineDim(representation.doors[doorIndex])
         if doorDim == lineDim then
            local count = #points
            if not maxCount or count > maxCount then
               maxCountDoor = doorIndex
               maxCount = count
            end
         end
      end
      if maxCountDoor and maxCount > doorCounters[maxCountDoor] * 0.2 then
         local points = doorPoints[maxCountDoor]

         if lineDim == 0 then
            if math.abs(line[1][1] - line[2][1]) > math.abs(line[1][2] - line[2][2]) then
               lineDim = 1
            else
               lineDim = 2
            end
         end
         local minDoor
         local maxDoor
         for _, point in pairs(points) do
            if not minDoor or point[lineDim] < minDoor then
               minDoor = point[lineDim]
            end
            if not maxDoor or point[lineDim] > maxDoor then
               maxDoor = point[lineDim]
            end
         end
         local wallIndices = wallMask:eq(wallIndex):nonzero()
         local minWall = torch.min(wallIndices, 1)[1][3 - lineDim]
         local maxWall = torch.max(wallIndices, 1)[1][3 - lineDim]
         local minRatio = math.max((minDoor - minWall) / (maxWall - minWall + 1), 0)
         local maxRatio = math.min((maxDoor - minWall) / (maxWall - minWall + 1), 1)
         wallDoorTensor[wallIndex][1] = minRatio
         wallDoorTensor[wallIndex][2] = maxRatio
         wallDoorTensor[wallIndex][3] = utils.getNumber('doors', representation.doors[maxCountDoor][3])
      end
   end
   local wallHeatmaps = torch.zeros(maxNumWalls, height, width)
   for wallIndex, _ in pairs(walls) do
      if wallIndex > maxNumWalls then
         break
      end
      wallHeatmaps[wallIndex] = wallMask:eq(wallIndex):double()
   end

   return wallHeatmaps, wallDoorTensor
end

function utils.drawMasks( img, masks, maxn, alpha, clrs )
   assert(img:isContiguous() and img:dim()==3)
   local n, h, w = masks:size(1), masks:size(2), masks:size(3)
   if not maxn then maxn=n end
   if not alpha then alpha=.4 end
   if not clrs then clrs=torch.rand(n,3)*.6+.4 end
   for i=1,math.min(maxn,n) do
      local M = masks[i]:contiguous():data()
      local B = torch.ByteTensor(h,w):zero():contiguous():data()
      -- get boundaries B in masks M quickly
      for y=0,h-2 do for x=0,w-2 do
            local k=y*w+x
            if M[k]~=M[k+1] then B[k],B[k+1]=1,1 end
            if M[k]~=M[k+w] then B[k],B[k+w]=1,1 end
            if M[k]~=M[k+1+w] then B[k],B[k+1+w]=1,1 end
      end end
      -- softly embed masks into image and add solid boundaries
      for j=1,3 do
         local O,c,a = img[j]:data(), clrs[i][j], alpha
         for k=0,w*h-1 do if M[k]==1 then O[k]=O[k]*(1-a)+c*a end end
            for k=0,w*h-1 do if B[k]==1 then O[k]=c end end
      end
   end
end


function utils.detectIcons(floorplan)
   local width, height = floorplan:size(3), floorplan:size(2)

   local inputSize = 160
   local bw = inputSize / 2

   if not utils.modelIcon then
      require 'nnx'
      local inn = require 'inn'
      if not nn.SpatialConstDiagonal then
         torch.class('nn.SpatialConstDiagonal', 'inn.ConstAffine')
      end
      --paths.dofile('/home/chenliu/Projects/Floorplan/floorplan/InverseCAD/models/DeepMask.lua')
      utils.modelIcon = torch.load('/home/chenliu/Projects/Floorplan/models/icon-deepmask/model_best.t7')
   end

   --------------------------------------------------------------------------------
   -- function: linear2convTrunk
   local function linear2convTrunk(net,fSz)
      return net:replace(function(x)
            if torch.typename(x):find('Linear') then
               local nInp,nOut = x.weight:size(2)/(fSz*fSz),x.weight:size(1)
               local w = torch.reshape(x.weight,nOut,nInp,fSz,fSz)
               local y = cudnn.SpatialConvolution(nInp,nOut,fSz,fSz,1,1)
               y.weight:copy(w); y.gradWeight:copy(w); y.bias:copy(x.bias)
               return y
            elseif torch.typename(x):find('Threshold') then
               return cudnn.ReLU()
            elseif torch.typename(x):find('View') or
            torch.typename(x):find('SpatialZeroPadding') then
               return nn.Identity()
            else
               return x
            end
                         end
      )
   end

   --------------------------------------------------------------------------------
   -- function: linear2convHeads
   local function linear2convHead(net)
      return net:replace(function(x)
            if torch.typename(x):find('Linear') then
               local nInp,nOut = x.weight:size(2),x.weight:size(1)
               local w = torch.reshape(x.weight,nOut,nInp,1,1)
               local y = cudnn.SpatialConvolution(nInp,nOut,1,1,1,1)
               y.weight:copy(w); y.gradWeight:copy(w); y.bias:copy(x.bias)
               return y
            elseif torch.typename(x):find('Threshold') then
               return cudnn.ReLU()
            elseif not torch.typename(x):find('View') and
            not torch.typename(x):find('Copy') then
               return x
            end
                         end
      )
   end

   utils.modelIcon:evaluate()
   local trunk = utils.modelIcon.modules[1]
   local maskBranch = utils.modelIcon.modules[2].modules[1]
   local scoreBranch = utils.modelIcon.modules[3]
   linear2convTrunk(trunk, inputSize / 16)
   linear2convHead(maskBranch)
   linear2convHead(scoreBranch)

   trunk:cuda()
   maskBranch:cuda()
   scoreBranch:cuda()

   local scales = {}
   for i = -1.5,0.5,1.5 do
      table.insert(scales, 2^i)
   end

   local numProposals = 100
   local meanstd = {mean = { 0.5, 0.5, 0.5 }, std = { 0.5, 0.5, 0.5 }}


   local inpPad = torch.CudaTensor()
   local input = floorplan
   if input:type() == 'torch.CudaTensor' then input = input:float() end

   local pyramid = nn.ConcatTable()
   for i = 1,#scales do
      pyramid:add(nn.SpatialReSamplingEx{rwidth=scales[i],
                                         rheight=scales[i], mode='bilinear'})
   end
   local inpPyramid = pyramid:forward(input)

   -- forward all scales through network
   local outPyramidMask,outPyramidScore = {},{}
   for i,_ in pairs(inpPyramid) do
      local inp = inpPyramid[i]:cuda()
      local h,w = inp:size(2),inp:size(3)

      -- padding/normalize
      inpPad:resize(1,3,h+2*bw,w+2*bw):fill(.5)
      inpPad:narrow(1,1,1):narrow(3,bw+1,h):narrow(4,bw+1,w):copy(inp)
      for i=1,3 do
         inpPad[1][i]:add(-meanstd.mean[i]):div(meanstd.std[i])
      end

      -- forward trunk
      local outTrunk = trunk:forward(inpPad):squeeze()
      -- forward score branch
      local outScore = scoreBranch:forward(outTrunk)
      table.insert(outPyramidScore,outScore:clone():squeeze())
      -- forward mask branch
      local outMask = maskBranch:forward(outTrunk)
      table.insert(outPyramidMask,outMask:float():squeeze())



      outScore = outScore:clone():squeeze()
      outMask = outMask:float():squeeze()

      --[[
         print(#inpPad)
         print(#outTrunk)
         print(#outMask)
         print(#outScore)
         print(#floorplan)
         print(scales[i])
         os.exit(1)
      ]]--

      if false then
         for y = 1, outMask:size(3) - 1 do
            for x = 1, outMask:size(2) - 1 do
               local maskDim = math.sqrt(outMask:size(1))
               local mask = outMask[{{}, x, y}]:contiguous():view(maskDim, maskDim)


               local thr = 0.2
               local s = scales[i]
               --local sz = math.floor(inputSize / s)
               local sz = inputSize
               local t = 16
               local delta = inputSize / 2

               mask = image.scale(mask,sz,sz,'bilinear')
               mask = mask:gt(thr)

               local imgMask = torch.zeros(h + bw * 2, w + bw * 2)
               imgMask:zero()
               print(#imgMask)
               print(math.floor((x - 1) * t) .. ' ' .. math.floor((y - 1) * t) .. ' ' .. sz)
               imgMask:narrow(1, math.floor((x - 1) * t + 1), sz):narrow(2, math.floor((y - 1) * t + 1), sz)[mask] = 1
               --imgMask:narrow(1, math.floor((x - 1) * t + 1), sz):narrow(2, math.floor((y - 1) * t + 1), sz)[1 - mask] = -1
               imgMask:narrow(1, math.floor((x - 1) * t + 1), 1):narrow(2, math.floor((y - 1) * t + 1), sz):fill(-1)
               imgMask:narrow(1, math.floor((x - 1) * t + 1) + sz - 1, 1):narrow(2, math.floor((y - 1) * t + 1), sz):fill(-1)
               imgMask:narrow(1, math.floor((x - 1) * t + 1), sz):narrow(2, math.floor((y - 1) * t + 1), 1):fill(-1)
               imgMask:narrow(1, math.floor((x - 1) * t + 1), sz):narrow(2, math.floor((y - 1) * t + 1) + sz - 1, 1):fill(-1)
               --imgMask = imgMask:narrow(1, bw + 1, h):narrow(2, bw + 1, w):byte()
               local img = torch.ones(3,h+2*bw,w+2*bw) * 0.5
               img:narrow(2,bw+1,h):narrow(3,bw+1,w):copy(inp)
               --print(#img)
               --print(#imgMask)
               img[1][imgMask:eq(1)] = 1
               img[2][imgMask:eq(1)] = 0
               img[3][imgMask:eq(1)] = 0
               img[1][imgMask:eq(-1)] = 0
               img[2][imgMask:eq(-1)] = 0
               img[3][imgMask:eq(-1)] = 1
               local score = outScore[x][y]
               image.save('test/masks/mask_' .. i .. '_' .. x .. '_' .. y .. '_' .. score .. '.png', img)
            end
         end
      end
   end


   local function unfoldMasksMatrix(masks)
      local umasks = {}
      local oSz = math.sqrt(masks[1]:size(1))
      for _,mask in pairs(masks) do
         local umask = mask:reshape(oSz,oSz,mask:size(2),mask:size(3))
         umask=umask:transpose(1,3):transpose(2,3):transpose(2,4):transpose(3,4)
         table.insert(umasks,umask)
      end
      return umasks
   end

   local masks = unfoldMasksMatrix(outPyramidMask)
   local scores = outPyramidScore

   local function getTopScores()
      local sortedScores = torch.Tensor()
      local sortedIds = torch.Tensor()
      local pos = torch.Tensor()

      local topScores = torch.Tensor()

      -- sort scores/ids for each scale
      local nScales=#scales
      local rowN = scores[nScales]:size(1) * scores[nScales]:size(2)
      sortedScores:resize(rowN,nScales):zero()
      sortedIds:resize(rowN,nScales):zero()
      for s = 1,nScales do
         scores[s]:mul(-1):exp():add(1):pow(-1) -- scores2prob

         local sc = scores[s]
         local h,w = sc:size(1),sc:size(2)

         local sc=sc:view(h*w)
         local sS,sIds=torch.sort(sc,true)
         local sz = sS:size(1)
         sortedScores:narrow(2,s,1):narrow(1,1,sz):copy(sS)
         sortedIds:narrow(2,s,1):narrow(1,1,sz):copy(sIds)
      end

      -- get top scores
      local np = numProposals
      pos:resize(nScales):fill(1)
      topScores:resize(np,4):fill(1)
      np=math.min(np,rowN)

      for i = 1,np do
         local scale,score = 0,0
         for k = 1,nScales do
            if sortedScores[pos[k]][k] > score then
               score = sortedScores[pos[k]][k]
               scale = k
            end
         end
         local temp=sortedIds[pos[scale]][scale]
         local x=math.floor(temp/scores[scale]:size(2))
         local y=temp%scores[scale]:size(2)+1
         x,y=math.max(1,x),math.max(1,y)

         pos[scale]=pos[scale]+1
         topScores:narrow(1,i,1):copy(torch.Tensor({score,scale,x,y}))
      end

      return topScores
   end

   local topScores = getTopScores()

   local function getTopMasks(thr, h, w)
      local imgMask = torch.ByteTensor()

      local topMasks = torch.ByteTensor()

      thr = math.log(thr/(1-thr)) -- 1/(1+e^-s) > th => s > log(1-th)

      local masks,topScores,np = masks, topScores, numProposals
      topMasks:resize(np,h,w):zero()
      --imgMask:resize(h,w)
      --local imgMaskPtr = imgMask:data()

      for i = 1,np do

         local scale,x,y=topScores[i][2], topScores[i][3], topScores[i][4]
         local s = scales[scale]
         local sz = math.floor(inputSize / s)
         local mask = masks[scale]
         x,y = math.min(x,mask:size(1)),math.min(y,mask:size(2))
         mask = mask[x][y]:float()
         local mask = image.scale(mask,sz,sz,'bilinear')


         mask = mask:gt(thr)
         local t = 16 / s
         local delta = inputSize / 2 / s
         imgMask:resize(h + delta * 2, w + delta * 2)
         imgMask:zero()
         --print(#imgMask)
         --print(math.floor((x - 1) * t) .. ' ' .. math.floor((y - 1) * t) .. ' ' .. sz)
         local sz1 = math.min(imgMask:size(1) - math.floor((x - 1) * t), sz)
         local sz2 = math.min(imgMask:size(2) - math.floor((y - 1) * t), sz)
         imgMask:narrow(1, math.floor((x - 1) * t + 1), sz1):narrow(2, math.floor((y - 1) * t + 1), sz2):copy(mask:narrow(1, 1, sz1):narrow(2, 1, sz2))
         imgMask = imgMask:narrow(1, delta + 1, h):narrow(2, delta + 1, w)
         --[[
            local mask_ptr = mask:data()
            local t = 16/s
            local delta = inputSize/2/s
            for im =0, sz-1 do
            local ii = math.floor((x-1)*t-delta+im)
            for jm = 0,sz- 1 do
            local jj=math.floor((y-1)*t-delta+jm)
            if  mask_ptr[sz*im + jm] > thr and
            ii >= 0 and ii <= h-1 and jj >= 0 and jj <= w-1 then
            imgMaskPtr[jj+ w*ii]=1
            end
            end
            end
         --]]
         topMasks:narrow(1,i,1):copy(imgMask)
      end

      return topMasks
   end
   local topMasks = getTopMasks(0.2, height, width)

   local IOUThreshold = 0.2
   while true do
      local hasChange = false
      local invalidMasks = {}
      for i = 1, topMasks:size(1) do
         for j = i + 1, topMasks:size(1) do
            local intersection = torch.cmul(topMasks[i], topMasks[j]):nonzero()
            if ##intersection > 0 then
               local union = (topMasks[i] + topMasks[j]):nonzero()
               if intersection:size(1) / union:size(1) > IOUThreshold then
                  invalidMasks[j] = true
                  hasChange = true
               end
            end
         end
      end
      if not hasChange then
         break
      end
      local newTopMasks
      for i = 1, topMasks:size(1) do
         if not invalidMasks[i] then
            if not newTopMasks then
               newTopMasks = topMasks[{{i}}]
            else
               newTopMasks = torch.cat(newTopMasks, topMasks[{{i}}], 1)
            end
         end
      end
      topMasks = newTopMasks
   end

   local res = floorplan:clone()
   utils.drawMasks(res, topMasks)
   image.save('test/icon_result.png', res)

   return
end

function utils.detectItems(floorplan, mode)
   local mode = mode or 'icons'
   --detectionImage = image.drawRect(detectionImage, x_1, y_1, x_2, y_2, {color = colorMap[number], lineWidth = lineWidth})
   local width, height = floorplan:size(3), floorplan:size(2)

   local patchDim = 16 * 7
   local nClasses = 13

   local modelName = 'model' .. mode
   if not utils[modelName] then
      require 'nnx'
      local inn = require 'inn'
      if not nn.SpatialConstDiagonal then
         torch.class('nn.SpatialConstDiagonal', 'inn.ConstAffine')
      end
      utils[modelName] = torch.load('/home/chenliu/Projects/Floorplan/models/deepmask-grid-' .. mode .. '/model_best.t7')
   end

   local model = utils[modelName]

   --utils.modelIcon:evaluate()
   local trunk = model.modules[1]
   local coordinatesBranch = model.modules[2]
   local labelBranch = model.modules[3]

   local scales = {}
   --for i = -1.5,0.5,1.5 do
   --table.insert(scales, 2^i)
   --end
   table.insert(scales, 1)

   local meanstd = {mean = { 0.5, 0.5, 0.5 }, std = { 0.5, 0.5, 0.5 }}

   local input = floorplan:clone()
   if input:type() == 'torch.CudaTensor' then input = input:float() end

   local pyramid = nn.ConcatTable()
   for i = 1,#scales do
      pyramid:add(nn.SpatialReSamplingEx{rwidth=scales[i],
                                         rheight=scales[i], mode='bilinear'})
   end
   local inpPyramid = pyramid:forward(input)

   local inpPad = torch.CudaTensor()
   -- forward all scales through network
   --local outPyramidMask,outPyramidScore = {},{}
   local boxes = {}
   local softmax = nn.SoftMax():cuda()


   for i,_ in pairs(inpPyramid) do
      local inp = inpPyramid[i]:cuda()
      local h,w = inp:size(2),inp:size(3)

      -- padding/normalize
      --inpPad:resize(1,3,h+2*bw,w+2*bw):fill(.5)
      --inpPad:narrow(1,1,1):narrow(3,bw+1,h):narrow(4,bw+1,w):copy(inp)
      --for i=1,3 do
      --inpPad[1][i]:add(-meanstd.mean[i]):div(meanstd.std[i])
      --end
      inpPad = inp:repeatTensor(1, 1, 1, 1)
      inpPad[1][i]:add(-meanstd.mean[i]):div(meanstd.std[i])

      -- forward trunk
      local outTrunk = trunk:forward(inpPad)
      -- forward score branch
      local outLabel = labelBranch:forward(outTrunk)
      --table.insert(outPyramidScore,outScore:clone():squeeze())
      -- forward mask branch
      local outCoordinates = coordinatesBranch:forward(outTrunk)
      --table.insert(outPyramidMask,outMask:float():squeeze())
      --outScore = outScore:clone():squeeze()
      --outMask = outMask:float():squeeze()
      outCoordinates = outCoordinates:squeeze()
      local gridHeight, gridWidth = outCoordinates:size(2), outCoordinates:size(3)
      outLabel = outLabel:view(gridHeight, gridWidth, -1):transpose(2, 3):transpose(1, 2)

      local cellWidth = w / gridWidth
      local cellHeight = h / gridHeight



      for gridX = 1, gridWidth do
         for gridY = 1, gridHeight do
            local labelProbs = outLabel[{{}, gridY, gridX}]
            labelProbs = softmax:forward(labelProbs)

            local prob, pred = torch.max(labelProbs, 1)
            if pred[1] <= nClasses then
               local box = torch.cat(outCoordinates[{{}, gridY, gridX}], labelProbs, 1):double()
               local x_1 = cellWidth * (gridX - 1 + 0.5) + (box[1] - 0.5) * patchDim - math.exp(box[3]) * patchDim / 2
               local y_1 = cellHeight * (gridY - 1 + 0.5) + (box[2] - 0.5) * patchDim - math.exp(box[4]) * patchDim / 2
               local x_2 = cellWidth * (gridX - 1 + 0.5) + (box[1] - 0.5) * patchDim + math.exp(box[3]) * patchDim / 2
               local y_2 = cellHeight * (gridY - 1 + 0.5) + (box[2] - 0.5) * patchDim + math.exp(box[4]) * patchDim / 2
               box[1] = x_1 / w * width
               box[2] = y_1 / h * height
               box[3] = x_2 / w * width
               box[4] = y_2 / h * height

               table.insert(boxes, box)
            end
         end
      end
   end
   --os.exit(1)

   local items = {}
   local numItemsPerClass = 100
   local confidenceThreshold = 0.3

   if true then
      local boxesTensor = torch.zeros(#boxes, 5)
      for boxIndex, box in pairs(boxes) do
         boxesTensor[boxIndex]:narrow(1, 1, 4):copy(box[{{1, 4}}])
         boxesTensor[boxIndex][5] = torch.max(box[{{5, -1}}])
      end

      local nms = require 'nms'
      require 'cunn'
      local threshold = 0
      local validIndices = nms.gpu_nms(boxesTensor:cuda(), threshold)
      --boxesTensor = boxesTensor:index(1, validIndices)
      local newBoxes = {}
      for i = 1, validIndices:size(1) do
         table.insert(newBoxes, boxes[validIndices[i]])
      end
      boxes = newBoxes
   end

   for number = 1, nClasses do
      table.sort(boxes, function(a, b) return a[4 + number] > b[4 + number] end)
      local boxesTensor = torch.zeros(#boxes, 5)
      for boxIndex, box in pairs(boxes) do
         boxesTensor[boxIndex] = torch.cat(box[{{1, 4}}], box[{{4 + number, 4 + number}}], 1)
      end

      if false then
         local nms = require 'nms'
         require 'cunn'
         local threshold = 0
         local validIndices = nms.gpu_nms(boxesTensor:cuda(), threshold)
         boxesTensor = boxesTensor:index(1, validIndices)
      end


      for i = 1, math.min(numItemsPerClass, boxesTensor:size(1)) do
         local box = boxesTensor[i]
         if box[5] < confidenceThreshold then
            break
         end

         local itemInfo = utils.getItemInfo(mode, number)
         --table.insert(itemInfo, box[5])
         local item = {{box[1], box[2]}, {box[3], box[4]}, itemInfo}
         table.insert(items, item)
      end
   end
   if true then
      local detectionImage = floorplan:clone()
      local colorMap = utils.getColorMap()
      local lineWidth = 2
      for _, item in pairs(items) do
         local x_1 = math.min(math.max(torch.round(item[1][1]), 1 + lineWidth), width - lineWidth)
         local y_1 = math.min(math.max(torch.round(item[1][2]), 1 + lineWidth), height - lineWidth)
         local x_2 = math.max(math.min(torch.round(item[2][1]), width - lineWidth), 1 + lineWidth)
         local y_2 = math.max(math.min(torch.round(item[2][2]), height - lineWidth), 1 + lineWidth)

         --if item[3][4] > 0.5 then
         detectionImage = image.drawRect(detectionImage, x_1, y_1, x_2, y_2, {lineWidth = lineWidth, color = colorMap[number]})
         --end
      end
      image.save('test/detection_result_' .. mode .. '.png', detectionImage)
      os.exit(1)
   end
   return items
end

function utils.evaluateResult(width, height, representationTarget, representationPrediction, opt)
   local lineWidth = opt.lineWidth or 5
   local maxDim = math.max(width, height)

   if (not representationTarget.points or #representationTarget.points == 0) and (representationTarget.walls and #representationTarget.walls > 0) then
      representationTarget.walls = utils.mergeLines(representationTarget.walls, lineWidth)
      representationTarget.points = utils.linesToPoints(width, height, representationTarget.walls, lineWidth)
   end
   if (not representationPrediction.points or #representationPrediction.points == 0) and (representationPrediction.walls and #representationPrediction.walls > 0) then
      representationPrediction.points = utils.linesToPoints(width, height, representationPrediction.walls, lineWidth)
   end

   --local longWalls = utils.pointsToLines(width, height, points, lineWidth)
   --representationPrediction.points = utils.linesToPoints(width, height, longWalls, lineWidth)

   local pointMap = {}
   local numCorrectPredictions = 0
   for pointIndexTarget, pointTarget in pairs(representationTarget.points) do
      local minDistance
      local minDistancePointIndexPrediction
      for pointIndexPrediction, pointPrediction in pairs(representationPrediction.points) do

         --[[
            local distance = utils.calcDistance(pointPrediction[1], pointTarget[1])
            if distance < opt.pointDistanceThreshold then
            print({'point', pointPrediction[1], pointPrediction[3], pointTarget[3]})
            end
         ]]--
         if utils.getNumber('points', pointPrediction[3]) == utils.getNumber('points', pointTarget[3]) then
            local distance = utils.calcDistance(pointPrediction[1], pointTarget[1])
            if not minDistance or distance < minDistance then
               minDistancePointIndexPrediction = pointIndexPrediction
               minDistance = distance
            end
         end
      end



      if minDistance and minDistance < opt.pointDistanceThreshold * maxDim then
         pointMap[pointIndexTarget] = minDistancePointIndexPrediction
         numCorrectPredictions = numCorrectPredictions + 1
      else
         print('missing wall junction')
         print(minDistance)
         print(pointTarget)
         --if minDistancePointIndexPrediction then
         --print(representationPrediction.points[minDistancePointIndexPrediction])
         --end
      end
   end

   local result = {}
   for _, mode in pairs({'Wall Junction', 'Door', 'Object', 'Room'}) do
      result[mode] = {}
      for _, value in pairs({'numCorrectPredictions', 'numTargets', 'numPredictions'}) do
         result[mode][value] = 0
      end
   end

   result["Wall Junction"].numCorrectPredictions = result["Wall Junction"].numCorrectPredictions + numCorrectPredictions
   result["Wall Junction"].numTargets = result["Wall Junction"].numTargets + #representationTarget.points
   result["Wall Junction"].numPredictions = result["Wall Junction"].numPredictions + #representationPrediction.points


   local doorMap = {}
   local numCorrectPredictions = 0
   local doorNumberGroupMap = {}
   doorNumberGroupMap[1] = 1
   doorNumberGroupMap[2] = 1
   doorNumberGroupMap[3] = 2
   doorNumberGroupMap[4] = 3
   doorNumberGroupMap[5] = 3
   doorNumberGroupMap[6] = 4
   doorNumberGroupMap[7] = 5
   doorNumberGroupMap[8] = 5
   doorNumberGroupMap[9] = 6
   doorNumberGroupMap[10] = 2
   doorNumberGroupMap[11] = 2

   for doorIndexTarget, doorTarget in pairs(representationTarget.doors) do
      local minDistance
      local minDistanceDoorIndexPrediction
      local numberTarget = doorNumberGroupMap[utils.getNumber('doors', doorTarget[3])]

      for doorIndexPrediction, doorPrediction in pairs(representationPrediction.doors) do
         local numberPrediction = doorPrediction[3][2]

         --[[
            local distance = math.min(math.max(utils.calcDistance(doorPrediction[1], doorTarget[1]), utils.calcDistance(doorPrediction[2], doorTarget[2])), math.max(utils.calcDistance(doorPrediction[1], doorTarget[2]), utils.calcDistance(doorPrediction[2], doorTarget[1])))
            if distance < opt.doorDistanceThreshold then
            print({'door', numberPrediction, numberTarget})
            end
         ]]--
         if numberPrediction == numberTarget or true then
            local distance = math.max(utils.calcDistance(doorPrediction[1], doorTarget[1]), utils.calcDistance(doorPrediction[2], doorTarget[2]))
            if not minDistance or distance < minDistance then
               minDistanceDoorIndexPrediction = doorIndexPrediction
               minDistance = distance
            end
         end
      end
      if minDistance and minDistance < opt.doorDistanceThreshold * maxDim then
         doorMap[doorIndexTarget] = minDistanceDoorIndexPrediction
         numCorrectPredictions = numCorrectPredictions + 1
      else
         print('missing door')
         print(doorTarget)
         print(minDistance)
         if minDistanceDoorIndexPrediction then
            print(representationPrediction.doors[minDistanceDoorIndexPrediction])
         end
      end
   end
   result["Door"].numCorrectPredictions = result["Door"].numCorrectPredictions + numCorrectPredictions
   result["Door"].numTargets = result["Door"].numTargets + #representationTarget.doors
   result["Door"].numPredictions = result["Door"].numPredictions + #representationPrediction.doors


   local iconMap = {}
   local numCorrectPredictions = 0
   for iconIndexTarget, iconTarget in pairs(representationTarget.icons) do
      local maxIOU
      local maxIOUIconIndexPrediction
      for iconIndexPrediction, iconPrediction in pairs(representationPrediction.icons) do
         if utils.getNumber('icons', iconPrediction[3]) == utils.getNumber('icons', iconTarget[3]) or (iconTarget[3][1] == 'special' and iconPrediction[3][1] == 'special') then
            local IOU = utils.calcIOU(iconPrediction, iconTarget)
            if not maxIOU or IOU > maxIOU then
               maxIOUIconIndexPrediction = iconIndexPrediction
               maxIOU = IOU
            end
         end
      end
      if maxIOU and maxIOU > opt.iconIOUThreshold then
         iconMap[iconIndexTarget] = maxIOUIconIndexPrediction
         numCorrectPredictions = numCorrectPredictions + 1
      else
         print('missing object')
         print(iconTarget)
         print(maxIOU)
      end
   end

   result["Object"].numCorrectPredictions = result["Object"].numCorrectPredictions + numCorrectPredictions
   result["Object"].numTargets = result["Object"].numTargets + #representationTarget.icons
   result["Object"].numPredictions = result["Object"].numPredictions + #representationPrediction.icons


   --[[
      local segmentationTarget = utils.getSegmentation(width, height, representationTarget)[1]
      local segmentationPrediction = utils.getSegmentation(width, height, representationPrediction)[1]
      local segmentMasksTarget = {}
      for segmentIndex = 1, 11 do
      local segmentMask = segmentationTarget:eq(segmentIndex):double()
      local segments, numSegments = utils.findConnectedComponents(segmentMask)
      for segment = 1, numSegments - 1 do
      local mask = segments:eq(segment)
      table.insert(segmentMasksTarget, {mask, segmentIndex})
      end
      end

      local segmentMasksPrediction = {}
      for segmentIndex = 1, 11 do
      local segmentMask = segmentationPrediction:eq(segmentIndex):double()
      local segments, numSegments = utils.findConnectedComponents(segmentMask)
      for segment = 1, numSegments - 1 do
      local mask = segments:eq(segment)
      table.insert(segmentMasksPrediction, {mask, segmentIndex})
      end
      end
   ]]--
   local segmentMasksTarget = utils.getRoomSegments(width, height, representationTarget)

   local segmentMasksPrediction = utils.getRoomSegments(width, height, representationPrediction)

   --[[
      for segmentIndexTarget, segmentTarget in pairs(segmentMasksPrediction) do
      print(segmentTarget[2])
      print(segmentTarget[1]:nonzero()[1])
      print(#segmentTarget[1]:nonzero())
      end
      print(segmentMasksPrediction.labels)
      os.exit(1)
   ]]--

   local segmentMap = {}
   local numCorrectPredictions = 0
   local roomTypeMap = {}
   for roomType = 1, 10 do
      roomTypeMap[roomType] = {}
      roomTypeMap[roomType][roomType] = true
   end
   roomTypeMap[1][2] = true
   roomTypeMap[2][1] = true
   roomTypeMap[2][3] = true
   roomTypeMap[3][2] = true
   roomTypeMap[4][5] = true
   roomTypeMap[5][4] = true
   roomTypeMap[7][10] = true
   roomTypeMap[8][1] = true
   roomTypeMap[8][2] = true
   roomTypeMap[9][4] = true
   roomTypeMap[9][5] = true
   roomTypeMap[10][4] = true
   roomTypeMap[10][5] = true
   roomTypeMap[10][7] = true
   roomTypeMap[10][8] = true
   roomTypeMap[10][9] = true


   --local IOU = utils.calcIOUMask(segmentMasksPrediction[4][1], segmentMasksTarget[4][1])
   --print(IOU)
   --os.exit(1)

   for segmentIndexTarget, segmentTarget in pairs(segmentMasksTarget) do
      local maxIOU
      local maxIOUSegmentIndexPrediction
      for segmentIndexPrediction, segmentPrediction in pairs(segmentMasksPrediction) do
         --if segmentPrediction[2] == segmentTarget[2] then
         if roomTypeMap[segmentTarget[2]][segmentPrediction[2]] then
            local IOU = utils.calcIOUMask(segmentPrediction[1], segmentTarget[1])
            if not maxIOU or IOU > maxIOU then
               maxIOUSegmentIndexPrediction = segmentIndexPrediction
               maxIOU = IOU
            end
         end
      end
      if maxIOU and maxIOU > opt.segmentIOUThreshold then
         segmentMap[segmentIndexTarget] = maxIOUSegmentIndexPrediction
         numCorrectPredictions = numCorrectPredictions + 1
      else
         print('missing segment')
         print(segmentTarget[2])
         print({segmentTarget[1]:nonzero()[1][2], segmentTarget[1]:nonzero()[1][1]})
         print(maxIOU)
      end
   end
   result["Room"].numCorrectPredictions = result["Room"].numCorrectPredictions + numCorrectPredictions
   result["Room"].numTargets = result["Room"].numTargets + #segmentMasksTarget
   local numSegmentPredictions = 0
   for segmentIndexPrediction, segmentPrediction in pairs(segmentMasksPrediction) do
      numSegmentPredictions = numSegmentPredictions + 1
   end
   result["Room"].numPredictions = result["Room"].numPredictions + numSegmentPredictions

   return result
end

function utils.evaluateDetection(floorplan, representation, mode)
   local mode = mode or 'icons'
   --detectionImage = image.drawRect(detectionImage, x_1, y_1, x_2, y_2, {color = colorMap[number], lineWidth = lineWidth})
   local width, height = floorplan:size(3), floorplan:size(2)

   local patchDim = 16 * 7
   local nClasses = 13

   if not utils.modelIcon then
      require 'nnx'
      local inn = require 'inn'
      if not nn.SpatialConstDiagonal then
         torch.class('nn.SpatialConstDiagonal', 'inn.ConstAffine')
      end
      --paths.dofile('/home/chenliu/Projects/Floorplan/floorplan/InverseCAD/models/SpatialSymmetricPadding.lua')
      utils.modelIcon = torch.load('/home/chenliu/Projects/Floorplan/models/deepmask-grid-' .. mode .. '/model_best.t7')
   end


   --utils.modelIcon:evaluate()
   local trunk = utils.modelIcon.modules[1]
   local coordinatesBranch = utils.modelIcon.modules[2]
   local labelBranch = utils.modelIcon.modules[3]


   local scales = {}
   --for i = -1.5,0.5,1.5 do
   --table.insert(scales, 2^i)
   --end
   table.insert(scales, 1)

   local meanstd = {mean = { 0.5, 0.5, 0.5 }, std = { 0.5, 0.5, 0.5 }}

   local input = floorplan
   if input:type() == 'torch.CudaTensor' then input = input:float() end

   local pyramid = nn.ConcatTable()
   for i = 1,#scales do
      pyramid:add(nn.SpatialReSamplingEx{rwidth=scales[i],
                                         rheight=scales[i], mode='bilinear'})
   end
   local inpPyramid = pyramid:forward(input)

   local inpPad = torch.CudaTensor()
   -- forward all scales through network
   --local outPyramidMask,outPyramidScore = {},{}
   local boxes = {}
   local softmax = nn.SoftMax():cuda()

   for i,_ in pairs(inpPyramid) do
      local inp = inpPyramid[i]:cuda()
      local h,w = inp:size(2),inp:size(3)

      -- padding/normalize
      --inpPad:resize(1,3,h+2*bw,w+2*bw):fill(.5)
      --inpPad:narrow(1,1,1):narrow(3,bw+1,h):narrow(4,bw+1,w):copy(inp)
      --for i=1,3 do
      --inpPad[1][i]:add(-meanstd.mean[i]):div(meanstd.std[i])
      --end
      inpPad = inp:repeatTensor(1, 1, 1, 1)
      inpPad[1][i]:add(-meanstd.mean[i]):div(meanstd.std[i])

      -- forward trunk
      local outTrunk = trunk:forward(inpPad)
      -- forward score branch
      local outLabel = labelBranch:forward(outTrunk)
      --table.insert(outPyramidScore,outScore:clone():squeeze())
      -- forward mask branch
      local outCoordinates = coordinatesBranch:forward(outTrunk)
      --table.insert(outPyramidMask,outMask:float():squeeze())
      --outScore = outScore:clone():squeeze()
      --outMask = outMask:float():squeeze()
      outCoordinates = outCoordinates:squeeze()
      local gridHeight, gridWidth = outCoordinates:size(2), outCoordinates:size(3)
      outLabel = outLabel:view(gridHeight, gridWidth, -1):transpose(2, 3):transpose(1, 2)

      local cellWidth = w / gridWidth
      local cellHeight = h / gridHeight



      for gridX = 1, gridWidth do
         for gridY = 1, gridHeight do
            local labelProbs = outLabel[{{}, gridY, gridX}]
            labelProbs = softmax:forward(labelProbs)
            local box = torch.cat(outCoordinates[{{}, gridY, gridX}], labelProbs, 1):double()
            local x_1 = cellWidth * (gridX - 1 + 0.5) + (box[1] - 0.5) * patchDim - math.exp(box[3]) * patchDim / 2
            local y_1 = cellHeight * (gridY - 1 + 0.5) + (box[2] - 0.5) * patchDim - math.exp(box[4]) * patchDim / 2
            local x_2 = cellWidth * (gridX - 1 + 0.5) + (box[1] - 0.5) * patchDim + math.exp(box[3]) * patchDim / 2
            local y_2 = cellHeight * (gridY - 1 + 0.5) + (box[2] - 0.5) * patchDim + math.exp(box[4]) * patchDim / 2
            box[1] = x_1 / w * width
            box[2] = y_1 / h * height
            box[3] = x_2 / w * width
            box[4] = y_2 / h * height

            table.insert(boxes, box)

            if false then
               print(gridX .. ' ' .. gridY)
               print(box)
               local sample = image.crop(floorplan, math.max(cellWidth * (gridX - 1 + 0.5) - patchDim / 2, 0), math.max(cellHeight * (gridY - 1 + 0.5) - patchDim / 2, 0), math.min(cellWidth * (gridX - 1 + 0.5) + patchDim / 2, width), math.min(cellHeight * (gridY - 1 + 0.5) + patchDim / 2, height))
               image.save('test/samples/sample_' .. gridX .. '_' .. gridY .. '.png', sample)
            end
         end
      end
   end
   --os.exit(1)

   local APs = {}
   for number = 1, nClasses do
      table.sort(boxes, function(a, b) return a[4 + number] > b[4 + number] end)
      local boxesTensor = torch.zeros(#boxes, 5)
      for boxIndex, box in pairs(boxes) do
         boxesTensor[boxIndex] = torch.cat(box[{{1, 4}}], box[{{4 + number, 4 + number}}], 1)
      end

      local nms = require 'nms'
      require 'cunn'
      local threshold = 0
      local validIndices = nms.gpu_nms(boxesTensor:cuda(), threshold)
      boxesTensor = boxesTensor:index(1, validIndices)
      local numberItems = {}
      for _, item in pairs(representation[mode]) do
         if utils.getNumber(mode, item[3]) == number then
            table.insert(numberItems, item)
         end
      end
      if #numberItems > 0 then
         local AP = utils.calcAP(boxesTensor, numberItems)
         APs[number] = AP
         print(number .. ' ' .. AP)
      end
   end

   local APSum = 0
   local count = 0
   for _, AP in pairs(APs) do
      APSum = APSum + AP
      count = count + 1
   end
   print(APSum / count)

   local detectionImage = floorplan:clone()
   local colorMap = utils.getColorMap()
   local lineWidth = 2
   local numProposals = 10
   for number = 1, nClasses do
      --table.sort(boxes, function(a, b) return torch.max(a[{{5, 4 + nClasses}}]) > torch.max(b[{{5, 4 + nClasses}}]) end)
      table.sort(boxes, function(a, b) return a[4 + number] > b[4 + number] end)
      local boxesTensor = torch.zeros(#boxes, 5)
      for boxIndex, box in pairs(boxes) do
         boxesTensor[boxIndex] = torch.cat(box[{{1, 4}}], box[{{4 + number, 4 + number}}], 1)
      end
      --print(boxesTensor[{{}, 5}])
      local nms = require 'nms'
      require 'cunn'
      --require 'cutorch'
      local threshold = 0
      local validIndices = nms.gpu_nms(boxesTensor:cuda(), threshold)
      boxesTensor = boxesTensor:index(1, validIndices)

      --print(boxesTensor[{{}, 5}])
      --os.exit(1)

      --print(colorMap[number][1])
      --print(colorMap[number][2])
      --print(colorMap[number][3])
      for i = 1, math.min(numProposals, boxesTensor:size(1)) do
         local box = boxesTensor[i]

         local x_1 = math.min(math.max(torch.round(box[1]), 1 + lineWidth), width - lineWidth)
         local y_1 = math.min(math.max(torch.round(box[2]), 1 + lineWidth), height - lineWidth)
         local x_2 = math.max(math.min(torch.round(box[3]), width - lineWidth), 1 + lineWidth)
         local y_2 = math.max(math.min(torch.round(box[4]), height - lineWidth), 1 + lineWidth)
         --local prob, pred = torch.max(box[{{5, -1}}], 1)
         if number == 1 then
            --print(box)
            --local prob = box[5]
            print(box[5] .. ' ' .. number)
         end

         if box[5] > 0.5 then
            detectionImage = image.drawRect(detectionImage, x_1, y_1, x_2, y_2, {lineWidth = lineWidth, color = colorMap[number]})
         end
      end
   end
   image.save('test/icon_result.png', detectionImage)
   os.exit(1)
end

function utils.calcIOU(box_1, box_2)
   local intersectionX = (math.min(box_1[2][1], box_2[2][1]) - math.max(box_1[1][1], box_2[1][1]))
   local intersectionY = (math.min(box_1[2][2], box_2[2][2]) - math.max(box_1[1][2], box_2[1][2]))
   if intersectionX <= 0 or intersectionY <= 0 then
      return 0
   end

   local intersection = intersectionX * intersectionY


   local union = (box_1[2][1] - box_1[1][1]) * (box_1[2][2] - box_1[1][2]) + (box_2[2][1] - box_2[1][1]) * (box_2[2][2] - box_2[1][2]) - intersection
   return intersection / union
end

function utils.calcIOUMask(mask_1, mask_2)
   local unionIndices = (mask_1 + mask_2):nonzero()
   if ##unionIndices > 0 then
      local intersectionIndices = torch.cmul(mask_1, mask_2):nonzero()
      if ##intersectionIndices > 0 then
         return intersectionIndices:size(1) / unionIndices:size(1)
      end
   end
   return 0
end

function utils.calcAP(boxesTensor, items, IOUThreshold)
   local IOUThreshold = IOUThreshold or 0.5
   local groundTruthMap = {}
   local maxBoxIndex = 0
   for itemIndex, item in pairs(items) do
      local boxIndex
      local prevIOU
      local prevScore
      for i = 1, boxesTensor:size(1) do
         local box = boxesTensor[i]
         local IOU = utils.calcIOU({{box[1], box[2]}, {box[3], box[4]}}, item)
         local score = box[5]
         if prevScore and score < prevScore then
            if not boxIndex and IOU > IOUThreshold then
               boxIndex = i
            end
            break
         else
            if IOU > IOUThreshold and (not prevIOU or IOU > prevIOU) then
               boxIndex = i
               prevIOU = IOU
               prevScore = score
            end
         end
      end
      if boxIndex then
         groundTruthMap[boxIndex] = itemIndex
         maxBoxIndex = math.max(maxBoxIndex, boxIndex)
      end
   end
   local precisions = {}
   local numPositiveBoxes = 0
   for boxIndex = 1, maxBoxIndex do
      if groundTruthMap[boxIndex] then
         numPositiveBoxes = numPositiveBoxes + 1
      end
      local recall = numPositiveBoxes / #items
      local recallLevel = math.floor(recall * 10) + 1
      local precision = numPositiveBoxes / boxIndex
      --print(recallLevel .. ' ' .. precision)

      if not precisions[recallLevel] then
         precisions[recallLevel] = precision
      else
         precisions[recallLevel] = math.max(precision, precisions[recallLevel])
      end
   end
   local AP = 0
   for recallLevel = 10, 1, -1 do
      if not precisions[recallLevel + 1] then
         break
      end
      if not precisions[recallLevel] or precisions[recallLevel] < precisions[recallLevel + 1] then
         precisions[recallLevel] = precisions[recallLevel + 1]
      end
   end

   for recallLevel = 1, 11 do
      --print(precisions[recallLevel])
      if precisions[recallLevel] then
         AP = AP + precisions[recallLevel]
      end
   end
   AP = AP / 11

   return AP
end

function utils.extractMaximum(heatmap, numPoints)
   local width, height = heatmap:size(2), heatmap:size(1)
   local lineWidth = lineWidth or 5
   local mask = heatmap:clone()
   local points = {}
   for pointIndex = 1, numPoints do
      local maxValues, ys = torch.max(mask, 1)
      local maxValue, x = torch.max(maxValues, 2)
      if maxValue[1][1] <= 0 then
         break
      end

      x = x[1][1]
      local y = ys[1][x]
      table.insert(points, {x, y})
      mask[{{math.max(y - lineWidth, 1), math.min(y + lineWidth, height)}, {math.max(x - lineWidth, 1), math.min(x + lineWidth, width)}}]:fill(0)
   end
   return points
end

function utils.extractLinePoints(mask_1, mask_2, lineDim, numPoints, lineWidth, lineMinLength, getHeatmaps)
   local width, height = mask_1:size(2), mask_1:size(1)
   local lineWidth = lineWidth or 5
   local lineMinLength = lineMinLength or 10

   local maxPoolingLine
   if lineDim == 1 then
      maxPoolingLine = nn.SpatialMaxPooling(1, lineWidth * 2 + 1, 1, 1, 0, lineWidth)
      --maxPoolingLine = nn.SpatialConvolution(1, 1, 1, lineWidth * 2 + 1, 1, 1, 0, lineWidth)
      --maxPoolingLine.weight = image.gaussian1D(lineWidth * 2 + 1):view(#maxPoolingLine.weight)
      --maxPoolingLine:noBias()
   else
      maxPoolingLine = nn.SpatialMaxPooling(lineWidth * 2 + 1, 1, 1, 1, lineWidth, 0)
      --maxPoolingLine = nn.SpatialConvolution(1, 1, lineWidth * 2 + 1, 1, 1, 1, lineWidth, 0)
      --maxPoolingLine.weight = image.gaussian1D(lineWidth * 2 + 1):view(#maxPoolingLine.weight)
      --maxPoolingLine:noBias()
   end

   local lineConfidences = maxPoolingLine:forward(torch.cat(mask_1:repeatTensor(1, 1, 1), mask_2:repeatTensor(1, 1, 1), 1))
   local lineConfidence_1 = lineConfidences[1]
   local lineConfidence_2 = lineConfidences[2]

   local heatmap_2 = torch.zeros(height, width)
   for i = lineMinLength + 1, mask_1:size(3 - lineDim) do
      if lineDim == 1 then
         heatmap_2[{{}, i}] = torch.cmax(heatmap_2[{{}, i - 1}], lineConfidence_1[{{}, i - lineMinLength}])
      else
         heatmap_2[i] = torch.cmax(heatmap_2[i - 1], lineConfidence_1[i - lineMinLength])
      end
   end
   local heatmap_1 = torch.zeros(height, width)
   for i = mask_1:size(3 - lineDim) - lineMinLength, 1, -1 do
      if lineDim == 1 then
         heatmap_1[{{}, i}] = torch.cmax(heatmap_1[{{}, i + 1}], lineConfidence_2[{{}, i + lineMinLength}])
      else
         heatmap_1[i] = torch.cmax(heatmap_1[i + 1], lineConfidence_2[i + lineMinLength])
      end
   end

   --local maxPoolingSquare = nn.SpatialMaxPooling(lineWidth * 2 + 1, lineWidth * 2 + 1, 1, 1, lineWidth, lineWidth)
   local maxPoolingSquare = nn.SpatialConvolution(1, 1, lineWidth * 2 + 1, lineWidth * 2 + 1, 1, 1, lineWidth, lineWidth)
   maxPoolingSquare.weight = image.gaussian(lineWidth * 2 + 1):view(#maxPoolingSquare.weight)
   maxPoolingSquare:noBias()

   --local pointConfidence_1 = maxPoolingSquare:forward(mask_1:repeatTensor(1, 1, 1))[1]:clone()
   --local pointConfidence_2 = maxPoolingSquare:forward(mask_2:repeatTensor(1, 1, 1))[1]:clone()
   local pointConfidence_1 = mask_1
   local pointConfidence_2 = mask_2
   --heatmap_1:add(pointConfidence_1)
   --heatmap_2:add(pointConfidence_2)

   --local heatmap_test = heatmap_1:clone()
   heatmap_1:cmul(pointConfidence_1)
   heatmap_2:cmul(pointConfidence_2)

   if getHeatmaps then
      return heatmap_1, heatmap_2
   end

   local points_1 = utils.extractMaximum(heatmap_1, numPoints)
   local points_2 = utils.extractMaximum(heatmap_2, numPoints)

   collectgarbage()
   if #points_1 > 0 and false then
      image.save('test/mask_1.png', mask_1)
      image.save('test/mask_2.png', mask_2)
      image.save('test/heatmap_test.png', heatmap_test)
      image.save('test/heatmap.png', heatmap_1)
      image.save('test/point_confidence.png', pointConfidence_1)
      image.save('test/line_confidence.png', lineConfidence_2)
      os.exit(1)
   end

   return points_1, points_2
end

function utils.extractRectanglePoints(mask_1, mask_2, mask_3, mask_4, numPoints, getHeatmap)
   local heatmap_1, heatmap_2 = utils.extractLinePoints(mask_1, mask_2, 1, nil, nil, nil, true)
   local heatmap_3, heatmap_4 = utils.extractLinePoints(mask_3, mask_4, 1, nil, nil, nil, true)
   heatmap_1, heatmap_3 = utils.extractLinePoints(heatmap_1, heatmap_3, 2, nil, 0, nil, true)
   heatmap_2, heatmap_4 = utils.extractLinePoints(heatmap_2, heatmap_4, 2, nil, 0, nil, true)

   if getHeatmap then
      return heatmap_1, heatmap_2, heatmap_3, heatmap_4
   end

   local points_1 = utils.extractMaximum(heatmap_1, numPoints)
   local points_2 = utils.extractMaximum(heatmap_2, numPoints)
   local points_3 = utils.extractMaximum(heatmap_3, numPoints)
   local points_4 = utils.extractMaximum(heatmap_4, numPoints)

   if #points_1 > 0 and false then
      image.save('test/mask_1.png', mask_1)
      image.save('test/mask_2.png', mask_2)
      image.save('test/mask_3.png', mask_3)
      image.save('test/mask_4.png', mask_4)
      local heatmap_test_1, heatmap_test_2 = utils.extractLinePoints(mask_1, mask_2, 1, nil, nil, nil, true)
      local heatmap_test_3, heatmap_test_4 = utils.extractLinePoints(mask_3, mask_4, 1, nil, nil, nil, true)
      image.save('test/heatmap_test_1.png', heatmap_test_1)
      image.save('test/heatmap_test_2.png', heatmap_test_2)
      image.save('test/heatmap_test_3.png', heatmap_test_3)
      image.save('test/heatmap_test_4.png', heatmap_test_4)
      image.save('test/heatmap_1.png', heatmap_1)
      image.save('test/heatmap_2.png', heatmap_2)
      image.save('test/heatmap_3.png', heatmap_3)
      image.save('test/heatmap_4.png', heatmap_4)
      print(#points_1 .. ' ' .. #points_2 .. ' ' .. #points_3 .. ' ' .. #points_4)
   end

   return points_1, points_2, points_3, points_4
end

function utils.extractWallPoints(masks, numPoints, lineWidth, lineMinLength, getHeatmaps)
   local width, height = masks[1]:size(2), masks[1]:size(1)
   local lineWidth = lineWidth or 5
   local lineMinLength = lineMinLength or 10

   local maxPoolingLine_1 = nn.SpatialMaxPooling(1, lineWidth * 2 + 1, 1, 1, 0, lineWidth)
   local maxPoolingLine_2 = nn.SpatialMaxPooling(lineWidth * 2 + 1, 1, 1, 1, lineWidth, 0)

   local lineConfidences = torch.zeros(4, height, width)
   for i = 1, 4 do
      lineConfidences[i]:cmax(masks[i])
   end
   for i = 1, 4 do
      lineConfidences[i % 4 + 1]:cmax(masks[4 + i])
      lineConfidences[(i + 1) % 4 + 1]:cmax(masks[4 + i])
   end
   for i = 1, 4 do
      lineConfidences[i]:cmax(masks[8 + i])
      lineConfidences[i % 4 + 1]:cmax(masks[8 + i])
      lineConfidences[(i + 2) % 4 + 1]:cmax(masks[8 + i])
   end
   for i = 1, 4 do
      lineConfidences[i]:cmax(masks[13])
   end

   local output_1 = maxPoolingLine_1:forward(torch.cat(lineConfidences[2]:repeatTensor(1, 1, 1), lineConfidences[4]:repeatTensor(1, 1, 1), 1))
   local output_2 = maxPoolingLine_2:forward(torch.cat(lineConfidences[1]:repeatTensor(1, 1, 1), lineConfidences[3]:repeatTensor(1, 1, 1), 1))

   lineConfidences[2] = output_1[1]
   lineConfidences[4] = output_1[2]
   lineConfidences[1] = output_2[1]
   lineConfidences[3] = output_2[2]

   local lineHeatmaps = torch.zeros(4, height, width)

   for i = lineMinLength + 1, width do
      lineHeatmaps[4][{{}, i}] = torch.cmax(lineHeatmaps[4][{{}, i - 1}], lineConfidences[4][{{}, i - lineMinLength}])
   end
   for i = lineMinLength + 1, height do
      lineHeatmaps[1][i] = torch.cmax(lineHeatmaps[1][i - 1], lineConfidences[1][i - lineMinLength])
   end

   for i = width - lineMinLength, 1, -1 do
      lineHeatmaps[2][{{}, i}] = torch.cmax(lineHeatmaps[2][{{}, i + 1}], lineConfidences[2][{{}, i + lineMinLength}])
   end
   for i = height - lineMinLength, 1, -1 do
      lineHeatmaps[3][i] = torch.cmax(lineHeatmaps[3][i + 1], lineConfidences[3][i + lineMinLength])
   end

   --[[
      for i = 1, 4 do
      image.save('test/line_' .. i .. '.png', lineHeatmaps[i])
      end
      os.exit(1)
   ]]--

   --local maxPoolingSquare = nn.SpatialMaxPooling(lineWidth * 2 + 1, lineWidth * 2 + 1, 1, 1, lineWidth, lineWidth)
   --local maxPoolingSquare = nn.SpatialConvolution(1, 1, lineWidth * 2 + 1, lineWidth * 2 + 1, 1, 1, lineWidth, lineWidth)
   --maxPoolingSquare.weight = image.gaussian(lineWidth * 2 + 1):view(#maxPoolingSquare.weight)
   --maxPoolingSquare:noBias()

   --local pointConfidence_1 = maxPoolingSquare:forward(mask_1:repeatTensor(1, 1, 1))[1]:clone()
   --local pointConfidence_2 = maxPoolingSquare:forward(mask_2:repeatTensor(1, 1, 1))[1]:clone()
   local heatmaps = masks
   for i = 1, 4 do
      heatmaps[i]:cmul(lineHeatmaps[(i + 1) % 4 + 1])
   end
   for i = 1, 4 do
      heatmaps[i]:cmul(lineHeatmaps[i])
      heatmaps[i]:cmul(lineHeatmaps[(i + 2) % 4 + 1])
   end
   for i = 1, 4 do
      heatmaps[i]:cmul(lineHeatmaps[i % 4 + 1])
      heatmaps[i]:cmul(lineHeatmaps[(i + 1) % 4 + 1])
      heatmaps[i]:cmul(lineHeatmaps[(i + 2) % 4 + 1])
   end
   for i = 1, 4 do
      heatmaps[13]:cmul(lineHeatmaps[i])
   end


   if getHeatmaps then
      return heatmaps
   end

   local points = {}
   for i = 1, 13 do
      table.insert(points, utils.extractMaximum(heatmaps[i], numPoints))
   end

   return points
end

function utils.estimateHeatmaps(modelHeatmap, floorplan, scaleType)

   local scaleType = scaleType or 'single'
   local width, height = floorplan:size(3), floorplan:size(2)
   local sampleDim = 256


   package.path = 'datasets/?.lua;' .. package.path
   package.path = '?.lua;' .. package.path
   local dataset = require('floorplan-representation')
   dataset.split = 'val'

   local output
   if scaleType == 'single' then
      --local input = dataset:preprocessResize(sampleDim, sampleDim)(floorplan):repeatTensor(1, 1, 1, 1):cuda()
      --output = modelHeatmap:forward(input)[1]:double()


      local floorplanScaled = dataset:preprocessScale(sampleDim)(floorplan)
      --image.save('test/scale.png', floorplanScaled:double())
      local offsetX, offsetY
      if floorplanScaled:size(2) < sampleDim then
	 offsetY = math.floor((sampleDim - floorplanScaled:size(2)) / 2)
	 offsetX = 0
      else
	 offsetX = math.floor((sampleDim - floorplanScaled:size(3)) / 2)
	 offsetY = 0
      end
      local temp = torch.zeros(3, sampleDim, sampleDim)
      temp:narrow(2, offsetY + 1, floorplanScaled:size(2)):narrow(3, offsetX + 1, floorplanScaled:size(3)):copy(floorplanScaled)
      local input = temp:repeatTensor(1, 1, 1, 1):cuda()

      output = modelHeatmap:forward(input)[1]:double()
      output = image.crop(output, offsetX, offsetY, offsetX + floorplanScaled:size(3), offsetY + floorplanScaled:size(2))

      --[[
	 image.save('test/heatmaps/floorplan.png', dataset:postprocess()(input[1]))
	 for i = 1, 13 do
	 image.save('test/heatmaps/junction_heatmap_' .. i .. '.png', output[i])
	 end
	 os.exit(1)
      ]]--
   elseif scaleType == 'full' then
      local floorplanNormalized = dataset:preprocessNormalization()(floorplan)
   else
      local floorplanNormalized = dataset:preprocessNormalization()(floorplan)

      local inputParamMap = {}
      local scale = 0
      local inputs
      while math.max(floorplanNormalized:size(3), floorplanNormalized:size(2)) > sampleDim / 2 or not inputs do
	 for offsetX = 0, floorplanNormalized:size(3) - 1, sampleDim do
	    for offsetY = 0, floorplanNormalized:size(2) - 1, sampleDim do
	       local input = torch.zeros(3, sampleDim, sampleDim)
	       local inputWidth = math.min(sampleDim, floorplanNormalized:size(3) - offsetX)
	       local inputHeight = math.min(sampleDim, floorplanNormalized:size(2) - offsetY)

	       input:narrow(2, 1, inputHeight):narrow(3, 1, inputWidth):copy(image.crop(floorplanNormalized, offsetX, offsetY, offsetX + inputWidth, offsetY + inputHeight))

	       input = input:repeatTensor(1, 1, 1, 1)


	       if not inputs then
		  inputs = input
	       else
		  inputs = torch.cat(inputs, input, 1)
	       end
	       inputParamMap[inputs:size(1)] = {scale, offsetX, offsetY}
	    end
	 end
	 scale = scale + 1
	 floorplanNormalized = image.scale(floorplanNormalized, floorplanNormalized:size(3) / 2, floorplanNormalized:size(2) / 2)
      end

      inputs = inputs:cuda()

      local outputs = torch.zeros(inputs:size(1), 51, sampleDim, sampleDim)
      for batchOffset = 0, inputs:size(1) - 1, 4 do
	 local numInputs = math.min(inputs:size(1) - batchOffset, 4)
	 outputs[{{batchOffset + 1, batchOffset + numInputs}}]:copy(modelHeatmap:forward(inputs[{{batchOffset + 1, batchOffset + numInputs}}]):double())
      end


      local scaleWeights = {}
      for i = 0, 10 do
	 scaleWeights[i] = 1
      end

      local prediction = torch.zeros(51, height, width)
      for i = 1, inputs:size(1) do
	 local inputParam = inputParamMap[i]
	 local scaleFactor = 2^inputParam[1]
	 local output = image.scale(outputs[i], outputs[i]:size(3) * scaleFactor, outputs[i]:size(2) * scaleFactor)


	 local offsetX = inputParam[2] * scaleFactor
	 local offsetY = inputParam[3] * scaleFactor
	 local outputWidth = math.min(width - offsetX, output:size(3))
	 local outputHeight = math.min(height - offsetY, output:size(2))
	 prediction:narrow(2, offsetY + 1, outputHeight):narrow(3, offsetX + 1, outputWidth):add(output:narrow(2, 1, outputHeight):narrow(3, 1, outputWidth) * scaleWeights[inputParam[1]])

	 image.save('test/output_' .. i .. '.png', prediction:narrow(1, 1, 13):sum(1)[1])
      end
      local scaleSum = 0

      for i = 0, scale - 1 do
	 scaleSum = scaleSum + scaleWeights[i]
      end

      prediction:div(scaleSum)
      output = prediction
   end


   if true then
      output = image.scale(output:double(), width, height, 'bicubic')
      local doorOffset = 13
      local doorHeatmaps = torch.cat(torch.cat(torch.cat(output:narrow(1, doorOffset + 3, 1), output:narrow(1, doorOffset + 2, 1), 1), output:narrow(1, doorOffset + 4, 1), 1), output:narrow(1, doorOffset + 1, 1), 1)
      local iconOffset = 17
      local iconHeatmaps = torch.cat(torch.cat(torch.cat(output:narrow(1, iconOffset + 4, 1), output:narrow(1, iconOffset + 3, 1), 1), output:narrow(1, iconOffset + 1, 1), 1), output:narrow(1, iconOffset + 2, 1), 1)
      return output:narrow(1, 1, 13):double(), doorHeatmaps, iconHeatmaps, output:narrow(1, 22, 30):double()
   end

   --local junctionHeatmaps = torch.zeros(nClasses, height, width)
   --local junctionHeatmaps = output:narrow(1, 1, 13):double()
   local confidenceMasks = output:narrow(1, 1, 13):double()
   local junctionHeatmaps = fp_ut.extractWallPoints(confidenceMasks, nil, nil, nil, true)

   --[[
      for i = 1, 13 do
      image.save('test/mask_' .. i .. '.png', confidenceMasks[i])
      end
      for i = 1, 13 do
      image.save('test/heatmap_' .. i .. '.png', junctionHeatmaps[i])
      end
   ]]--

   local confidenceMasks = output:narrow(1, 13 + 1, 4):double()
   local heatmap_1, heatmap_2 = fp_ut.extractLinePoints(confidenceMasks[1], confidenceMasks[2], 1, nil, nil, nil, true)
   local heatmap_3, heatmap_4 = fp_ut.extractLinePoints(confidenceMasks[3], confidenceMasks[4], 2, nil, nil, nil, true)
   local doorHeatmaps = torch.cat(torch.cat(torch.cat(heatmap_3:repeatTensor(1, 1, 1), heatmap_2:repeatTensor(1, 1, 1), 1), heatmap_4:repeatTensor(1, 1, 1), 1), heatmap_1:repeatTensor(1, 1, 1), 1)


   local confidenceMasks = output:narrow(1, 13 + 4 + 1, 4):double()
   --[[
      image.save('test/mask_1.png', confidenceMasks[4 * (number - 1) + 1])
      image.save('test/mask_2.png', confidenceMasks[4 * (number - 1) + 2])
      image.save('test/mask_3.png', confidenceMasks[4 * (number - 1) + 3])
      image.save('test/mask_4.png', confidenceMasks[4 * (number - 1) + 4])
   ]]--
   local heatmap_1, heatmap_2, heatmap_3, heatmap_4 = fp_ut.extractRectanglePoints(confidenceMasks[1], confidenceMasks[2], confidenceMasks[3], confidenceMasks[4], numPoints, true)
   local iconHeatmaps = torch.cat(torch.cat(torch.cat(heatmap_4:repeatTensor(1, 1, 1), heatmap_3:repeatTensor(1, 1, 1), 1), heatmap_1:repeatTensor(1, 1, 1), 1), heatmap_2:repeatTensor(1, 1, 1), 1)

   local segmentations = output:narrow(1, 22, 30):double()


   junctionHeatmaps = image.scale(junctionHeatmaps, width, height)
   doorHeatmaps = image.scale(doorHeatmaps, width, height)
   iconHeatmaps = image.scale(iconHeatmaps, width, height)

   segmentations = image.scale(segmentations, width, height)
   return junctionHeatmaps, doorHeatmaps, iconHeatmaps, segmentations
end

function utils.proceduralGeneration(floorplan)
   local width, height = floorplan:size(3), floorplan:size(2)

   local floorplanByte = (floorplan:transpose(1, 2):transpose(2, 3) * 255):byte()
   local floorplanGray = cv.cvtColor({floorplanByte, nil, cv.COLOR_BGR2GRAY})
   local edges = cv.Canny({floorplanByte, 100, 200})
   image.save('test/edges.png', edges:double() / 255)
   local lines = cv.HoughLinesP({edges, 1, cv.CV_PI / 180, 100})
   local lineImage = floorplanByte:clone()
   local lineMask = torch.ByteTensor(#floorplanGray):zero()
   lineImage:zero()
   for i = 1, lines:size(1) do
      local line = lines[i][1]
      cv.line({lineImage, {line[1], line[2]}, {line[3], line[4]}, {255, 255, 255}})
      cv.line({lineMask, {line[1], line[2]}, {line[3], line[4]}, {255}})
   end
   image.save('test/Hough.png', lineImage:transpose(2, 3):transpose(1, 2):double() / 255)
   local lineMask = lineMask:gt(128)
   local lineSegments, numLineSegments = utils.findConnectedComponents(lineMask)
   image.save('test/line_mask.png', utils.drawSegmentation(lineSegments))
   lineSegments[1]:fill(numLineSegments)
   lineSegments[lineSegments:size(1)]:fill(numLineSegments)
   lineSegments:narrow(2, 1, 1):fill(numLineSegments)
   lineSegments:narrow(2, lineSegments:size(2), 1):fill(numLineSegments)

   cv.watershed({floorplanByte, lineSegments})

   local corners = cv.cornerHarris({lineSegments:byte(), nil, 5, 3, 0.04})

   local segmentationImage = utils.drawSegmentation(lineSegments)

   --corners = cv.dilate(corners)
   --corners = image.dilate(corners:double())
   local cornerMask = corners:gt(corners:max() * 0.01)

   local smallSegmentMask = torch.zeros(height, width)
   local smallSegmentAreaThreshold = width * height * 0.002
   local smallSegmentWidthThreshold = 3
   for segmentIndex = 1, numLineSegments - 1 do
      local segmentMask = lineSegments:eq(segmentIndex)
      local indices = segmentMask:nonzero()
      if ##indices > 0 then
         local mins = torch.min(indices, 1)[1]
         local maxs = torch.max(indices, 1)[1]
         if (#indices)[1] < smallSegmentAreaThreshold or maxs[1] - mins[1] < smallSegmentWidthThreshold and maxs[2] - mins[2] < smallSegmentWidthThreshold then
            smallSegmentMask[segmentMask] = 1
         end
      end
   end
   smallSegmentMask = image.dilate(smallSegmentMask)
   --cornerMask[smallSegmentMask:byte()] = 0
   --cornerMask[lineSegments:le(0)] = 0

   segmentationImage[1][cornerMask] = 1
   segmentationImage[2][cornerMask] = 0
   segmentationImage[3][cornerMask] = 0

   image.save('test/segmentation.png', segmentationImage)


   print(lines:size(1))
   os.exit(1)
   return
end

function utils.writePopupData(width, height, representation, filename)
   local floorplanSegmentation, shortWalls = utils.getSegmentation(width, height, representation)
   floorplanSegmentation = floorplanSegmentation[1]

   local representationFile = io.open(filename .. '.txt', 'w')
   representationFile:write(width .. '\t' .. height .. '\n')
   representationFile:write(#shortWalls .. '\n')
   for _, wall in pairs(shortWalls) do
      for pointIndex = 1, 2 do
         for c = 1, 2 do
            representationFile:write(torch.round(wall[pointIndex][c]) .. '\t')
         end
      end
      local lineDim = utils.lineDim(wall)
      local center = {(wall[1][1] + wall[2][1]) / 2, (wall[1][2] + wall[2][2]) / 2}
      center[1] = math.max(math.min(center[1], width), 1)
      center[2] = math.max(math.min(center[2], height), 1)

      local label_1, label_2
      if lineDim == 1 then
         for delta = 1, height do
            if center[2] - delta < 1 then
               break
            end
            if floorplanSegmentation[center[2] - delta][center[1]] <= 11 then
               label_1 = floorplanSegmentation[center[2] - delta][center[1]]
               break
            end
         end
         if not label_1 then
            label_1 = 11
         end

         for delta = 1, height do
            if center[2] + delta > height then
               break
            end
            if floorplanSegmentation[center[2] + delta][center[1]] <= 11 then
               label_2 = floorplanSegmentation[center[2] + delta][center[1]]
               break
            end
         end
         if not label_2 then
            label_2 = 11
         end
      else
         for delta = 1, width do
            if center[1] + delta > width then
               break
            end
            if floorplanSegmentation[center[2]][center[1] + delta] <= 11 then
               label_1 = floorplanSegmentation[center[2]][center[1] + delta]
               break
            end
         end
         if not label_1 then
            label_1 = 11
         end

         for delta = 1, height do
            if center[1] - delta < 1 then
               break
            end
            if floorplanSegmentation[center[2]][center[1] - delta] <= 11 then
               label_2 = floorplanSegmentation[center[2]][center[1] - delta]
               break
            end
         end
         if not label_2 then
            label_2 = 11
         end
      end
      representationFile:write(label_1 .. '\t' .. label_2 .. '\n')
   end

   for itemMode, items in pairs(representation) do
      if itemMode == 'doors' or itemMode == 'icons' then
         for _, item in pairs(items) do
            for __, field in pairs(item) do
               if __ <= 3 then
                  for ___, value in pairs(field) do
                     if __ <= 2 then
                        value = torch.round(value)
                     end
                     representationFile:write(value .. '\t')
                  end
               end
            end
            representationFile:write('\n')
         end
      end
   end

   representationFile:close()
   --if floorplan then
   --image.save(filename .. '.png', floorplan)
   --end
end

return utils
