local optim = require 'optim'
local image = require 'image'
local display = require 'display'
display.configure({hostname='127.0.0.1', port=8000})

local M = {}
local Trainer = torch.class('matching.Trainer', M)

function Trainer:__init(model, criterion, opt, optimState)
   self.model = model
   
   self.criterion = criterion
   self.optimState = optimState or {
      learningRate = opt.LR,
      learningRateDecay = 0.0,
      momentum = opt.momentum,
      nesterov = true,
      dampening = 0.0,
      weightDecay = opt.weightDecay,
                                   }
   self.opt = opt
   self.params, self.gradParams = self.model:getParameters()
   
   if opt.useCheckpoint then
      self.logger = {
         train = io.open(paths.concat(opt.resume, 'train.log'), 'a+'),
         val = io.open(paths.concat(opt.resume, 'test.log'), 'a+')
      }
   else
      self.logger = {
         train = io.open(paths.concat(opt.resume, 'train.log'), 'w'),
         val = io.open(paths.concat(opt.resume, 'test.log'), 'w')
      }
   end


   self.scale = 10
   
   self.colorMap = torch.randn(51, 3):totable()

   self.splitPoints = {0, 13, 17, 21, 32, 34, 44, 50, 51}
end

function Trainer:train(epoch, dataloader)
   -- Trains the model for a single epoch
   self.optimState.learningRate = self:learningRate(epoch)
   
   local timer = torch.Timer()
   local dataTimer = torch.Timer()
   
   local function feval()
      return self.criterion.output, self.gradParams
   end
   
   local trainSize = dataloader:size()
   local lossSum = 0.0
   local N = 0
   local correctSums = torch.zeros(10):totable()
   local sampleSums = torch.zeros(10):totable()
   local checkedResultIndex = 1
   
   print('=> Training epoch # ' .. epoch)
   -- set the batch norm to training mode
   self.model:training()
   for n, sample in dataloader:run() do
      local dataTime = dataTimer:time().real
      
      -- Copy input and target to the GPU
      self:copyInputs(sample)

      local output = self.model:forward(self.input)
      --self.model.output[self.ignoreMask] = self.target[self.ignoreMask]
      local loss = self.criterion:forward(self.model.output, self.target)
      self.model:zeroGradParameters()
      self.criterion:backward(self.model.output, self.target)
      --print(self.criterion.gradInput)
      --self.criterion.gradInput[self.ignoreMask] = 0
      self.model:backward(self.input, self.criterion.gradInput)
      --self.model.modules[1]:zeroGradParameters()
      
      --if self.opt.visIter > 0 and n % self.opt.visIter == 0 then
      --display.image(self.input[1][1], {win='floorplan', title='floorplan'})
      --display.image(self.input[2][1], {win='image', title='image'})
      --end
      
      
      optim.sgd(feval, self.params, self.optimState)
      
      lossSum = lossSum + loss
      N = N + 1
      

      local prob, pred_1 = torch.max(self.model.output[2]:double(), 2)            
      pred_1 = pred_1[{{}, 1}]
      local prob, pred_2 = torch.max(self.model.output[3]:double(), 2)            
      pred_2 = pred_2[{{}, 1}]
      
      if (n - 1) % 100 == 0 and true then

	 --print(torch.cat(self.model.output[1][1][self.target[1][1]:gt(5)], self.target[1][1][self.target[1][1]:gt(5)], 2))
	 
         checkedResultIndex = 1
         --for batchIndex = 1, (#self.input)[1] do
	 local segmentationTarget_1 = self.segmentationTarget_1:view(self.input:size(1), self.opt.sampleDim, self.opt.sampleDim):double()
	 local segmentationTarget_2 = self.segmentationTarget_2:view(self.input:size(1), self.opt.sampleDim, self.opt.sampleDim):double()
	 
	 local prediction_1 = pred_1:view(self.input:size(1), self.opt.sampleDim, self.opt.sampleDim):double()
	 local prediction_2 = pred_2:view(self.input:size(1), self.opt.sampleDim, self.opt.sampleDim):double()
	 
         for batchIndex = 1, self.input:size(1) do
            local floorplan = dataloader.dataset:postprocess()(self.input[batchIndex]:double())
            image.save(self.opt.tmp .. '/floorplan_' .. checkedResultIndex .. '.png', floorplan[{{1, 3}}])
            
            for c = 1, 3 do
               local target = self.heatmapTarget:narrow(2, self.splitPoints[c] + 1, self.splitPoints[c + 1] - self.splitPoints[c])
	       
               local mask = torch.zeros(self.opt.sampleDim, self.opt.sampleDim)
               --print(#target)
               --print(#mask)
               for label = 1, target:size(2) do
                  mask[target[batchIndex][label]:double():gt(self.scale / 2)] = label
               end
               image.save(self.opt.tmp .. '/target_' .. checkedResultIndex .. '_' .. c .. '.png', fp_ut.drawSegmentation(mask, nil, self.colorMap))

	       
               local prediction = self.model.output[1]:narrow(2, self.splitPoints[c] + 1, self.splitPoints[c + 1] - self.splitPoints[c])
               local mask = torch.zeros(self.opt.sampleDim, self.opt.sampleDim)
               for label = 1, prediction:size(2) do
                  mask[prediction[batchIndex][label]:double():gt(self.scale / 2)] = label
               end
               image.save(self.opt.tmp .. '/prediction_' .. checkedResultIndex .. '_' .. c .. '.png', fp_ut.drawSegmentation(mask, nil, self.colorMap))
            end

	    local mask = torch.zeros(self.opt.sampleDim, self.opt.sampleDim)
            --print(#target)
            --print(#mask)
	    image.save(self.opt.tmp .. '/target_' .. checkedResultIndex .. '_' .. 4 .. '.png', fp_ut.drawSegmentation(segmentationTarget_1[batchIndex], nil, self.colorMap))        
            image.save(self.opt.tmp .. '/prediction_' .. checkedResultIndex .. '_' .. 4 .. '.png', fp_ut.drawSegmentation(prediction_1[batchIndex], nil, self.colorMap))
	    image.save(self.opt.tmp .. '/target_' .. checkedResultIndex .. '_' .. 5 .. '.png', fp_ut.drawSegmentation(segmentationTarget_2[batchIndex], nil, self.colorMap))        
            image.save(self.opt.tmp .. '/prediction_' .. checkedResultIndex .. '_' .. 5 .. '.png', fp_ut.drawSegmentation(prediction_2[batchIndex], nil, self.colorMap))
            
            checkedResultIndex = checkedResultIndex + 1
         end
      end


      if true then
         for c = 1, 3 do
            local target = self.heatmapTarget:narrow(2, self.splitPoints[c] + 1, self.splitPoints[c + 1] - self.splitPoints[c]):double()
            local prediction = self.model.output[1]:narrow(2, self.splitPoints[c] + 1, self.splitPoints[c + 1] - self.splitPoints[c]):double()
            --local ignoreMask = self.ignoreMask:narrow(2, self.splitPoints[c] + 1, self.splitPoints[c + 1] - self.splitPoints[c])
            local nonzeroMask = target:gt(self.scale / 2)

            local sampleIndices = (nonzeroMask):nonzero()
            if ##sampleIndices > 0 then
               local correctIndices = torch.cmul(torch.cmul(prediction - self.scale / 2, target - self.scale / 2):gt(0), nonzeroMask):nonzero()
               if ##correctIndices > 0 then    
                  correctSums[c] = correctSums[c] + correctIndices:size(1)     
               end
               sampleSums[c] = sampleSums[c] + sampleIndices:size(1)     
            end
            
            local sampleIndices = (1 - nonzeroMask):nonzero()
            if ##sampleIndices > 0 then
               local correctIndices = torch.cmul(torch.cmul(prediction - self.scale / 2, target - self.scale / 2):gt(0), 1 - nonzeroMask):nonzero()
               if ##correctIndices > 0 then    
                  correctSums[7 + c] = correctSums[7 + c] + correctIndices:size(1)     
               end
               sampleSums[7 + c] = sampleSums[7 + c] + sampleIndices:size(1)     
            end
         end


	 local sampleIndices = self.segmentationTarget_1:double():nonzero()
	 if ##sampleIndices > 0 then
	    local correctIndices = (pred_1 - self.segmentationTarget_1:long()):eq(0):nonzero()
	    if ##correctIndices > 0 then
	       correctSums[4] = correctSums[4] + correctIndices:size(1)
            end
            sampleSums[4] = sampleSums[4] + sampleIndices:size(1)
	 end
         local sampleIndices_2 = self.segmentationTarget_2:double():nonzero()
         if ##sampleIndices > 0 then
            local correctIndices = (pred_2 - self.segmentationTarget_2:long()):eq(0):nonzero()
            if ##correctIndices > 0 then
               correctSums[5] = correctSums[5] + correctIndices:size(1)
            end
            sampleSums[5] = sampleSums[5] + sampleIndices:size(1)
         end
         -- local correctMask = (pred - self.segmentationTarget:long()):eq(0)
         -- for c = 4, 7 do
         --    local minSegmentIndex = self.splitPoints[c] + 1 - 21
         --    local maxSegmentIndex = self.splitPoints[c + 1] - 21
         --    local targetMask = torch.cmul(self.segmentationTarget:ge(minSegmentIndex), self.segmentationTarget:le(maxSegmentIndex)):byte()
	    --    local sampleIndices = targetMask:nonzero()
         --    if ##sampleIndices > 0 then
         --       local correctIndices = torch.cmul(correctMask, targetMask):nonzero()
         --       if ##correctIndices > 0 then
	       --          correctSums[c] = correctSums[c] + correctIndices:size(1)
         --       end
	       --       sampleSums[c] = sampleSums[c] + sampleIndices:size(1)
         --    end
         -- end
      end


      local loss_1 = self.criterion.criterions[1]:forward(self.model.output[1], self.target[1])
      local loss_2 = self.criterion.criterions[2]:forward(self.model.output[2], self.target[2])
      local loss_3 = self.criterion.criterions[3]:forward(self.model.output[3], self.target[3])
      
      local log = ('Epoch: [%d][%d/%d] Time %.3f Data %.3f Err %1.4f Err %1.4f Err %1.4f Err %1.4f')
         :format(epoch, n, trainSize, timer:time().real, dataTime, loss, loss_1, loss_2, loss_3)
      --self.logger.train:write(log .. '\n')
      ut.progress(n, trainSize, log)
      
      -- check that the storage didn't get changed do to an unfortunate getParameters call
      assert(self.params:storage() == self.model:parameters()[1]:storage())
      
      timer:reset()
      dataTimer:reset()
   end

   local log = (' * Finished epoch # %d     Err %1.4f    Acc %1.4f    Acc %1.4f    Acc %1.4f    Acc %1.4f    Acc %1.4f    Acc %1.4f    Acc %1.4f    Acc %1.4f\n'):format(epoch, lossSum / N, correctSums[1] / sampleSums[1], correctSums[8] / sampleSums[8], correctSums[2] / sampleSums[2], correctSums[9] / sampleSums[9], correctSums[3] / sampleSums[3], correctSums[10] / sampleSums[10], correctSums[4] / sampleSums[4], correctSums[5] / sampleSums[5])
   
   --self.logger.train:write(log .. '\n')
   print(log)
   return lossSum / N
end

function Trainer:test(epoch, dataloader)
   -- Computes the top-1 and top-5 err on the validation set

   local timer = torch.Timer()
   local dataTimer = torch.Timer()
   local size = dataloader:size()
   
   local lossSum = 0.0
   local N = 0
   
   local correctSum = 0.0
   local sampleSum = 0

   local correctSums = torch.zeros(10):totable()   
   local sampleSums = torch.zeros(10):totable()
   local numBatches = math.ceil(size / self.opt.numFolds)

   local checkedResultIndex = 1
   self.model:evaluate()
   for n, sample in dataloader:run() do
      local dataTime = dataTimer:time().real
      
      -- Copy input and target to the GPU
      self:copyInputs(sample)
      local output = self.model:forward(self.input)
      --self.model.output[self.ignoreMask] = self.target[self.ignoreMask]
      local loss = self.criterion:forward(self.model.output, self.target)

      --[[
      print(loss)
      print(torch.min(self.target[2]))
      print(torch.max(self.target[2]))
	 print(torch.min(self.target[3]))
      print(torch.max(self.target[3]))
      print(torch.min(self.model.output[2]))      
      print(torch.max(self.model.output[2]))      
      print(torch.min(self.model.output[3]))      
      print(torch.max(self.model.output[3]))
      ]]--
      lossSum = lossSum + loss
      N = N + 1
      


      local prob, pred_1 = torch.max(self.model.output[2]:double(), 2)            
      pred_1 = pred_1[{{}, 1}]
      local prob, pred_2 = torch.max(self.model.output[3]:double(), 2)            
      pred_2 = pred_2[{{}, 1}]
      
      if (n - 1) % 100 == 0 and true then

         --print(torch.cat(self.model.output[1][1][self.target[1][1]:gt(5)], self.target[1][1][self.target[1][1]:gt(5)], 2))
         
         checkedResultIndex = 1
         --for batchIndex = 1, (#self.input)[1] do
         local segmentationTarget_1 = self.segmentationTarget_1:view(self.input:size(1), self.opt.sampleDim, self.opt.sampleDim):double()
         local segmentationTarget_2 = self.segmentationTarget_2:view(self.input:size(1), self.opt.sampleDim, self.opt.sampleDim):double()
         
         local prediction_1 = pred_1:view(self.input:size(1), self.opt.sampleDim, self.opt.sampleDim):double()
         local prediction_2 = pred_2:view(self.input:size(1), self.opt.sampleDim, self.opt.sampleDim):double()


         for batchIndex = 1, self.input:size(1) do
            local floorplan = dataloader.dataset:postprocess()(self.input[batchIndex]:double())
	    image.save(self.opt.tmp .. '/floorplan_' .. checkedResultIndex .. '.png', floorplan[{{1, 3}}])

            if batchIndex == 1 and false then
	       for c = 1, 13 do
		  print(torch.max(self.model.output[1][batchIndex][c]))
		  image.save(self.opt.tmp .. '/target_wall_' .. c .. '.png', self.target[1][batchIndex][c]:double() / 10)
		  image.save(self.opt.tmp .. '/prediction_wall_' .. c .. '.png', self.model.output[1][batchIndex][c]:double() / 10)
		  
		  --image.save(self.opt.tmp .. '/prediction_threshold_' .. c .. '.png', torch.cmul(self.model.output[1][batchIndex][c]:double(), self.model.output[1][batchIndex][c]:gt(self.scale / 2):double()))
               end
	       
               for c = 1, 4 do
		  local img = floorplan:clone()
		  local target = self.target[1][batchIndex][13 + c]:double()
		  local mask = target:gt(self.scale / 2)
		  img[1][mask]:copy(target[mask])
		  img[2][mask] = 0
		  img[3][mask] = 0
                  image.save(self.opt.tmp .. '/target_door_' .. c .. '.png', img)
		  
		  local img = floorplan:clone()
                  local prediction = self.model.output[1][batchIndex][13 + c]:double()
                  local mask = prediction:gt(self.scale / 2)
                  img[1][mask]:copy(prediction[mask])
                  img[2][mask] = 0
                  img[3][mask] = 0
		  
                  image.save(self.opt.tmp .. '/prediction_door_' .. c .. '.png', img)
                  image.save(self.opt.tmp .. '/prediction_door_threshold_' .. c .. '.png', torch.cmul(self.model.output[1][batchIndex][13 + c]:double(), self.model.output[1][batchIndex][13 + c]:gt(self.scale / 2):double()))
               end
               for c = 1, 4 do
		  local img = floorplan:clone()
                  local target = self.target[1][batchIndex][17 + c]:double()
                  local mask = target:gt(self.scale / 2)
                  img[1][mask]:copy(target[mask])
                  img[2][mask] = 0
                  img[3][mask] = 0
		  
		  image.save(self.opt.tmp .. '/target_object_' .. c .. '.png', img)
                  local img = floorplan:clone()
                  local prediction = self.model.output[1][batchIndex][17 + c]:double()
                  local mask = prediction:gt(self.scale / 2)
                  img[1][mask]:copy(prediction[mask])
                  img[2][mask] = 0
                  img[3][mask] = 0
		  
                  image.save(self.opt.tmp .. '/prediction_object_' .. c .. '.png', img)
		  image.save(self.opt.tmp .. '/prediction_object_threshold_' .. c .. '.png', torch.cmul(self.model.output[1][batchIndex][17 + c]:double(), self.model.output[1][batchIndex][17 + c]:gt(self.scale / 2):double()))
               end
	    end
	    
            for c = 1, 3 do
               local target = self.heatmapTarget:narrow(2, self.splitPoints[c] + 1, self.splitPoints[c + 1] - self.splitPoints[c])
               
               local mask = torch.zeros(self.opt.sampleDim, self.opt.sampleDim)
               --print(#target)
               --print(#mask)
               for label = 1, target:size(2) do
                  mask[target[batchIndex][label]:double():gt(self.scale / 2)] = label
               end
               image.save(self.opt.tmp .. '/target_' .. checkedResultIndex .. '_' .. c .. '.png', fp_ut.drawSegmentation(mask, nil, self.colorMap))

               
               local prediction = self.model.output[1]:narrow(2, self.splitPoints[c] + 1, self.splitPoints[c + 1] - self.splitPoints[c])
               local mask = torch.zeros(self.opt.sampleDim, self.opt.sampleDim)
               for label = 1, prediction:size(2) do
                  mask[prediction[batchIndex][label]:double():gt(self.scale / 2)] = label
               end
               image.save(self.opt.tmp .. '/prediction_' .. checkedResultIndex .. '_' .. c .. '.png', fp_ut.drawSegmentation(mask, nil, self.colorMap))
            end

            local mask = torch.zeros(self.opt.sampleDim, self.opt.sampleDim)
            --print(#target)
            --print(#mask)
            image.save(self.opt.tmp .. '/target_' .. checkedResultIndex .. '_' .. 4 .. '.png', fp_ut.drawSegmentation(segmentationTarget_1[batchIndex], nil, self.colorMap))        
            image.save(self.opt.tmp .. '/prediction_' .. checkedResultIndex .. '_' .. 4 .. '.png', fp_ut.drawSegmentation(prediction_1[batchIndex], nil, self.colorMap))
            image.save(self.opt.tmp .. '/target_' .. checkedResultIndex .. '_' .. 5 .. '.png', fp_ut.drawSegmentation(segmentationTarget_2[batchIndex], nil, self.colorMap))        
            image.save(self.opt.tmp .. '/prediction_' .. checkedResultIndex .. '_' .. 5 .. '.png', fp_ut.drawSegmentation(prediction_2[batchIndex], nil, self.colorMap))
            
            checkedResultIndex = checkedResultIndex + 1
	    --os.exit(1)
         end
      end


      if true then
         for c = 1, 3 do
            local target = self.heatmapTarget:narrow(2, self.splitPoints[c] + 1, self.splitPoints[c + 1] - self.splitPoints[c]):double()
            local prediction = self.model.output[1]:narrow(2, self.splitPoints[c] + 1, self.splitPoints[c + 1] - self.splitPoints[c]):double()
            --local ignoreMask = self.ignoreMask:narrow(2, self.splitPoints[c] + 1, self.splitPoints[c + 1] - self.splitPoints[c])
            local nonzeroMask = target:gt(self.scale / 2)

            local sampleIndices = (nonzeroMask):nonzero()
            if ##sampleIndices > 0 then
               local correctIndices = torch.cmul(torch.cmul(prediction - self.scale / 2, target - self.scale / 2):gt(0), nonzeroMask):nonzero()
               if ##correctIndices > 0 then    
                  correctSums[c] = correctSums[c] + correctIndices:size(1)     
               end
               sampleSums[c] = sampleSums[c] + sampleIndices:size(1)     
            end
            
            local sampleIndices = (1 - nonzeroMask):nonzero()
            if ##sampleIndices > 0 then
               local correctIndices = torch.cmul(torch.cmul(prediction - self.scale / 2, target - self.scale / 2):gt(0), 1 - nonzeroMask):nonzero()
               if ##correctIndices > 0 then    
                  correctSums[7 + c] = correctSums[7 + c] + correctIndices:size(1)     
               end
               sampleSums[7 + c] = sampleSums[7 + c] + sampleIndices:size(1)     
            end
         end


         local sampleIndices = self.segmentationTarget_1:double():nonzero()
         if ##sampleIndices > 0 then
            local correctIndices = (pred_1 - self.segmentationTarget_1:long()):eq(0):nonzero()
            if ##correctIndices > 0 then
               correctSums[4] = correctSums[4] + correctIndices:size(1)
            end
            sampleSums[4] = sampleSums[4] + sampleIndices:size(1)
         end
         local sampleIndices_2 = self.segmentationTarget_2:double():nonzero()
         if ##sampleIndices > 0 then
            local correctIndices = (pred_2 - self.segmentationTarget_2:long()):eq(0):nonzero()
            if ##correctIndices > 0 then
               correctSums[5] = correctSums[5] + correctIndices:size(1)
            end
            sampleSums[5] = sampleSums[5] + sampleIndices:size(1)
         end
         -- local correctMask = (pred - self.segmentationTarget:long()):eq(0)
         -- for c = 4, 7 do
         --    local minSegmentIndex = self.splitPoints[c] + 1 - 21
         --    local maxSegmentIndex = self.splitPoints[c + 1] - 21
         --    local targetMask = torch.cmul(self.segmentationTarget:ge(minSegmentIndex), self.segmentationTarget:le(maxSegmentIndex)):byte()
         --    local sampleIndices = targetMask:nonzero()
         --    if ##sampleIndices > 0 then
         --       local correctIndices = torch.cmul(correctMask, targetMask):nonzero()
         --       if ##correctIndices > 0 then
         --          correctSums[c] = correctSums[c] + correctIndices:size(1)
         --       end
         --       sampleSums[c] = sampleSums[c] + sampleIndices:size(1)
         --    end
         -- end
      end

      
      if n % numBatches == 0 or n == size then
         table.insert(correctSums, correctSum)
         table.insert(sampleSums, sampleSum)
      end      

      local loss_1 = self.criterion.criterions[1]:forward(self.model.output[1], self.target[1])
      local loss_2 = self.criterion.criterions[2]:forward(self.model.output[2], self.target[2])
      local loss_3 = self.criterion.criterions[3]:forward(self.model.output[3], self.target[3])
      
      local log = ('Test: [%d][%d/%d] Time %.3f Data %.3f Err %1.4f Err %1.4f Err %1.4f Err %1.4f')      
         :format(epoch, n, size, timer:time().real, dataTime, loss, loss_1, loss_2, loss_3)
      --local log = ('Test: [%d][%d/%d] Time %.3f Data %.3f Err %1.4f')
      --:format(epoch, n, size, timer:time().real, dataTime, loss)
      --self.logger.val:write(log .. '\n')
      ut.progress(n, size, log)
      
      timer:reset()
      dataTimer:reset()
   end
   self.model:training()

   local log = (' * Finished epoch # %d     Err %1.4f    Acc %1.4f    Acc %1.4f    Acc %1.4f    Acc %1.4f    Acc %1.4f    Acc %1.4f    Acc %1.4f    Acc %1.4f\n'):format(epoch, lossSum / N, correctSums[1] / sampleSums[1], correctSums[8] / sampleSums[8], correctSums[2] / sampleSums[2], correctSums[9] / sampleSums[9], correctSums[3] / sampleSums[3], correctSums[10] / sampleSums[10], correctSums[4] / sampleSums[4], correctSums[5] / sampleSums[5])
   
   --self.logger.val:write(log .. '\n')
   print(log)
   
   return lossSum / N
end

function Trainer:copyInputs(sample)
   -- Copies the input to a CUDA tensor, if using 1 GPU, or to pinned memory,
   -- if using DataParallelTable. The target is always copied to a CUDA tensor
   self.floorplanInput = self.floorplanInput or (self.opt.nGPU == 1         
                                                    and torch.CudaTensor()         
                                                    or cutorch.createCudaHostTensor())
   self.representationInput = self.representationInput or (self.opt.nGPU == 1         
                                                              and torch.CudaTensor()         
                                                              or cutorch.createCudaHostTensor())
   
   self.floorplanInput:resize(sample.floorplanInput:size()):copy(sample.floorplanInput)

   self.representationInput:resize(sample.representationInput:size()):copy(sample.representationInput)


   --[[
   local nonzeroMask = self.heatmapTarget:double():gt(0)
   self.ignoreMask = 1 - nonzeroMask
   for shuffle = 1, 4 do
      for i = 1, self.ignoreMask:size(2) do
         local mask = self.ignoreMask[{{}, i, {}, {}}]:contiguous():view(-1)
         mask:copy(mask:index(1, torch.randperm(mask:size(1)):long()))
         self.ignoreMask[{{}, i, {}, {}}]:copy(mask)
      end
      self.ignoreMask[nonzeroMask] = 0
   end
   ]]--
   
   -- self.weights = torch.zeros(self.ignoreMask:size(2))
   -- for i = 1, self.ignoreMask:size(2) do
   --    local indices = self.ignoreMask[{{}, i, {}, {}}]:eq(0):nonzero()
   --    if ##indices > 0 then
   --       self.weights[i] = 1.0 / indices:size(1)
   --    end
   -- end
   
   
   --[[
      local numNonzeroPixels = self.representationInput:double():nonzero():size(1)
      local numZeroPixels = self.ignoreMask:nonzero():size(1)
      if numNonzeroPixels < numZeroPixels then
      local sample = torch.randperm(numZeroPixels):narrow(1, 1, numNonzeroPixels):long()
      local sampledNonobjectIndices = self.ignoreMask:nonzero():index(1, sample)
      for i = 1, (#sampledNonobjectIndices)[1] do 
      self.ignoreMask[torch.totable(sampledNonobjectIndices[i])] = 0
      end
      end
   ]]--

   self.heatmapTarget = self.representationInput:narrow(2, 1, 21)
   self.segmentationTarget_1 = self.representationInput:narrow(2, 22, 1)
   self.segmentationTarget_2 = self.representationInput:narrow(2, 23, 1)
   self.segmentationTarget_1[self.segmentationTarget_1:eq(0)] = 11

   --image.save('test/mask.png', self.segmentationTarget_1[1]:eq(11):double())
   
   self.heatmapTarget = self.heatmapTarget * self.scale
   self.segmentationTarget_1 = self.segmentationTarget_1:contiguous():view(-1)
   self.segmentationTarget_2 = self.segmentationTarget_2:contiguous():view(-1)
   self.segmentationTarget_2[self.segmentationTarget_2:eq(0)] = 17
   
   self.input = self.floorplanInput
   self.target = {self.heatmapTarget, self.segmentationTarget_1, self.segmentationTarget_2}
   self.indices = sample.indices
end

function Trainer:learningRate(epoch)
   -- Training schedule
   local decay = 0   
   return self.opt.LR * math.pow(0.1, decay)
end

return M.Trainer
