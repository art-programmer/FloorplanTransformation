local image = require 'image'
local paths = require 'paths'
local t = require 'datasets/transformsRepresentation'
local tBoth = require 'datasets/transformsBoth'
local ffi = require 'ffi'
package.path = '../util/lua/?.lua;' .. package.path
local fp_ut = require 'floorplan_utils'

local M = {}
local FloorplanDataset = torch.class('FloorplanDataset', M)

function FloorplanDataset:__init(imageInfo, opt, split)
   self.imageInfo = imageInfo[split]
   if split == 'train' then
      self.imageInfo.floorplanPaths = self.imageInfo.floorplanPaths:repeatTensor(opt.nRepetitionsPerEpochTrain, 1)            
      self.imageInfo.representationPaths = self.imageInfo.representationPaths:repeatTensor(opt.nRepetitionsPerEpochTrain, 1)
   else
      self.imageInfo.floorplanPaths = self.imageInfo.floorplanPaths:repeatTensor(opt.nRepetitionsPerEpochTest, 1)      
      self.imageInfo.representationPaths = self.imageInfo.representationPaths:repeatTensor(opt.nRepetitionsPerEpochTest, 1)
   end
   self.opt = opt
   self.split = split
   self.dir = paths.concat(opt.data)
   --self.numberMap = fp_ut.numberMap()
   assert(paths.dirp(self.dir), 'directory does not exist: ' .. self.dir)
end

function FloorplanDataset:get(i)
   local floorplanPath = ffi.string(self.imageInfo.floorplanPaths[i]:data())   
   local floorplan = image.load(floorplanPath, 3)
   local representationPath = ffi.string(self.imageInfo.representationPaths[i]:data())
   local representation = fp_ut.loadRepresentation(representationPath)
   return {
      floorplanInput = floorplan,
      representationInput = representation,
   }
end

