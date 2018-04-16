#!/usr/bin/env torch
------------------------------------------------------------
-- a simple filter bank
--
-- Clement Farabet
--

require 'xlua'
require 'qt'
require 'qtwidget'
require 'qtuiloader'
require 'qttorch'
require 'image'
local fp_ut = require 'floorplan_utils'

--require 'csvigo'
--require 'utils'
--rep_ut = require('../util/lua/representation_utils')
--util = paths.dofile('../util/util.lua')
--package.path = '../util/lua/?.lua;' .. package.path
--require 'ginit' (opt)
--local pl = require 'pl.import_into' ()
--local ffi = require 'ffi'

-- parse args
--op = xlua.OptionParser('%prog [options]')
--opt,args = op:parse()
local fp_ut = require 'floorplan_utils'

local maxImgs = 2000

-- setup GUI (external UI file)
widget = qtuiloader.load('g.ui')
painterFloorplan = qt.QtLuaPainter(widget.frameFloorplan)
painterAnnotation = qt.QtLuaPainter(widget.frameAnnotation)
painterIcon = qt.QtLuaPainter(widget.frameIcon)
painterMask = qt.QtLuaPainter(widget.frameMask)

-- thread
torch.setnumthreads(4)

-- filters
--filters = nn.SpatialConvolutionMap(nn.tables.random(3,16,1),5,5)

-- profiler
p = xlua.Profiler()

local filenames = {}
local filenamesRepresentation = {}
local index = 1
local windowSize = 700
local smallImageSize = 700
prevX = -1
prevY = -1
width = -1
height = -1
local scaleFactor = 1
gridWidth = 8
gridHeight = 16
mode = 'walls'
iconTypeCurrent = 'wall'
iconStyleCurrent = 1
iconOrientationCurrent = 1
local refresh = false
local preview = false
local original = false
local sanity = false
local lineWidth = 4


function emptyRepresentation()
   local representation = {}
   representation.walls = {}
   representation.doors = {}
   representation.icons = {}
   representation.labels = {}
   return representation
end
local representation = emptyRepresentation()

local roomTypeMap = fp_ut.getNameMap()['labels']

local keyMap = fp_ut.keyMap()
keyMap['r'] = {'remove', 'remove'}


function loadFilenames()
   maxImgs = 1
   for i = 1, maxImgs do
      --filenameFloorplan: path to floorplan image
      --filenameFloorplan: path to annotation txt file
      print('please change loadFilenames() function to load images')

      filenameFloorplan = '../data/floorplan_1.png'
      filenameRepresentation = '../data/floorplan_1.txt'
      table.insert(filenames, filenameFloorplan)
      table.insert(filenamesRepresentation, filenameRepresentation)
      break

   end
end

