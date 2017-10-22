local checkpoint = {}

function checkpoint.latest(opt)
   local latestPath = paths.concat(opt.resume, 'latest.t7')
   if not paths.filep(latestPath) then
      return nil
   end

   print('=> Loading checkpoint ' .. latestPath)
   local latest = torch.load(latestPath)
   local optimState = torch.load(paths.concat(opt.resume, latest.optimFile))

   return latest, optimState
end

function checkpoint.load(opt)
   if opt.useCheckpoint == false then
      return nil
   end
   --print(opt.epochNumber)
   local epoch = opt.epochNumber
   if epoch == 0 then
      return nil
   elseif epoch < 0 then
      -- finding the latest epoch, requiring 'latest.t7'
      return checkpoint.latest(opt)
   end

   local modelFile = 'model_' .. epoch .. '.t7'
   local optimFile = 'optimState_' .. epoch .. '.t7'

   local optimState = torch.load(paths.concat(opt.resume, optimFile))
   local loaded = {
      epoch = epoch,
      modelFile = modelFile,
      optimFile = optimFile,
   }

   return loaded, optimState
end

function checkpoint.save(epoch, model, optimState, bestModel, opt)
   -- Don't save the DataParallelTable for easier loading on other machines
   if torch.type(model) == 'nn.DataParallelTable' then
      model = model:get(1)
   end

   local modelFile = 'model_' .. epoch .. '.t7'
   local optimFile = 'optimState_' .. epoch .. '.t7'

   torch.save(paths.concat(opt.resume, modelFile), model:clearState())
   torch.save(paths.concat(opt.resume, optimFile), optimState)
   torch.save(paths.concat(opt.resume, 'latest.t7'), {
                 epoch = epoch,
                 modelFile = modelFile,
                 optimFile = optimFile,
   })

   if bestModel then
      torch.save(paths.concat(opt.resume, 'model_best.t7'), model:clearState())
   end
end

return checkpoint
