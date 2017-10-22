local datasets = require 'datasets/init'
local Threads = require 'threads'
Threads.serialization('threads.sharedserialize')

local M = {}
local DataLoader = torch.class('FloorplanRepresentation.DataLoader', M)

function DataLoader.create(opt)
   -- The train and val loader
   local loaders = {}
   
   for i, split in ipairs{'train', 'val'} do
      local dataset = datasets.create(opt, split)
      loaders[i] = M.DataLoader(dataset, opt, split)
   end
   
   return table.unpack(loaders)
end

function DataLoader:__init(dataset, opt, split)
   local manualSeed = opt.manualSeed
   local function init()
      require('datasets/' .. opt.dataset)
   end
   local function main(idx)
      if manualSeed ~= 0 then
         torch.manualSeed(manualSeed + idx)
      end
      torch.setnumthreads(1)
      _G.dataset = dataset
      --_G.preprocess_1 = dataset:preprocess_1(opt.loadDim, opt.sampleDim)
      --_G.preprocess_2 = dataset:preprocess_2(opt.loadDim, opt.sampleDim)
      _G.preprocessRepresentation = dataset:preprocessRepresentation(opt.sampleDim, opt.scaleProb)
      --_G.preprocessRepresentation = dataset:preprocessBoth(opt.sampleDim, opt.scaleProb)
      _G.convertRepresentation = dataset:convertRepresentationHeatmaps(opt.mode, 5, true, false, false)
      _G.getSegmentation = dataset:getSegmentation()
      --return math.min(dataset:size(), 100000)
      return math.min(dataset:size(), 100000)
   end
   
   local threads, sizes = Threads(opt.nThreads, init, main)
   self.threads = threads
   self.__size = sizes[1][1]
   --self.__size = 3
   self.batchSize = opt.batchSize
   self.dataset = dataset
end

function DataLoader:size()
   return math.ceil(self.__size / self.batchSize)
end

function DataLoader:run()
   local threads = self.threads
   local size, batchSize = self.__size, self.batchSize
   local perm = torch.randperm(size)
   
   local idx, sample = 1, nil
   local function enqueue()
      while idx <= size and threads:acceptsjob() do
         local indices = perm:narrow(1, idx, math.min(batchSize, size - idx + 1))
         --indices:fill(1)
         threads:addjob(
            function(indices)
               local sz = indices:size(1)
               local floorplanBatch, floorplanSize, representationBatch, representationSize
               for i, idx in ipairs(indices:totable()) do
                  local sample = _G.dataset:get(idx, true)
		  
                  local floorplan, representation = sample.floorplanInput, sample.representationInput
		  local segmentation = _G.getSegmentation(floorplan, representation)
		  
                  floorplan = torch.cat(floorplan, segmentation, 1)
		  local floorplan, representation = _G.preprocessRepresentation(floorplan, representation)
		  
                  local representationTensor = _G.convertRepresentation(floorplan, representation)
		  representationTensor = torch.cat(representationTensor, floorplan:narrow(1, 4, 2), 1)
		  floorplan = floorplan:narrow(1, 1, 3)

                  --representationTensor = torch.cat(representationTensor, torch.ones(1, 256, 256), 1)
                  --local kernel = image.gaussian(7)
		  --representationTensor[{{1, 21}}] = image.convolve(representationTensor[{{1, 21}}], kernel, 'same')

                  --representationTensor = representationTensor:gt(0):double()
                  --[[
                     image.save('test/floorplan_after.png', floorplan)
                     for i = 1, heatmaps:size(1) do
                     image.save('test/heatmap_after_' .. i .. '.png', representationTensor[i])
                     end
                     os.exit(1)
                  ]]
                  if not floorplanBatch then
                     floorplanSize = floorplan:size():totable()
                     floorplanBatch = torch.FloatTensor(sz, table.unpack(floorplanSize))
                  end
                  floorplanBatch[i]:copy(floorplan)
                  
                  
                  if not representationBatch then
                     representationSize = representationTensor:size():totable()
                     representationBatch = torch.FloatTensor(sz, table.unpack(representationSize))
                  end
                  representationBatch[i]:copy(representationTensor)
               end
               collectgarbage()
               return {
                  floorplanInput = floorplanBatch:view(sz, table.unpack(floorplanSize)),
                  representationInput = representationBatch:view(sz, table.unpack(representationSize)),
               }
            end,
            function(_sample_)
               sample = _sample_
            end,
            indices,
            self.nCrops
         )
         idx = idx + batchSize
      end
   end
   
   local n = 0
   local function loop()
      enqueue()
      if not threads:hasjob() then
         return nil
      end
      threads:dojob()
      if threads:haserror() then
         threads:synchronize()
      end
      enqueue()
      n = n + 1
      return n, sample
   end

   return loop
end

return M.DataLoader