function loadImage()
   floorplan = image.load(filenames[index], 3)
   annotation = torch.ones(#floorplan)

   representation = fp_ut.loadRepresentation(filenamesRepresentation[index])

   scaleFactor = 1
   if representation == nil then
      representation = emptyRepresentation()
   end

   if math.max(floorplan:size(2), floorplan:size(3)) < smallImageSize or math.max(floorplan:size(2), floorplan:size(3)) > windowSize then
      scaleFactor = windowSize / math.max(floorplan:size(2), floorplan:size(3))
      floorplan = image.scale(floorplan, windowSize)
      representation = fp_ut.scaleRepresentationByRatio(representation, scaleFactor)
   end

   width = floorplan:size(3)
   height = floorplan:size(2)

   original = false
   candidateRegions = nil
   floorplanSegmentation = nil

   display()
   draw()
   --widget.windowTitle = 'Floorplan ' .. filenames[index]
   widget.windowTitle = 'Floorplan ' .. index
end

function moveToNextImage()
   index = index + 1
   assert(index <= #filenames, "no next image")
end

function moveToPreviousImage()
   index = index - 1
   assert(index > 0, "no previous image")
end

function moveToNextUnannotatedImage()
   index = index + 1

   while fp_ut.loadRepresentation(filenamesRepresentation[index]) ~= nil or fp_ut.loadRepresentation(filenamesRepresentation[index + 1]) ~= nil do
      index = index + 1
   end
   assert(index <= #filenames, "no next image")
end

function checkSanities()
   --startIndex = startIndex or 894
   --endIndex = endIndex or index
   startIndex = startIndex or 800
   endIndex = 1000
   for indexForCheck = startIndex, endIndex do
      local representationForCheck = fp_ut.loadRepresentation(filenamesRepresentation[indexForCheck])
      if representationForCheck then
	 local floorplanForCheck = image.load(filenames[indexForCheck], 3)
	 --if indexForCheck == 4 then
	 --image.save('test/walls.png', fp_ut.drawLineMask(floorplanForCheck:size(3), floorplanForCheck:size(2), representationForCheck.walls, 5))
	 --os.exit(1)
         --end
         if math.max(floorplanForCheck:size(2), floorplanForCheck:size(3)) < smallImageSize or math.max(floorplanForCheck:size(2), floorplanForCheck:size(3)) > windowSize then
            local scale = windowSize / math.max(floorplanForCheck:size(2), floorplanForCheck:size(3))
            floorplanForCheck = image.scale(floorplanForCheck, windowSize)
	    representationForCheck = fp_ut.scaleRepresentationByRatio(representationForCheck, scale)
         end

	 local sanity = fp_ut.checkSanity(floorplanForCheck, representationForCheck)
         if not sanity then
	    print(filenames[indexForCheck])
	    index = indexForCheck
	    break
	 else
	    startIndex = indexForCheck + 1
	    print(indexForCheck .. ' passed sanity check')
	 end
      end
   end
   assert(index <= #filenames, "no next image")
end


function displayPreview()
   --floorplan = image.load(filenames[index], 3)
   --fp_ut.getWallPlacements(width, height, representation, 5)
   --fp_ut.detectIcons(floorplan)
   --fp_ut.evaluateDetection(floorplan, representation)
   --outputPopupData()
   if preview then
      local orientation = 0
      if orientation == 1 then
         floorplan = floorplan:clone()
         representation = fp_ut.rotateRepresentation(representation, width, height, 1)
      elseif orientation == 2 then
         floorplan = image.hflip(floorplan:transpose(2, 3))
         representation = fp_ut.rotateRepresentation(representation, width, height, 2)
      elseif orientation == 3 then
         floorplan = image.hflip(image.vflip(floorplan))
         representation = fp_ut.rotateRepresentation(representation, width, height, 3)
      elseif orientation == 4 then
         floorplan = image.vflip(floorplan:transpose(2, 3))
         representation = fp_ut.rotateRepresentation(representation, width, height, 4)
      end

      --local floorplan = image.scale(floorplan, 500, 600)
      --local representation = scaleRepresentation(representation, width, height, 500, 600)
      --print(#floorplan)
      --local floorplan = image.crop(floorplan, 50, 100, 500, 600)
      --local representation = cropRepresentation(representation, 50, 100, 500, 600)
      width = floorplan:size(3)
      height = floorplan:size(2)

      --print(#representation.walls)
      --print(#representation.doors)
      --print(#representation.icons)
      --print(#representation.labels)

      --[[
         local representationGlobal = fp_ut.convertRepresentation(width, height, representation, 'P', 5)
         local representationTensor = fp_ut.convertRepresentationToTensor(width, height, gridWidth, gridHeight, representationGlobal)
         local representationPreview = fp_ut.convertTensorToRepresentation(width, height, representationTensor, 0.5)
      ]]--
      --local representationImage = fp_ut.drawRepresentationImage(floorplan, representation)

      --representationImage = fp_ut.extractCandidateRegions(floorplan, floorplanSegmentation, representation.walls)
      --representationImage = fp_ut.findWalls(floorplan)
      --local representationImage = fp_ut.predictSegmentation(floorplan, representation.walls, true)
      --representationImage = fp_ut.drawSegmentation(segmentation)

      if not imageInfo then
	 imageInfo = fp_ut.getImageInfo(floorplan, representation)

	 for _, label in pairs(representation.labels) do
	    if label[3][1] == 'corridor' then
	       label[1][2] = label[1][2] - 30
	       label[2][2] = label[2][2] - 30
	    end
	 end
      end

      if startPoint and endPoint then
	 if mode == 'walls' or mode == 'doors' then
            if math.abs(endPoint[1] - startPoint[1]) > math.abs(endPoint[2] - startPoint[2]) then
	       endPoint[2] = startPoint[2]
	    else
	       endPoint[1] = startPoint[1]
	    end
	    local point_1, point_2
	    if startPoint[1] + startPoint[2] < endPoint[1] + endPoint[2] then
	       point_1 = {startPoint[1], startPoint[2]}
	       point_2 = {endPoint[1], endPoint[2]}
	    else
	       point_1 = {endPoint[1], endPoint[2]}
	       point_2 = {startPoint[1], startPoint[2]}
	    end

	    local lineDim = fp_ut.lineDim({point_1, point_2})

	    if mode == 'walls' then
	       if lineDim == 1 then
		  table.insert(representation.points, {point_1, point_1, {'point', 1, 4}})
		  table.insert(representation.points, {point_2, point_2, {'point', 1, 2}})
	       else
		  table.insert(representation.points, {point_1, point_1, {'point', 1, 1}})
		  table.insert(representation.points, {point_2, point_2, {'point', 1, 3}})
	       end

	       local wallSegmentIndex
	       local center = {torch.round((point_1[1] + point_2[1]) / 2), torch.round((point_1[2] + point_2[2]) / 2)}
	       for segmentIndex = 1, 10 do
		  if imageInfo.segmentImages[segmentIndex][center[2]][center[1]] == 1 then
		     wallSegmentIndex = segmentIndex
		     break
		  end
	       end

	       table.insert(representation.walls, {point_1, point_2, {'wall', 1, 1}, {wallSegmentIndex, wallSegmentIndex}, {}})

               local segmentMask = imageInfo.segmentImages[wallSegmentIndex]
	       segmentMask:narrow(3 - lineDim, point_1[lineDim] - lineWidth, point_2[lineDim] - point_1[lineDim] + 1 + lineWidth * 2):narrow(lineDim, point_1[3 - lineDim], 1):fill(0)
	       --image.save('test/segment_mask.png', segmentMask)
	       local segments, numSegments = fp_ut.findConnectedComponents(segmentMask)
	       local newLabels = {}
	       for _, label in pairs(representation.labels) do
		  if fp_ut.getNumber('labels', label[3]) ~= wallSegmentIndex then
		     table.insert(newLabels, label)
		  end
	       end
	       for segmentIndex = 1, numSegments - 1 do
		  local labelWidth = 80
		  local labelHeight = 30
		  local roomIndices = segments:eq(segmentIndex):nonzero()
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
		     local point_1 = {torch.round(cx - labelWidth / 2), torch.round(cy - labelHeight / 2)}
		     local point_2 = {torch.round(cx + labelWidth / 2), torch.round(cy + labelHeight / 2)}
		     local itemInfo = fp_ut.getItemInfo('labels', wallSegmentIndex)
		     itemInfo[3] = orientation
		     table.insert(newLabels, {point_1, point_2, itemInfo})
		  end
	       end
	       representation.labels = newLabels
	    elseif mode == 'doors' then
	       local door = {point_1, point_2, {'door', 1, lineDim}}
	       local lineDim = fp_ut.lineDim(door, lineWidth)
	       local doorFixedValue = (door[1][3 - lineDim] + door[2][3 - lineDim]) / 2
               local doorMinValue = math.min(door[1][lineDim], door[2][lineDim])
               local doorMaxValue = math.max(door[1][lineDim], door[2][lineDim])
               for _, wall in pairs(representation.walls) do
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

	       local doorMask
	       local dashLineStride = 10
	       if lineDim == 1 then
		  doorMask = torch.zeros(15, door[2][lineDim] - door[1][lineDim] + 1)
	       else
		  doorMask = torch.zeros(door[2][lineDim] - door[1][lineDim] + 1, 15)
	       end
               for pointIndex = 1, 2 do
                  local point = door[pointIndex]
                  doorMask:narrow(3 - lineDim, point[lineDim] - door[1][lineDim] + 1, 1):fill(1)
               end
               for lineValue = door[1][lineDim], door[2][lineDim], dashLineStride do
                  doorMask:narrow(3 - lineDim, lineValue - door[1][lineDim] + 1, 1):narrow(lineDim, 8, 1):fill(1)
	       end
	       for i = 1, 2 do
                  doorMask = image.dilate(doorMask)
               end
               doorMask = doorMask:byte()
	       table.insert(door, doorMask)
	       table.insert(representation.doors, door)
            end
         end

	 startPoint = nil
         endPoint = nil
      end

      if startPoint and not endPoint and mode == 'labels' then
	 local number = fp_ut.getNumber('labels', {iconTypeCurrent, iconStyleCurrent, iconOrientationCurrent})

	 local previousNumber
         for segmentIndex = 1, 10 do
            if imageInfo.segmentImages[segmentIndex][startPoint[2]][startPoint[1]] == 1 then
	       previousNumber = segmentIndex
               break
            end
         end
	 local segmentMask = imageInfo.segmentImages[previousNumber]

         local segments, numSegments = fp_ut.findConnectedComponents(segmentMask)
	 local segmentIndex = segments[startPoint[2]][startPoint[1]]
	 local labelExists = false
         for _, label in pairs(representation.labels) do
	    local x = (label[1][1] + label[2][1]) / 2
	    local y = (label[1][2] + label[2][2]) / 2
	    if segments[y][x] == segmentIndex then
	       label[3] = fp_ut.getItemInfo('labels', number)
	       labelExists = true
	       break
	    end
         end
	 local labelMask = segments:eq(segmentIndex)
	 if not labelExists then
	    local labelWidth = 80
            local labelHeight = 30
            local roomIndices = labelMask:nonzero()
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
               local point_1 = {torch.round(cx - labelWidth / 2), torch.round(cy - labelHeight / 2)}
               local point_2 = {torch.round(cx + labelWidth / 2), torch.round(cy + labelHeight / 2)}
               local itemInfo = fp_ut.getItemInfo('labels', number)
               itemInfo[3] = orientation
               table.insert(representation.labels, {point_1, point_2, itemInfo})
            end
	 end
	 imageInfo.segmentImages[previousNumber][labelMask] = 0
	 imageInfo.segmentImages[number][labelMask] = 1

	 for _, wall in pairs(representation.walls) do
            local lineDim = fp_ut.lineDim(wall, lineWidth)
            local x = (wall[1][1] + wall[2][1]) / 2
            local y = (wall[1][2] + wall[2][2]) / 2
            local deltas
            if lineDim == 1 then
               deltas = {0, 1}
            else
               deltas = {1, 0}
            end
            for direction = 1, 2 do
               local newX = x
               local newY = y
               for i = 1, lineWidth + 2 do
                  newX = newX + deltas[1] * (direction * 2 - 3)
                  newY = newY + deltas[2] * (direction * 2 - 3)
                  if newX <= 0 or newX > width or newY <= 0 or newY > height then
                     break
                  end
		  if labelMask[newY][newX] > 0 then
                     wall[4][direction] = number
		     break
                  end
               end
            end
         end

         startPoint = nil
      end

      painterAnnotation:gbegin()

      --if not representationImage or not movingItem or (movingItem[3][1] == 'wall' or movingItem[3][1] == 'door') then
      if true then
	 representationImage = torch.ones(3, height, width)
	 for segmentIndex, segmentImage in pairs(imageInfo.segmentImages) do
	    local mask = segmentImage
	    for c = 1, 3 do
	       representationImage[c][mask] = imageInfo.colorMap[segmentIndex][c]
	    end
	 end

	 -- for wallIndex, wallImage in pairs(imageInfo.wallImages) do
	 --    --local mask = wallImage[4]:byte()
	 --    local wall = representation.walls[wallIndex]
	 --    local lineDim = fp_ut.lineDim(wall)
	 --    if lineDim == 1 then
	 --       representationImage:narrow(2, wall[1][2] - lineWidth, lineWidth * 2 + 1):narrow(3, wall[1][1], wall[2][1] - wall[1][1] + 1):copy(wallImage)
	 --    elseif lineDim == 2 then
	 --       representationImage:narrow(2, wall[1][2], wall[2][2] - wall[1][2] + 1):narrow(3, wall[1][1] - lineWidth, lineWidth * 2 + 1):copy(wallImage)
	 --    end
	 --    -- if lineDim == 1 then
	 --    --    image.display{image=wallImage, min=0, max=1, x=wall[1][1], y=wall[1][2] - lineWidth, win=painterAnnotation, saturate=false}
	 --    -- else
	 --    --    image.display{image=wallImage, min=0, max=1, x=wall[1][1] - lineWidth, y=wall[1][2], win=painterAnnotation, saturate=false}
	 --    -- end
	 -- end

	 for wallIndex, wall in pairs(representation.walls) do
	    local roomLabels = wall[4]
	    local lineDim = fp_ut.lineDim(wall, lineWidth)
	    local fixedValue = wall[1][3 - lineDim]
	    local minValue = wall[1][lineDim]
	    local maxValue = wall[2][lineDim]
	    for c = 1, 3 do
	       representationImage[c]:narrow(3 - lineDim, minValue, maxValue - minValue + 1):narrow(lineDim, fixedValue - lineWidth, lineWidth + 1):fill(imageInfo.borderColorMap[roomLabels[1]][c])
               representationImage[c]:narrow(3 - lineDim, minValue, maxValue - minValue + 1):narrow(lineDim, fixedValue + 1, lineWidth + 1):fill(imageInfo.borderColorMap[roomLabels[2]][c])
            end
         end

	 for doorIndex, door in pairs(representation.doors) do
	    local doorMask = door[4]
	    local lineDim = fp_ut.lineDim(door)
	    if doorMask:size(3 - lineDim) ~= door[2][lineDim] - door[1][lineDim] + 1 then
               local dashLineStride = 10
               if lineDim == 1 then
                  doorMask = torch.zeros(15, door[2][lineDim] - door[1][lineDim] + 1)
               else
                  doorMask = torch.zeros(door[2][lineDim] - door[1][lineDim] + 1, 15)
               end
               for pointIndex = 1, 2 do
                  local point = door[pointIndex]
                  doorMask:narrow(3 - lineDim, point[lineDim] - door[1][lineDim] + 1, 1):fill(1)
               end
               for lineValue = door[1][lineDim], door[2][lineDim], dashLineStride do
                  doorMask:narrow(3 - lineDim, lineValue - door[1][lineDim] + 1, 1):narrow(lineDim, 8, 1):fill(1)
               end
               for i = 1, 2 do
                  doorMask = image.dilate(doorMask)
               end
               doorMask = doorMask:byte()
	       door[4] = doorMask
            end
	    if lineDim == 1 then
	       for c = 1, 3 do
                  representationImage[{c, {door[1][2] - 7, door[2][2] + 7}, {door[1][1], door[2][1]}}][doorMask] = 0
	       end
	    else
	       for c = 1, 3 do
		  representationImage[{c, {door[1][2], door[2][2]}, {door[1][1] - 7, door[2][1] + 7}}][doorMask] = 0
	       end
	    end
	 end
	 for pointIndex, point in pairs(representation.points) do
	    local mask = imageInfo.pointImage[4]:byte()
	    for c = 1, 3 do
	       representationImage[{c, {point[1][2] - 8, point[1][2] + 8}, {point[1][1] - 8, point[1][1] + 8}}][mask] = imageInfo.pointImage[c][mask]
	    end
	 end

	 for mode, items in pairs(representation) do
	    if mode == 'icons' then
               for _, item in pairs(items) do
                  local point_1 = item[1]
                  local point_2 = item[2]
                  local icon = loadIcon(item[3][1], item[3][2], item[3][3])
                  local iconDisplay = image.scale(icon, point_2[1] - point_1[1] + 1, point_2[2] - point_1[2] + 1)
		  iconDisplay = iconDisplay:repeatTensor(3, 1, 1)
		  representationImage[{{}, {point_1[2] + 1, point_2[2] + 1}, {point_1[1] + 1, point_2[1] + 1}}]:copy(iconDisplay)
               end
	    elseif mode == 'labels' then
               for _, item in pairs(items) do
                  local point_1 = item[1]
                  local point_2 = item[2]
                  local icon = loadIcon(item[3][1], item[3][2], item[3][3])
                  local iconDisplay = image.scale(icon, point_2[1] - point_1[1] + 1, point_2[2] - point_1[2] + 1, 'bicubic')
		  local mask = iconDisplay:lt(0.5)
		  for c = 1, 3 do
		     representationImage[{c, {point_1[2] + 1, point_2[2] + 1}, {point_1[1] + 1, point_2[1] + 1}}][mask] = 0
		  end
               end
            end
         end

      end

      painterAnnotation:showpage()
      image.display{image=representationImage, min=0, max=1, x=0, y=0, win=painterAnnotation, saturate=false} --, zoom=200/math.max(representationImage:size(2), representationImage:size(3))}


      -- for mode, items in pairs(representation) do
      -- 	 if mode == 'icons' then
      -- 	    for _, item in pairs(items) do
      -- 	       local point_1 = item[1]
      -- 	       local point_2 = item[2]
      -- 	       local icon = loadIcon(item[3][1], item[3][2], item[3][3])
      -- 	       local iconDisplay = image.scale(icon, point_2[1] - point_1[1] + 1, point_2[2] - point_1[2] + 1)
      -- 	       --painterAnnotation:setcolor(0.5, 0.5, 0.5, 0.5)
      -- 	       image.display{image=iconDisplay, min=0, max=1, x=point_1[1], y=point_1[2], win=painterAnnotation, saturate=false}
      -- 	    end
      -- 	 end
      -- end


      if startPoint and not endPoint then
	 if mode == 'walls' then
	    local crossWidth = 10
	    painterAnnotation:moveto(startPoint[1] - crossWidth, startPoint[2] - crossWidth)
	    painterAnnotation:lineto(startPoint[1] + crossWidth, startPoint[2] + crossWidth)
	    painterAnnotation:moveto(startPoint[1] - crossWidth, startPoint[2] + crossWidth)
	    painterAnnotation:lineto(startPoint[1] + crossWidth, startPoint[2] - crossWidth)
	    painterAnnotation:setcolor(0, 0, 1, 1);
	    painterAnnotation:setlinewidth(10)
	    painterAnnotation:fill(false)
	    painterAnnotation:stroke()
	 elseif mode == 'doors' then
	    local crossWidth = 8
	    painterAnnotation:moveto(startPoint[1] - crossWidth, startPoint[2] - crossWidth)
	    painterAnnotation:lineto(startPoint[1] + crossWidth, startPoint[2] + crossWidth)
	    painterAnnotation:moveto(startPoint[1] - crossWidth, startPoint[2] + crossWidth)
	    painterAnnotation:lineto(startPoint[1] + crossWidth, startPoint[2] - crossWidth)
	    painterAnnotation:setcolor(0, 1, 0, 1);
	    painterAnnotation:setlinewidth(8)
	    painterAnnotation:fill(false)
	    painterAnnotation:stroke()
	 end
      end
      if movingItems and #movingItems > 0 then
	 local mins = {}
	 local maxs = {}
	 for _, item in pairs(movingItems) do
	    if item[7] then
	       for c = 1, 2 do
		  if not mins[c] or item[1][c] < mins[c] then
		     mins[c] = item[1][c]
		  end
		  if not maxs[c] or item[2][c] > maxs[c] then
		     maxs[c] = item[2][c]
		  end
	       end
	    end
	 end
	 painterAnnotation:moveto(mins[1] - lineWidth * 2, mins[2] - lineWidth * 2)
	 painterAnnotation:lineto(maxs[1] + lineWidth * 2, mins[2] - lineWidth * 2)
	 painterAnnotation:moveto(maxs[1] + lineWidth * 2, mins[2] - lineWidth * 2)
	 painterAnnotation:lineto(maxs[1] + lineWidth * 2, maxs[2] + lineWidth * 2)
	 painterAnnotation:moveto(maxs[1] + lineWidth * 2, maxs[2] + lineWidth * 2)
	 painterAnnotation:lineto(mins[1] - lineWidth * 2, maxs[2] + lineWidth * 2)
	 painterAnnotation:moveto(mins[1] - lineWidth * 2, maxs[2] + lineWidth * 2)
         painterAnnotation:lineto(mins[1] - lineWidth * 2, mins[2] - lineWidth * 2)
         painterAnnotation:setcolor(0, 0, 0, 1);
         painterAnnotation:setlinewidth(3)
         painterAnnotation:fill(false)
         painterAnnotation:stroke()
      end

      painterAnnotation:gend()
   else
      display()
      refresh = true
      draw()
      refresh = false
   end
end

function display()
   p:start('display','fps')
   painterFloorplan:gbegin()
   painterFloorplan:showpage()
   image.display{image=floorplan, min=0, max=1, win=painterFloorplan, saturate=false}
   --image.display{image=transformed, min=-2, max=2, nrow=4,
   --painterFloorplan=painterFloorplan, zoom=1/2, x=frame:size(3), saturate=false}
   painterFloorplan:gend()

   if not preview then
      painterAnnotation:gbegin()
      painterAnnotation:showpage()
      image.display{image=annotation, min=0, max=1, win=painterAnnotation, saturate=false}
      painterAnnotation:gend()
      p:lap('display')
   end
end


function drawLinePlain(point_1, point_2, color_1, color_2, lineWidth)
   painterFloorplan:gbegin()
   painterFloorplan:moveto(point_1[1], point_1[2])
   painterFloorplan:lineto(point_2[1], point_2[2])
   painterFloorplan:setcolor(color_1[1], color_1[2], color_1[3], color_1[4]);
   painterFloorplan:fill(false)
   painterFloorplan:setlinewidth(lineWidth)
   painterFloorplan:stroke()
   painterFloorplan:gend()

   if not preview then
      painterAnnotation:gbegin()
      painterAnnotation:moveto(point_1[1], point_1[2])
      painterAnnotation:lineto(point_2[1], point_2[2])
      painterAnnotation:setcolor(color_2[1], color_2[2], color_2[3], color_2[4]);
      painterAnnotation:fill(false)
      painterAnnotation:setlinewidth(lineWidth)
      painterAnnotation:stroke()
      painterAnnotation:gend()
   end
   --print(point_1[1])
   --print(point_1[2])
end

function drawLine(line)
   painterFloorplan:gbegin()
   painterFloorplan:moveto(line[1][1], line[1][2])
   painterFloorplan:lineto(line[2][1], line[2][2])
   if line[3][1] == 'wall' then
      painterFloorplan:setcolor(1, 0, 0, 0.5);
      painterFloorplan:setlinewidth(10)
   else
      painterFloorplan:setcolor(0, 0, 1, 0.5);
      painterFloorplan:setlinewidth(6)
   end
   painterFloorplan:fill(false)
   painterFloorplan:stroke()
   painterFloorplan:gend()

   painterAnnotation:gbegin()
   painterAnnotation:moveto(line[1][1], line[1][2])
   painterAnnotation:lineto(line[2][1], line[2][2])
   if line[3][1] == 'wall' then
      painterAnnotation:setcolor(0, 0, 0, 1);
      painterAnnotation:setlinewidth(10)
   else
      painterAnnotation:setcolor(1, 1, 1, 1);
      painterAnnotation:setlinewidth(6)
   end
   painterAnnotation:fill(false)
   painterAnnotation:stroke()

   if line[3][1] == 'wall' and line[3][2] == 2 then
      painterAnnotation:moveto(line[1][1], line[1][2])
      painterAnnotation:lineto(line[2][1], line[2][2])
      painterAnnotation:setcolor(1, 1, 1, 1);
      painterAnnotation:setlinewidth(6)
      painterAnnotation:fill(false)
      painterAnnotation:stroke()
   end

   painterAnnotation:gend()
end

function drawLines()
   for _, line in pairs(representation.walls) do
      if #line == 3 then
	 drawLine(line)
         table.insert(line, 1)
	 representation.walls[_] = line
      elseif refresh == true then
         drawLine(line)
      end
   end
   for _, line in pairs(representation.doors) do
      if #line == 3 then
	 drawLine(line)
         table.insert(line, 1)
         representation.doors[_] = line
      elseif refresh == true then
	 drawLine(line)
      end
   end
end

function draw()
   if preview then
      return
   end
   --display()
   drawLines()
   drawIcons()
end

function drawRectanglePlain(point_1, point_2)
   painterFloorplan:gbegin()
   painterFloorplan:rectangle(point_1[1], point_1[2], point_2[1] - point_1[1] + 1, point_2[2] - point_1[2] + 1)
   painterFloorplan:setcolor(color[1], color[2], color[3], color[4]);
   painterFloorplan:fill(false)
   painterFloorplan:gend()

   painterAnnotation:gbegin()
   painterAnnotation:rectangle(point_1[1], point_1[2], point_2[1] - point_1[1] + 1, point_2[2] - point_1[2] + 1)
   painterAnnotation:setcolor("black");
   painterAnnotation:fill(false)
   painterAnnotation:gend()
   --print(point_1[1])
   --print(point_1[2])
end

function drawIcon(iconInfo, hide)
   local point_1 = iconInfo[1]
   local point_2 = iconInfo[2]
   local icon = loadIcon(iconInfo[3][1], iconInfo[3][2], iconInfo[3][3])
   local iconDisplay = image.scale(icon, point_2[1] - point_1[1] + 1, point_2[2] - point_1[2] + 1)

   if not hide then
      painterFloorplan:gbegin()
      painterFloorplan:setcolor(0.5, 0.5, 0.5, 0.5)
      image.display{image=iconDisplay, min=0, max=1, x=point_1[1], y=point_1[2], win=painterFloorplan, saturate=false}
      painterFloorplan:gend()
   end

   painterAnnotation:gbegin()
   painterAnnotation:setcolor(0.5, 0.5, 0.5, 0.5)
   image.display{image=iconDisplay, min=0, max=1, x=point_1[1], y=point_1[2], win=painterAnnotation, saturate=false}
   painterAnnotation:gend()
   --print(point_1[1])
   --print(point_1[2])
end

function drawIcons()
   for _, icon in pairs(representation.icons) do
      if #icon == 3 then
	 drawIcon(icon)
         table.insert(icon, 1)
	 representation.icons[_] = icon
      elseif refresh == true then
	 drawIcon(icon)
      end
   end
   for _, label in pairs(representation.labels) do
      local hide
      if mode == 'walls' or mode == 'doors' or mode == 'icons' then
         hide = true
      end
      if #label == 3 then
         drawIcon(label, hide)
         table.insert(label, 1)
         representation.labels[_] = label
      elseif refresh == true then
         drawIcon(label, hide)
      end
   end
end

function pointValid(x, y)
   return x > 0 and x <= width and y > 0 and y <= height
end

function rectangleValid(x, y)
   return x > 0 and x <= width and y > 0 and y <= height and math.abs(x - prevX) > 5 and math.abs(y - prevY) > 5
end

function lineValid(x, y)
   return x > 0 and x <= width and y > 0 and y <= height and (math.abs(x - prevX) > 5 or math.abs(y - prevY) > 5)
end

function mousePressEvent(x, y)
   if mode == 'move' then
      local point = {x, y}
      for mode, items in pairs(representation) do
	 for _, item in pairs(items) do
	    if mode == 'walls' or mode == 'doors' then
	       local lineDim = fp_ut.lineDim(item)
	       if lineDim > 0 then
		  if (point[lineDim] - item[1][lineDim]) * (point[lineDim] - item[2][lineDim]) <= 0 and math.abs(point[3 - lineDim] - (item[1][3 - lineDim] + item[2][3 - lineDim]) / 2) <= lineWidth then
                     movingItem = item
		     if mode == 'doors' then
			for pointIndex = 1, 2 do
			   if math.abs(point[lineDim] - item[pointIndex][lineDim]) <= lineWidth then
			      movingPointIndex = pointIndex
			   end
			end
		     end
                     break
                  end
               end
	    elseif mode == 'icons' or mode == 'labels' then
               if (point[1] - item[1][1]) * (point[1] - item[2][1]) <= 0 and (point[2] - item[1][2]) * (point[2] - item[2][2]) <= 0 then
		  movingItem = item
                  break
	       end
            end
         end
	 if movingItem then
	    break
	 end
      end
      prevX = x
      prevY = y
      return
   end

   if mode == 'move_multiple' then
      local point = {x, y}
      for mode, items in pairs(representation) do
	 if mode == 'walls' then
	    local minLength
	    local minLengthItemIndex
            for _, item in pairs(items) do
               local lineDim = fp_ut.lineDim(item, lineWidth)
               if lineDim > 0 then
                  if (point[lineDim] - item[1][lineDim]) * (point[lineDim] - item[2][lineDim]) <= 0 and math.abs(point[3 - lineDim] - (item[1][3 - lineDim] + item[2][3 - lineDim]) / 2) <= lineWidth then
		     if not movingItems then
			movingItems = {}
		     end
		     local itemExists = false
		     for _, v in pairs(movingItems) do
			if v == item then
			   itemExists = true
			   break
			end
		     end
		     if not itemExists then
			table.insert(movingItems, item)
			local length = item[2][lineDim] - item[1][lineDim]
			if not minLength or length < minLength then
			   minLengthItemIndex = #movingItems
			   minLength = length
			end
		     end
                  end
               end
	    end
	    if minLengthItemIndex then
	       table.insert(movingItems[minLengthItemIndex], true)
	    end
	 end
      end
      displayPreview()
      prevX = x
      prevY = y
      return
   end

   if preview then
      local point = {x, y}
      if mode ~= 'remove' then
         for _, wall in pairs(representation.walls) do
	    local lineDim = fp_ut.lineDim(wall, lineWidth)
	    if math.abs(point[3 - lineDim] - wall[1][3 - lineDim]) <= lineWidth and wall[1][lineDim] < point[lineDim] and wall[2][lineDim] > point[lineDim] then
	       point[3 - lineDim] = wall[1][3 - lineDim]
	       break
	    end
	 end
	 if not startPoint then
	    startPoint = point
	 else
	    endPoint = point
	 end
      else
	 local doorRemoved = false
         for mode, items in pairs(representation) do
	    if mode == 'icons' or mode == 'labels' then
	       local newItems = {}
               for _, item in pairs(items) do
		  if item[1][1] > point[1] or item[2][1] < point[1] or item[1][2] > point[2] or item[2][2] < point[2] then
		     table.insert(newItems, item)
                  end
               end
	       representation[mode] = newItems
            elseif mode == 'doors' then
	       local newItems = {}
               for _, item in pairs(items) do
		  local lineDim = fp_ut.lineDim(item, lineWidth)
                  if item[1][lineDim] > point[lineDim] or item[2][lineDim] < point[lineDim] or item[1][3 - lineDim] - lineWidth > point[3 - lineDim] or item[2][3 - lineDim] + lineWidth < point[3 - lineDim] then
		     table.insert(newItems, item)
                  else
                     doorRemoved = true
                  end
               end
	       representation[mode] = newItems
            end
         end
	 if not doorRemoved then
	    local newItems = {}
	    for _, item in pairs(representation.walls) do
               local lineDim = fp_ut.lineDim(item, lineWidth)
               if item[1][lineDim] > point[lineDim] or item[2][lineDim] < point[lineDim] or item[1][3 - lineDim] - lineWidth > point[3 - lineDim] or item[2][3 - lineDim] + lineWidth < point[3 - lineDim] then
                  table.insert(newItems, item)
	       else
		  local lineDim = fp_ut.lineDim(item, lineWidth)
		  local roomLabels = item[4]
		  local wallSegmentIndex = math.min(roomLabels[1], roomLabels[2])
		  local segmentMask = imageInfo.segmentImages[wallSegmentIndex]
                  segmentMask:narrow(3 - lineDim, item[1][lineDim], item[2][lineDim] - item[1][lineDim] + 1):narrow(lineDim, item[1][3 - lineDim], 1):fill(1)
                  if roomLabels[1] == roomLabels[2] then
                     --image.save('test/segment_mask.png', segmentMask)
                     local segments, numSegments = fp_ut.findConnectedComponents(segmentMask)
                     local newLabels = {}
                     for _, label in pairs(representation.labels) do
                        if fp_ut.getNumber('labels', label[3]) ~= wallSegmentIndex then
                           table.insert(newLabels, label)
                        end
                     end
                     for segmentIndex = 1, numSegments - 1 do
                        local labelWidth = 80
                        local labelHeight = 30
                        local roomIndices = segments:eq(segmentIndex):nonzero()
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
                           local point_1 = {torch.round(cx - labelWidth / 2), torch.round(cy - labelHeight / 2)}
                           local point_2 = {torch.round(cx + labelWidth / 2), torch.round(cy + labelHeight / 2)}
                           local itemInfo = fp_ut.getItemInfo('labels', wallSegmentIndex)
                           itemInfo[3] = orientation
                           table.insert(newLabels, {point_1, point_2, itemInfo})
                        end
                     end
                     representation.labels = newLabels
		  end
		  representation.points[item[5][1]] = nil
		  representation.points[item[5][2]] = nil
               end
            end
            representation.walls = newItems
         end
      end

      displayPreview()
      return
   end


   if mode == 'walls' or mode == 'doors' then
      if pointValid(prevX, prevY) and lineValid(x, y) then
         if shiftPressed ~= true then
            if math.abs(x - prevX) > math.abs(y - prevY) then
               y = prevY
            else
               x = prevX
            end
         end
         saveLine({prevX, prevY}, {x, y})
         draw()
      end
   end
   if mode == 'doors' and pointValid(prevX, prevY) then
      prevX = -1
      prevY = -1
   else
      prevX = x
      prevY = y
   end
end

function mouseMoveEvent(x, y, s, n)
   if mode == 'icons' and n == 'LeftButton' and startPoint and (math.abs(x - startPoint[1]) >= 3 or math.abs(y - startPoint[2]) >= 3) then
      local point_1 = startPoint
      local point_2 = {x, y}
      local icon = loadIcon(iconTypeCurrent, iconStyleCurrent, iconOrientationCurrent)
      local iconDisplay = image.scale(icon, point_2[1] - point_1[1] + 1, point_2[2] - point_1[2] + 1)
      --painterAnnotation:setcolor(0.5, 0.5, 0.5, 0.5)
      painterAnnotation:gbegin()
      image.display{image=iconDisplay, min=0, max=1, x=point_1[1], y=point_1[2], win=painterAnnotation, saturate=false}
      painterAnnotation:gend()
      return
   end

   if imageInfo and movingItem and (x ~= prevX or y ~= prevY) then
      local movingX = true
      local movingY = true
      if movingItem[3][1] == 'wall' then
	 local lineDim = fp_ut.lineDim(movingItem)
         if lineDim == 1 then
	    movingX = false
         elseif lineDim == 2 then
	    movingY = false
	 else
	    return
	 end
      end
      if movingItem[3][1] == 'door' then
         local lineDim = fp_ut.lineDim(movingItem)
         if lineDim == 1 then
            movingY = false
         elseif lineDim == 2 then
            movingX = false
         else
            return
         end
      end

      local minMovement = 3
      if (movingX and math.abs(x - prevX) >= minMovement) or (movingY and math.abs(y - prevY) >= minMovement) then
         for pointIndex = 1, 2 do
	    if not movingPointIndex or pointIndex == movingPointIndex then
	       if movingX then
		  movingItem[pointIndex][1] = movingItem[pointIndex][1] + x - prevX
	       end
	       if movingY then
		  movingItem[pointIndex][2] = movingItem[pointIndex][2] + y - prevY
	       end
	    end
	 end
	 if movingItem[3][1] == 'wall' then
	    local lineDim = fp_ut.lineDim(movingItem)
	    if lineDim > 0 then
	       local deltas = {x - prevX, y - prevY}
	       local delta = deltas[3 - lineDim]


	       local pointIndices = movingItem[5]
	       for _, pointIndex in pairs(pointIndices) do
		  local point = representation.points[pointIndex]
                  point[1][3 - lineDim] = point[1][3 - lineDim] + delta
                  point[2][3 - lineDim] = point[2][3 - lineDim] + delta

                  local walls = imageInfo.pointWalls[pointIndex]
		  for _, wallInfo in pairs(walls) do
		     if fp_ut.lineDim(representation.walls[wallInfo[1]], lineWidth) + lineDim == 3 then
			representation.walls[wallInfo[1]][wallInfo[2]][3 - lineDim] = point[1][3 - lineDim]
		     end
		  end
	       end

	       local doorIndices = movingItem[6]
	       for _, doorIndex in pairs(doorIndices) do
		  local door = representation.doors[doorIndex]
                  door[1][3 - lineDim] = door[1][3 - lineDim] + delta
                  door[2][3 - lineDim] = door[2][3 - lineDim] + delta
	       end

	       local fixedValue = movingItem[1][3 - lineDim]
               local minValue = movingItem[1][lineDim]
               local maxValue = movingItem[2][lineDim]

	       for _, icon in pairs(representation.icons) do
		  if math.max(icon[1][lineDim], minValue) < math.min(icon[2][lineDim], maxValue) and icon[1][3 - lineDim] < fixedValue and icon[2][3 - lineDim] > fixedValue then
		     local delta_1 = fixedValue - icon[1][3 - lineDim]
		     local delta_2 = icon[2][3 - lineDim] - fixedValue
		     if delta_1 < delta_2 then
			for pointIndex = 1, 2 do
                           icon[pointIndex][3 - lineDim] = icon[pointIndex][3 - lineDim] + delta_1
                        end
                     else
			for pointIndex = 1, 2 do
                           icon[pointIndex][3 - lineDim] = icon[pointIndex][3 - lineDim] - delta_2
                        end
                     end
		  end
	       end


               local roomLabels = movingItem[4]
               if delta < 0 then
		  if roomLabels[1] <= 10 then
                     imageInfo.segmentImages[roomLabels[1]]:narrow(3 - lineDim, minValue, maxValue - minValue + 1):narrow(lineDim, fixedValue, -delta + 1):fill(0)
                  end
                  if roomLabels[2] <= 10 then
                     imageInfo.segmentImages[roomLabels[2]]:narrow(3 - lineDim, minValue, maxValue - minValue + 1):narrow(lineDim, fixedValue + 1, -delta + 1):fill(1)
                  end
               else
		  if roomLabels[1] <= 10 then
                     imageInfo.segmentImages[roomLabels[1]]:narrow(3 - lineDim, minValue, maxValue - minValue + 1):narrow(lineDim, fixedValue - delta, delta + 1):fill(1)
                  end
                  if roomLabels[2] <= 10 then
                     imageInfo.segmentImages[roomLabels[2]]:narrow(3 - lineDim, minValue, maxValue - minValue + 1):narrow(lineDim, fixedValue - delta - 1, delta + 1):fill(0)
                  end
               end
            end
	 end

	 moved = true

         displayPreview()
	 prevX = x
	 prevY = y
      end
   end


   if imageInfo and movingItems and #movingItems > 0 and (x ~= prevX or y ~= prevY) then
      local movingX = true
      local movingY = true
      local lineDim = fp_ut.lineDim(movingItems[1])
      if lineDim == 1 then
	 movingX = false
      elseif lineDim == 2 then
	 movingY = false
      else
	 return
      end

      local minMovement = 3
      if (movingX and math.abs(x - prevX) >= minMovement) or (movingY and math.abs(y - prevY) >= minMovement) then
	 local movingPoints = {}
	 local movingDoors = {}
         local movingIcons = {}

	 local deltas = {x - prevX, y - prevY}
	 local delta = deltas[3 - lineDim]
         for _, item in pairs(movingItems) do
	    for pointIndex = 1, 2 do
	       if not movingPointIndex or pointIndex == movingPointIndex then
		  if movingX then
		     item[pointIndex][1] = item[pointIndex][1] + x - prevX
		  end
		  if movingY then
		     item[pointIndex][2] = item[pointIndex][2] + y - prevY
		  end
	       end
	    end


	    local pointIndices = item[5]
	    for _, pointIndex in pairs(pointIndices) do
	       movingPoints[pointIndex] = true
	    end

	    local doorIndices = item[6]
	    for _, doorIndex in pairs(doorIndices) do
	       movingDoors[doorIndex] = true
	    end

	    local fixedValue = item[1][3 - lineDim]
            local minValue = item[1][lineDim]
	    local maxValue = item[2][lineDim]

	    for _, icon in pairs(representation.icons) do
	       if math.max(icon[1][lineDim], minValue) < math.min(icon[2][lineDim], maxValue) and icon[1][3 - lineDim] < fixedValue and icon[2][3 - lineDim] > fixedValue then
		  movingIcons[_] = true
	       end
	    end


	    local roomLabels = item[4]
	    if delta < 0 then
	       if roomLabels[1] <= 10 and roomLabels[1] ~= roomLabels[2] then
		  imageInfo.segmentImages[roomLabels[1]]:narrow(3 - lineDim, minValue, maxValue - minValue + 1):narrow(lineDim, fixedValue, -delta + 1):fill(0)
	       end
	       if roomLabels[2] <= 10 then
		  imageInfo.segmentImages[roomLabels[2]]:narrow(3 - lineDim, minValue, maxValue - minValue + 1):narrow(lineDim, fixedValue + 1, -delta + 1):fill(1)
	       end
	    else
	       if roomLabels[2] <= 10 and roomLabels[2] ~= roomLabels[1] then
                  imageInfo.segmentImages[roomLabels[2]]:narrow(3 - lineDim, minValue, maxValue - minValue + 1):narrow(lineDim, fixedValue - delta, delta + 1):fill(0)
               end
               if roomLabels[1] <= 10 then
		  imageInfo.segmentImages[roomLabels[1]]:narrow(3 - lineDim, minValue, maxValue - minValue + 1):narrow(lineDim, fixedValue - delta - 1, delta + 1):fill(1)
	       end
	    end
	 end

	 for pointIndex, _ in pairs(movingPoints) do
            local point = representation.points[pointIndex]
            point[1][3 - lineDim] = point[1][3 - lineDim] + delta
            point[2][3 - lineDim] = point[2][3 - lineDim] + delta

            local walls = imageInfo.pointWalls[pointIndex]
            for _, wallInfo in pairs(walls) do
               if fp_ut.lineDim(representation.walls[wallInfo[1]], lineWidth) + lineDim == 3 then
                  representation.walls[wallInfo[1]][wallInfo[2]][3 - lineDim] = point[1][3 - lineDim]
               end
            end
	 end

	 for doorIndex, _ in pairs(movingDoors) do
            local door = representation.doors[doorIndex]
	    door[1][3 - lineDim] = door[1][3 - lineDim] + delta
	    door[2][3 - lineDim] = door[2][3 - lineDim] + delta
	 end

         local fixedValue = movingItems[1][1][3 - lineDim]
         for iconIndex, _ in pairs(movingIcons) do
	    local icon = representation.icons[iconIndex]
	    local delta_1 = fixedValue - icon[1][3 - lineDim]
	    local delta_2 = icon[2][3 - lineDim] - fixedValue
	    if delta_1 < delta_2 then
	       for pointIndex = 1, 2 do
		  icon[pointIndex][3 - lineDim] = icon[pointIndex][3 - lineDim] + delta_1
	       end
	    else
	       for pointIndex = 1, 2 do
		  icon[pointIndex][3 - lineDim] = icon[pointIndex][3 - lineDim] - delta_2
	       end
	    end
	 end

	 moved = true

         displayPreview()
         prevX = x
         prevY = y
      end
   end

end

function intersect(rectangle_1, rectangle_2)
   for c = 1, 2 do
      if math.min(rectangle_1[1][c], rectangle_1[2][c]) >= math.max(rectangle_2[1][c], rectangle_2[2][c]) or math.min(rectangle_2[1][c], rectangle_2[2][c]) >= math.max(rectangle_1[1][c], rectangle_1[2][c]) then
	 return false
      end
   end
   return true
end

function removeItems(point_1, point_2)
   local removedRepresentation = emptyRepresentation()
   for mode, items in pairs(representation) do
      for index, item in pairs(items) do
	 if intersect({item[1], item[2]}, {point_1, point_2}) then
	    --print('remove')
            table.insert(removedRepresentation[mode], item)
	    table.remove(items, index)
	    --table.remove(representation[mode], index)
	 end
      end
   end
end

function mouseReleaseEvent(x, y)
   if preview then
      if movingItem then
	 movingItem = nil
	 movingPointIndex = nil
      end
      if moved then
	 if movingItems then
            movingItems = nil
         end
         moved = nil
	 --imageInfo = nil
         --displayPreview()
      end
      if mode == 'remove' then
	 imageInfo = nil
         displayPreview()
      end

      if mode == 'icons' and startPoint then
	 local endPoint = {x, y}
         local point_1, point_2
         if startPoint[1] + startPoint[2] < endPoint[1] + endPoint[2] then
            point_1 = {startPoint[1], startPoint[2]}
            point_2 = {endPoint[1], endPoint[2]}
         else
            point_1 = {endPoint[1], endPoint[2]}
            point_2 = {startPoint[1], startPoint[2]}
         end
         table.insert(representation.icons, {point_1, point_2, {iconTypeCurrent, iconStyleCurrent, iconOrientationCurrent}})
      end

      return
   end

   -- if preview then
   --    representation.walls = fp_ut.pointsToLines(width, height, representation.points, lineWidth)
   --    representation.points = fp_ut.linesToPoints(width, height, representation.walls, lineWidth)
   --    imageInfo = nil
   --    displayPreview()
   -- end

   if (mode == 'icons' or mode == 'labels') and pointValid(prevX, prevY) and rectangleValid(x, y) then
      table.insert(representation[mode], {{prevX, prevY}, {x, y}, {iconTypeCurrent, iconStyleCurrent, iconOrientationCurrent}})
      draw()
      prevX = -1
      prevY = -1
   elseif mode == 'remove' and pointValid(prevX, prevY) then
      removeItems({prevX, prevY}, {x, y})
      display()
      refresh = true
      draw()
      refresh = false
      prevX = -1
      prevY = -1
   elseif (mode == 'doors' or mode == 'icons') and pointValid(x, y) and candidateRegions then
      local regionIndex = candidateRegions[mode][y][x]
      if regionIndex > 0 and not ctrlPressed then
	 local mask = candidateRegions[mode]:eq(regionIndex)
	 if pointValid(prevX, prevY) then
	    local previousRegionIndex = candidateRegions[mode][prevY][prevX]
	    if previousRegionIndex > 0 then
	       mask = mask + candidateRegions[mode]:eq(previousRegionIndex)
	    end
	 end
	 local indices = mask:nonzero()
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
	 table.insert(representation[mode], {point_1, point_2, {iconTypeCurrent, iconStyleCurrent, iconOrientationCurrent}})
         draw()
         prevX = -1
         prevY = -1
      end
   end
end

--[[
   function mouseMoveEvent(x, y)
   if mode == 'icons' then
   if prevX > 0 and prevX <= width and prevY > 0 and prevY <= height then
   drawRectangle({prevX, prevY}, {x, y})
      end
   end
end
]]--

local iconImages = {}
function loadIcon(iconType, iconStyle, iconOrientation)
   if not iconImages[iconType] then
      iconImages[iconType] = {}
   end
   if not iconImages[iconType][iconStyle] then
      iconImages[iconType][iconStyle] = {}
   end
   if not iconImages[iconType][iconStyle][iconOrientation] then
      local icon = image.load('../icons/' .. iconType .. '_' .. iconStyle .. '.jpg', 1)
      assert(icon ~= nil)
      if icon:dim() == 3 then
	 icon = icon[1]
      end
      iconImages[iconType][iconStyle][iconOrientation] = rotateIcon(icon, iconOrientation)
   end
   return iconImages[iconType][iconStyle][iconOrientation]
end

function rotateIcon(iconOriginal, iconOrientation)
   local iconRotated
   if iconOrientation == 1 then
      iconRotated = iconOriginal:clone()
   elseif iconOrientation == 2 then
      iconRotated = image.hflip(iconOriginal:transpose(1, 2):contiguous())
   elseif iconOrientation == 3 then
      iconRotated = image.vflip(image.hflip(iconOriginal))
   else
      iconRotated = image.vflip(iconOriginal:transpose(1, 2):contiguous())
   end
   return iconRotated
end

function displayIcon()
   local iconExists, icon = pcall(function()
         return loadIcon(iconTypeCurrent, iconStyleCurrent, iconOrientationCurrent)
   end)
   if iconExists == false then
      return
   end

   painterIcon:gbegin()
   painterIcon:showpage()

   local offsetX = 0
   local offsetY = 0
   if iconOrientationCurrent == 2 then
      offsetX = painterIcon.width - icon:size(2)
   elseif iconOrientationCurrent == 3 then
      offsetX = painterIcon.width - icon:size(2)
      offsetY = painterIcon.height - icon:size(1)
   elseif iconOrientationCurrent == 4 then
      offsetY = painterIcon.height - icon:size(1)
   end

   image.display{image=icon, min=0, max=1, x=offsetX, y=offsetY, win=painterIcon, saturate=false}
   painterIcon:gend()
end

function displayMask()
   if not maskImage then
      return
   end
   painterMask:gbegin()
   painterMask:showpage()

   image.display{image=image.scale(maskImage, 200), min=0, max=1, x=0, y=0, win=painterMask, saturate=false}
   painterMask:gend()
end

function outputPopupData()
   for i = 1, 50 do
      moveToPreviousImage()
      loadImage()
      if #representation.walls > 0 then
      end
   end
   os.exit(1)
end

function displayFloorplan()
   if original then
      painterFloorplan:gbegin()
      painterFloorplan:showpage()
      image.display{image=floorplan, min=0, max=1, win=painterFloorplan, saturate=false}
      --image.display{image=transformed, min=-2, max=2, nrow=4,
      --painterFloorplan=painterFloorplan, zoom=1/2, x=frame:size(3), saturate=false}
      painterFloorplan:gend()
   else
      display()
      refresh = true
      draw()
      refresh = false
   end
end

function clearLineState()
   prevX = -1
   prevY = -1
end

function saveLine(point_1, point_2)
   table.insert(representation[mode], {point_1, point_2, {iconTypeCurrent, iconStyleCurrent, iconOrientationCurrent}})
end

function keyPressEvent(s, n)
   local key = s:tostring()

   --[[
   if key == 'i' then
      print('write')
      painterAnnotation:gbegin()
      painterAnnotation:write('test/annotation.png')
      painterAnnotation:gend()
      return
   end
   ]]--

   if n ~= 'Key_Shift' then
      clearLineState()
   end

   --print(n)
   --print(key)
   if key == 'i' then
      representation = fp_ut.invertFloorplan(floorplan)
      display()
      refresh = true
      draw()
      refresh = false
      return
   end

   if n == 'Key_Space' then
      --representation = fp_ut.predictRepresentation(floorplan)
      --fp_ut.getSegmentation(width, height, representation)


      if #representation.walls == 0 then
	 representation.walls, floorplanSegmentation = fp_ut.findWalls(floorplan)
      else
	 representation = fp_ut.finalizeRepresentation(representation)
	 candidateRegions, maskImage, labels = fp_ut.extractCandidateRegions(floorplan, floorplanSegmentation, representation.walls)
	 if not representation.labels or #representation.labels == 0 then
	    representation.labels = labels
	 end
	 displayMask()
      end

      --fp_ut.printRepresentation(representation)
      display()
      refresh = true
      draw()
      refresh = false
      return
   end

   if key == 'o' then
      original = not original
      displayFloorplan()
      return
   end

   if key == 'p' then
      preview = not preview
      representation = fp_ut.invertFloorplan(floorplan)
      representation = fp_ut.finalizeRepresentation(representation)
      displayPreview()
      return
   end

   if key == 'P' then
      local newWalls = {}
      for _, wall in pairs(representation.walls) do
	 local wallExists = false
	 for _, newWall in pairs(newWalls) do
	    if math.abs(newWall[1][1] - wall[1][1]) <= 1 and math.abs(newWall[1][2] - wall[1][2]) <= 1 and math.abs(newWall[2][1] - wall[2][1]) <= 1 and math.abs(newWall[2][2] - wall[2][2]) <= 1 then
	       wallExists = true
	       break
	    end
	 end
	 if not wallExists then
	    table.insert(newWalls, wall)
	 end
      end
      representation.walls = newWalls
      --fp_ut.writePopupData(floorplan, representation, 'test/floorplan_69')
      --image.save('test/floorplan_69.png', fp_ut.drawRepresentationImage(floorplan, representation))
      return
   end

   if key == 'f' then
      representation = fp_ut.finalizeRepresentation(representation)
      display()
      refresh = true
      draw()
      refresh = false
      return
   end

   if key == 'S' then
      representation = fp_ut.finalizeRepresentation(representation)
      if false then
	 local sanity = fp_ut.checkSanity(floorplan, representation)
	 if sanity == false and not ctrlPressed then
	    print('sanity check failed')
	    return
	 end
      end
      fp_ut.saveRepresentation(filenamesRepresentation[index], representation, 1 / scaleFactor)
      --moveToNextUnannotatedImage()
      moveToNextImage()
      loadImage()
      return
   end

   if n == 'Key_S' and shiftPressed then
      representation = fp_ut.finalizeRepresentation(representation)
      fp_ut.saveRepresentation(filenamesRepresentation[index], representation, 1 / scaleFactor)
      moveToNextUnannotatedImage()
      loadImage()
      return
   end

   if n == 'Key_Down' then
      moveToNextUnannotatedImage()
      loadImage()
      return
   end

   if n == 'Key_Right' then
      moveToNextImage()
      loadImage()
      return
   end

   if n == 'Key_Left' then
      moveToPreviousImage()
      loadImage()
      return
   end

   if key == 'm' then
      mode = 'move'
      return
   end

   if key == 'M' then
      mode = 'move_multiple'
      return
   end

   if key == 'v' then
      sanity = true
      checkSanities()
      loadImage()
      return
   end

   if key == 'V' then
      startIndex = startIndex + 1
      sanity = true
      checkSanities()
      loadImage()
      return
   end

   if n == 'Key_Escape' then
      return
   end

   if key == 'z' then
      if representation[mode] ~= nil and #representation[mode] > 0 then
	 table.remove(representation[mode])
      end
      display()
      refresh = true
      draw()
      refresh = false
      return
   end

   if n == 'Key_Tab' then
      iconStyleCurrent = iconStyleCurrent + 1
      iconOrientationCurrent = 1
      local iconExists, icon = pcall(function()
            return loadIcon(iconTypeCurrent, iconStyleCurrent, iconOrientationCurrent)
      end)
      if iconExists == false then
	 iconStyleCurrent = 1
      end
      displayIcon()
      return
   end
   if key == '`' then
      iconOrientationCurrent = iconOrientationCurrent % 4 + 1
      displayIcon()
      return
   end

   if keyMap[key] ~= nil then
      mode = keyMap[key][1]
      iconTypeCurrent = keyMap[key][2]
      iconStyleCurrent = 1
      iconOrientationCurrent = 1
      displayIcon()

      display()
      refresh = true
      draw()
      refresh = false
   end

   if n == 'Key_Shift' then
      shiftPressed = true
   end
   if n == 'Key_Control' then
      ctrlPressed = true
   end
end

function keyReleaseEvent(s, n)
   if n == 'Key_Shift' then
      shiftPressed = false
   end
   if n == 'Key_Control' then
      ctrlPressed = false
   end
end

p:start('full loop','fps')
loadFilenames()
loadImage()
p:lap('full loop')
p:printAll()
widget.windowTitle = 'Floorplan ' .. index
--filenames[index]
widget:show()
local listenerFloorplan = qt.QtLuaListener(widget.frameFloorplan)
local listenerAnnotation = qt.QtLuaListener(widget.frameAnnotation)
local listenerGlobal = qt.QtLuaListener(widget)
--print(listener)

qt.connect(listenerFloorplan,
           'sigMousePress(int, int, QByteArray, QByteArray, QByteArray)',
           mousePressEvent
)
qt.connect(listenerFloorplan,
	   'sigMouseRelease(int, int, QByteArray, QByteArray, QByteArray)',
	   mouseReleaseEvent
)
qt.connect(listenerFloorplan,
	   'sigMouseMove(int, int, QByteArray, QByteArray)',
	   mouseMoveEvent
)


qt.connect(listenerAnnotation,
           'sigMousePress(int, int, QByteArray, QByteArray, QByteArray)',
           mousePressEvent
)
qt.connect(listenerAnnotation,
           'sigMouseRelease(int, int, QByteArray, QByteArray, QByteArray)',
           mouseReleaseEvent
)
qt.connect(listenerAnnotation,
           'sigMouseMove(int, int, QByteArray, QByteArray)',
           mouseMoveEvent
)

qt.connect(listenerGlobal,
           'sigKeyPress(QString, QByteArray, QByteArray)', keyPressEvent)
qt.connect(listenerGlobal,
           'sigKeyRelease(QString, QByteArray, QByteArray)', keyReleaseEvent)