function FloorplanDataset:getPatches(i)
   local floorplanPath = ffi.string(self.imageInfo.floorplanPaths[i]:data())   
   local floorplan = image.load(floorplanPath, 3)
   local representationPath = ffi.string(self.imageInfo.representationPaths[i]:data())
   local representation = fp_ut.loadRepresentation(representationPath)
   
   local patches = {}
   local patchLabels = {}
   local patchOrientations = {}
   local width = floorplan:size(3)
   local height = floorplan:size(2)
   for mode, items in pairs(representation) do
      if mode == 'doors' then
	 for _, item in pairs(items) do  
            local centerX = (item[1][1] + item[2][1]) / 2        
            local centerY = (item[1][2] + item[2][2]) / 2        
            local dim = math.max(math.abs(item[1][1] - item[2][1]), math.abs(item[1][2] - item[2][2])) * 2       
            local minX = math.max(centerX - dim / 2, 1)                  
            local maxX = math.min(centerX + dim / 2, width)      
            local minY = math.max(centerY - dim / 2, 1)                  
            local maxY = math.min(centerY + dim / 2, height)     
	    local patch = image.crop(floorplan, minX, minY, maxX, maxY)  
            --local patch = image.scale(patch, self.opt.patchDim, self.opt.patchDim):view(1, 1, 1, 1)
	    table.insert(patches, patch)    
            table.insert(patchLabels, fp_ut.getNumber(mode, item[3]))
	    table.insert(patchOrientations, item[3][3])
         end
      elseif mode == 'icons' then
	 for _, item in pairs(items) do
            local centerX = (item[1][1] + item[2][1]) / 2        
            local centerY = (item[1][2] + item[2][2]) / 2        
            local dim = math.max(math.abs(item[1][1] - item[2][1]), math.abs(item[1][2] - item[2][2])) * 2       
            local minX = math.max(math.min(item[1][1], item[2][1]), 1)
            local maxX = math.min(math.max(item[1][1], item[2][1]), width)
            local minY = math.max(math.min(item[1][2], item[2][2]), 1)                  
            local maxY = math.min(math.max(item[1][2], item[2][2]), height)
            local patch = image.crop(floorplan, minX, minY, maxX, maxY)
	    table.insert(patches, patch)
            table.insert(patchLabels, fp_ut.getNumber(mode, item[3]) + 11)
	    table.insert(patchOrientations, item[3][3])
         end
      end
      
   end
      
   --print(#floorplan)
   return {
      --floorplanInput = floorplan,
      --representationInput = representation,
      patchesInput = patches,
      patchLabelsInput = patchLabels,
      patchOrientationsInput = patchOrientations
   }
end

function FloorplanDataset:size()
   return self.imageInfo.floorplanPaths:size(1)
end

-- Computed from random subset of Imagenet training images
local meanstd = {
   mean = { 0.5, 0.5, 0.5, 0 },
   std = { 0.5, 0.5, 0.5, 1 },
}
local pca = {
   eigval = torch.Tensor{ 0.2175, 0.0188, 0.0045 },
   eigvec = torch.Tensor{
      { -0.5675,  0.7192,  0.4009 },
      { -0.5808, -0.0045, -0.8140 },
      { -0.5836, -0.6948,  0.4203 },
   },
}

function FloorplanDataset:preprocessRepresentation(dim, scaleProb, interpolation)
   local scaleProb = scaleProb or 1
   local interpolation = interpolation or 'bicubic'
   local transforms = {}
   table.insert(transforms, t.ScaleOrCrop(dim, scaleProb, interpolation))
   -- if torch.uniform() <= scaleProb then
   --    --table.insert(transforms, t.Resize(dim, dim, interpolation))
   --    table.insert(transforms, t.Scale(dim, interpolation))
   --    table.insert(transforms, t.Pad(dim))
   --    table.insert(transforms, t.CenterCrop(dim))
   -- else
   --    table.insert(transforms, t.RandomCrop(dim, dim / 2))
   -- end
   if self.split == 'train' then
      table.insert(transforms, t.Rotate())
      if self.opt.useColorJitter then
	 table.insert(transforms, t.ColorJitter({
			    brightness = 0.4,
			    contrast = 0.4,
			    saturation = 0.4,
	 }))
      end
   end
   table.insert(transforms, t.ColorNormalize(meanstd))
   
   return t.Compose(transforms)
end

function FloorplanDataset:preprocessBoth(dim, scaleProb, outputDim)
   local scaleProb = scaleProb or 1
   local interpolation = interpolation or 'bicubic'
   local transforms = {}
   if torch.uniform() <= scaleProb then
      table.insert(transforms, tBoth.Scale(dim, interpolation))
      table.insert(transforms, tBoth.Pad(dim))
      table.insert(transforms, tBoth.CenterCrop(dim))
   else
      table.insert(transforms, tBoth.RandomCrop(dim, dim / 2))
   end

   --table.insert(transforms, tBoth.Rotate())
   if self.opt and self.opt.useColorJitter then
      table.insert(transforms, tBoth.ColorJitter({
                         brightness = 0.4,
                         contrast = 0.4,
                         saturation = 0.4,
      }))
   end
   table.insert(transforms, tBoth.ColorNormalize(meanstd))

   if outputDim then
      table.insert(transforms, tBoth.ScaleSecond(outputDim, 'simple'))
   end
   
   return tBoth.Compose(transforms)

   --[[
   local transforms = denotedTransforms or {   
      tBoth.Resize(loadSize, loadSize, 'bicubic'),         
      tBoth.RandomCrop(sampleSize),         
      tBoth.ColorNormalize(meanstd),   
					   }
      if self.split == 'train' then
      table.insert(transforms, tBoth.HorizontalFlip(0.5))
   end
   
      return tBoth.Compose(transforms)
   --]]--
end

function FloorplanDataset:preprocessResize(width, height)
   local interpolation = interpolation or 'bicubic'
   local transforms = {}
   table.insert(transforms, tBoth.Resize(width, height, interpolation))
   table.insert(transforms, tBoth.ColorNormalize(meanstd))
   
   return tBoth.Compose(transforms)
end

function FloorplanDataset:preprocessScale(dim, interpolation)
   local interpolation = interpolation or 'bicubic'
   local transforms = {}
   table.insert(transforms, t.Scale(dim, interpolation))
   table.insert(transforms, tBoth.ColorNormalize(meanstd))
   
   return tBoth.Compose(transforms)
end

function FloorplanDataset:preprocessNormalization()
   local transforms = {}
   table.insert(transforms, tBoth.ColorNormalize(meanstd))
   
   return tBoth.Compose(transforms)
end

function FloorplanDataset:postprocess()
   return t.Compose{
      t.ColorUnnormalize(meanstd),
   }
end

function FloorplanDataset:convertRepresentation(sampleDim, gridDim, lineWidth)
   return function(floorplan, representation)   
      local representationGlobal = fp_ut.convertRepresentation(sampleDim, sampleDim, representation, 'P', lineWidth)   
      return fp_ut.convertRepresentationToTensor(sampleDim, sampleDim, gridDim, gridDim, representationGlobal)   
   end
end

function FloorplanDataset:convertRepresentationIcon(sampleDim, gridDim, lineWidth)
   return function(floorplan, representation)
      return fp_ut.getIconTensor(sampleDim, sampleDim, representation)   
   end
end

function FloorplanDataset:convertRepresentationPatch(opt, mode, regression, numLabels)
   return function(floorplan, representation, head)   
      return fp_ut.getPatch(floorplan, representation, opt, mode, head, regression, numLabels)
   end
end

function FloorplanDataset:convertRepresentationPatchGrid(opt, mode, regression, numLabels)
   return function(floorplan, representation, head)
      return fp_ut.getPatchGrid(floorplan, representation, opt, mode, head, regression, numLabels)
   end
end

function FloorplanDataset:convertRepresentationImage(sampleDim, gridDim, lineWidth)
   return function(floorplan, representation, matchingLabel)   
      local representationGlobal = fp_ut.convertRepresentation(sampleDim, sampleDim, representation, 'P', lineWidth)
      if matchingLabel == 0 then
	 local numDroppedPoints = torch.random(math.min(3, #representationGlobal.points))
	 for i = 1, numDroppedPoints do
	    local pointIndex = torch.random(#representationGlobal.points)
	    table.remove(representationGlobal.points, pointIndex)
	 end
      end
      local representationImage =  fp_ut.drawRepresentationImage(sampleDim, sampleDim, gridDim, gridDim, floorplan, representationGlobal, 'P', 'L', lineWidth)
      return (representationImage[1] + representationImage[2] + representationImage[3]) / 3
   end
end

function FloorplanDataset:convertRepresentationAnchor(sampleDim, gridDim, lineWidth)
   return function(floorplan, representation)   
      local representationGlobal = fp_ut.convertRepresentation(sampleDim, sampleDim, representation, 'P', lineWidth)   
      return fp_ut.convertRepresentationToTensorAnchor(sampleDim, sampleDim, gridDim, gridDim, representationGlobal)   
   end
end

function FloorplanDataset:convertRepresentationHeatmap(sampleDim, gridDim, lineWidth)
   return function(floorplan, representation)
      local representationGlobal = fp_ut.convertRepresentation(sampleDim, sampleDim, representation, 'P', lineWidth)   
      return fp_ut.getJunctionHeatmap(sampleDim, sampleDim, representationGlobal)
   end
end

--[[
function FloorplanDataset:convertRepresentationJunctionAll(sampleDim, gridDim, lineWidth)
   return function(floorplan, representation)
      return fp_ut.getHeatmaps(floorplan:size(3), floorplan:size(2), representation, lineWidth)
      --return fp_ut.convertRepresentationToTensorHeatmap(sampleDim, sampleDim, representationGlobal)
   end
end
]]--

function FloorplanDataset:convertRepresentationHeatmaps(mode, lineWidth, styless, includeSegmentation, segmentationHeatmap)
   return function(floorplan, representation)
      local width, height = floorplan:size(3), floorplan:size(2)
      local heatmaps
      if not styless then
	 heatmaps = fp_ut.getHeatmaps(width, height, representation, lineWidth)
	 if mode == 'points' then
	    heatmaps = heatmaps:narrow(1, 1, 13)
	 elseif mode == 'doors' then
	    heatmaps = heatmaps:narrow(1, 13 + 1, 13 * 4)
	 elseif mode == 'icons' then
	    heatmaps = heatmaps:narrow(1, 13 * 5 + 1, 13 * 4)
	 end
      else
	 heatmaps = fp_ut.getHeatmapsStyless(width, height, representation, lineWidth)
	 if mode == 'points' then
	    heatmaps = heatmaps:narrow(1, 1, 13)
	 elseif mode == 'doors' then
	    heatmaps = heatmaps:narrow(1, 13 + 1, 4)
	 elseif mode == 'icons' then
	    heatmaps = heatmaps:narrow(1, 13 + 4 + 1, 4)
	 end
      end

      if includeSegmentation then
	 --local segmentation = fp_ut.getSegmentation(width, height, representation, nil, floorplan)
	 local segmentations = fp_ut.getSegmentation(width, height, representation, nil, floorplan, segmentationHeatmap)
	 heatmaps = torch.cat(heatmaps, segmentations, 1)
      end
      return heatmaps
      --return fp_ut.convertRepresentationToTensorHeatmap(sampleDim, sampleDim, representationGlobal)
   end
end

function FloorplanDataset:convertRepresentationWall(sampleDim, gridDim, lineWidth)
   return function(floorplan, representation)
      return fp_ut.drawLineMask(floorplan:size(3), floorplan:size(2), representation.walls, lineWidth)
   end
end

function FloorplanDataset:convertRepresentationDoor(sampleDim, gridDim, lineWidth)
   return function(floorplan, representation)
      return fp_ut.drawDoorMasks(floorplan:size(3), floorplan:size(2), representation.doors, lineWidth - 2)
      --return fp_ut.drawLineMask(floorplan:size(3), floorplan:size(2), representation.walls, lineWidth), fp_ut.drawLineMask(floorplan:size(3), floorplan:size(2), representation.doors, lineWidth - 2)
   end
end

function FloorplanDataset:convertRepresentationAnchorWall(sampleDim, gridDim, lineWidth)
   return function(floorplan, representation)
      local representationGlobal = fp_ut.convertRepresentation(sampleDim, sampleDim, representation, 'P', lineWidth)   
      local anchorMasks = fp_ut.convertRepresentationToTensorHeatmap(sampleDim, sampleDim, representationGlobal)
      local wallMask = fp_ut.drawLineMask(floorplan:size(3), floorplan:size(2), representation.walls, lineWidth)
      return torch.cat(anchorMasks, wallMask:repeatTensor(1, 1, 1), 1)
   end
end

function FloorplanDataset:convertRepresentationRoomJunction(sampleDim, gridDim, lineWidth)
   return function(floorplan, representation)
      local representationGlobal = fp_ut.convertRepresentation(sampleDim, sampleDim, representation, 'P', lineWidth)
      return fp_ut.getRoomJunctions(sampleDim, sampleDim, representationGlobal)
   end
end

function FloorplanDataset:convertRepresentationWallPlacement(sampleDim, gridDim, lineWidth, getHeatmap)
   return function(floorplan, representation)
      return fp_ut.getWallPlacement(sampleDim, sampleDim, representation, lineWidth, 'L', getHeatmap)
   end
end

function FloorplanDataset:convertRepresentationWallDoorMap(sampleDim, gridDim, lineWidth, doorWidth, maxNumWalls)
   return function(floorplan, representation)
      local representationGlobal = fp_ut.convertRepresentation(sampleDim, sampleDim, representation, 'P', lineWidth)
      return fp_ut.attachDoorsOnWalls(sampleDim, sampleDim, representationGlobal, lineWidth, doorWidth, maxNumWalls)
   end
end

function FloorplanDataset:convertRepresentationJunctionPlacement(sampleDim, gridDim, lineWidth, getHeatmap)
   return function(floorplan, representation)
      return fp_ut.getJunctionPlacement(sampleDim, sampleDim, representation, lineWidth, 'L', 7)
   end
end


function FloorplanDataset:getSegmentation()
   return function(floorplan, representation)
      return fp_ut.getSegmentation(floorplan:size(3), floorplan:size(2), representation, nil, floorplan)
   end
end

return M.FloorplanDataset
