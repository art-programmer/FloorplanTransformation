-- usage example: DATA_ROOT=/path/to/data/ which_direction=BtoA name=expt1 th train.lua
--
-- code derived from https://github.com/soumith/dcgan.torch
--

require 'torch'
require 'nn'
require 'optim'
--util = paths.dofile('../util/util.lua')
require 'image'
--require 'models'



local opts = require 'opts'
local opt = opts.parse(arg)


package.path = '../util/lua/?.lua;' .. package.path
require 'ginit' (opt)
opts.init(opt)

----------------------------------------------------
-- Make directories
require 'paths'
paths.mkdir('../gen')
paths.mkdir('../checkpoint')

----------------------------------------------------
local models = require 'models/init'
local DataLoader = require('models/' .. opt.loaderType .. '-dataloader')
local checkpoints = require 'checkpoints'

----------------------------------------------------
-- Load previous checkpoint, if it exists
print('=> Checking checkpoints')
local checkpoint, optimState = checkpoints.load(opt)

-- Create model
print('=> Setting up model')
local model, criterion = models.setup(opt, checkpoint)

-- Data loading
print('=> Setting up data loader')
local trainLoader, valLoader = DataLoader.create(opt)

-- The trainer handles the training loop and evaluation on validation set
print('=> Loading trainer')
local Trainer = require('models/' .. opt.trainerType .. '-train')
local trainer = Trainer(model, criterion, opt, optimState)


if opt.valOnly then
   local loss = trainer:test(0, valLoader)
   print(string.format(' * Results Err %1.4f', loss))
   return
end


local loggerLoss = optim.Logger(paths.concat(opt.resume, 'loss.log'))
loggerLoss:setNames{'Training', 'Test'}

local startEpoch = checkpoint and checkpoint.epoch + 1 or math.max(1, opt.epochNumber)
local bestLoss = math.huge
for epoch = startEpoch, opt.nEpochs do
   -- Train for a single epoch
   local trainLoss = trainer:train(epoch, trainLoader)

   --checkpoints.save(epoch, model, trainer.optimState, true, opt)

   -- Run model on validation set
   local testLoss = trainer:test(epoch, valLoader)
   --testLoss = 0

   local bestModel = false
   if testLoss < bestLoss then
      bestModel = true
      bestLoss = testLoss
      print(' * Best model ', testLoss)
   end

   checkpoints.save(epoch, model, trainer.optimState, bestModel, opt)

   loggerLoss:add({trainLoss, testLoss})
end

print(string.format(' * Finished Err %1.4f', bestLoss))

loggerLoss:style({'+-', '+-'})
loggerLoss:plot()
