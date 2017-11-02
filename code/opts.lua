--
--  Copyright (c) 2016, Facebook, Inc.
--  All rights reserved.
--
--  This source code is licensed under the BSD-style license found in the
--  LICENSE file in the root directory of this source tree. An additional grant
--  of patent rights can be found in the PATENTS file in the same directory.
--
local M = { }

function M.parse(arg)
   local cmd = torch.CmdLine()
   cmd:text()
   cmd:text('Torch-7 ResNet Training script')
   cmd:text()
   cmd:text('Options:')
   ------------- General options -------------------
   cmd:option('-debug',      false,      'Debug mode')
   cmd:option('-manualSeed', 0,          'Manually set RNG seed')
   cmd:option('-gpu',       '1',        'ID of GPU to use by default, separated by ,')
   cmd:option('-nGPU',       1,        'The number of GPUs to use')
   cmd:option('-backend',    'cudnn',    'Options: cudnn | cunn')
   cmd:option('-cudnn',      'default',  'Options: fastest | default | deterministic')
   ------------- Path options ----------------------
   cmd:option('-data',       '../data/',     'Path to dataset')
   cmd:option('-gen',        '../gen/',      'Path to save generated files')   
   cmd:option('-resume',     '../checkpoint/',   'Path to checkpoint')   
   ------------- Data options ----------------------
   cmd:option('-nThreads',   1,              'number of data loading threads')
   cmd:option('-dataset',    'floorplan-representation',    'dataset name')
   cmd:option('-maxImgs',    100000,         'Number of images in train+val')
   cmd:option('-maxNumJunctions',    40,         'The maximum number of junction')
   cmd:option('-maxNumWalls',    100,         'The maximum number of junction')
   cmd:option('-maxTestImgs',    5000,         'Number of images in test')
   cmd:option('-trainPctg',  0.95,           'Percentage of training images')
   cmd:option('-mode',         '',      'Data mode to be considered')
   cmd:option('-maskProb',         0.5,      'The probability of training masks')
   cmd:option('-IOUThreshold',         0.95,      'The probability of training masks')
   ------------- Training/testing options ----------
   cmd:option('-nEpochs',         1000,       'Number of total epochs to run')
   cmd:option('-checkpointEpochInterval',         1,       'Number of epochs between two saved checkpoints')
   cmd:option('-batchSize',       16,        'mini-batch size (1 = pure stochastic)')
   cmd:option('-valOnly',         false,     'Run on validation set only')
   cmd:option('-testOnly',        false,     'Run on validation set only')
   cmd:option('-visualizeOnly',   false,     'Run on validation set only')
   cmd:option('-evaluateOnly',   false,     'Evaluate results only')
   cmd:option('-predictOnly',   false,     'Predict results only')
   ------------- Optimization options --------------
   cmd:option('-LR',              1e-5,  'initial learning rate')
   cmd:option('-momentum',        0.9,   'momentum')
   cmd:option('-weightDecay',     1e-4,  'weight decay')
   ------------- Model options ---------------------
   cmd:option('-netType',      'heatmap-segmentation',     'Network type')
   cmd:option('-modelName',         '',      'model name')
   cmd:option('-loaderType',      '',     'Data loader type')
   cmd:option('-trainerType',      '',     'Trainer type')
   cmd:option('-criterionType',      '',     'Trainer type')
   cmd:option('-loadDim',          286,       'Input dimensions')
   cmd:option('-sampleDim',          256,       'Input dimensions')
   cmd:option('-sampleDim_2',          128,       'Input dimensions')
   cmd:option('-patchDim',          112,       'Input patch dimensions')
   cmd:option('-outputDim',          64,       'Output dimensions')
   cmd:option('-segmentationDim',          500,       'Input dimensions')
   cmd:option('-retrain',      'none',   'Path to model to retrain with')
   cmd:option('-optimState',   'none',   'Path to an optimState to reload from')
   cmd:option('-useCheckpoint',         0,      'Load checkpoint or not')
   ------------- Other model options ---------------
   cmd:option('-nClasses',         13,      'The number of classes in the dataset')
   cmd:option('-nSegmentationClasses',         26,      'Number of classes of segmentation')   
   cmd:option('-gridDim',         8,      'Grid dimension')
   cmd:option('-numAnchorBoxes',         13,      'The number of anchor boxes')
   cmd:option('-lineWidth',         5,      'line width')
   cmd:option('-ncInput',         3,      'The number of input channels')   
   cmd:option('-ncOutput',         3,      'The number of output channels')   
   cmd:option('-nz',         512,      'nz')
   cmd:option('-nf',         64,      'nf')
   cmd:option('-numImages',         10,      'The number of images to consider')   
   cmd:option('-direction',         'BtoA',      'AtoB or BtoA')
   cmd:option('-conditionGAN', 1, 'set to 0 to use unconditional discriminator')
   cmd:option('-useGAN', 1, 'set to 0 to turn off GAN term')
   cmd:option('-useL1', 1, 'set to 0 to turn off L1 term')
   cmd:option('-lambdaL1', 100, 'weight on L1 term in objective')
   cmd:option('-useBottleneck', 1, 'set to 0 to turn off bottleneck term')
   cmd:option('-lambdaBottleneck', 1, 'weight on L1 term in objective')
   cmd:option('-resnetDepth', 34, 'ResNet depth')
   cmd:option('-weight_1', 3, 'Weight 1')
   
   cmd:option('-loadModel',         '',      'load trained model')
   cmd:option('-loadPoseEstimationModel', '../PoseEstimation/human_pose_mpii.t7', 'load pretrained model')   
   ------------- pre-process options ---------------
   cmd:option('-scaleProb',         0.5,      'The probability of using scaling instead of random cropping')    
   cmd:option('-useColorJitter',         true,      'use color jitter or not')    
   cmd:option('-useLighting',         true,      'use lighting or not')    
   cmd:option('-useHorizontalFlip',         false,      'use horizontal flip or not')  
   
   ------------- execution options ---------------
   cmd:option('-displayFreq',        20,      'visualization interval')
   cmd:option('-checkFreq',        100,      'check output interval')
   cmd:option('-numExamplesToCheck',        16,      'the number of examples to check')
   cmd:option('-tmp',       'test/',     'path to write temporary file')
   cmd:option('-logIter',         0,      'logging interval')
   cmd:option('-numFolds',         5,      'the number of folds')

   ------------- testing options ---------------
   cmd:option('-resultPath', 'results/', 'path to save evaluation results')   
   cmd:option('-floorplanFilename', '', 'filename for the floorplan to test')
   cmd:option('-outputFilename', 'test/result', 'filename for saving the prediction')
   
   cmd:text()
   
   local opt = cmd:parse(arg or {})

   if opt.trainerType == '' then
      opt.trainerType = opt.netType
   end
   if opt.criterionType == '' then   
      opt.criterionType = opt.netType   
   end
   if opt.loaderType == '' then   
      opt.loaderType = opt.netType   
   end

   if opt.mode ~= '' and opt.modelName == '' then
      opt.modelName = opt.mode
   end
   
   opt.resume = path.join(opt.resume, opt.netType)
   opt.tmp = path.join(opt.tmp, opt.netType)
   if opt.modelName ~= '' then   
      opt.resume = opt.resume .. '-' .. opt.modelName
      opt.tmp = opt.tmp .. '-' .. opt.modelName
   end   

   return opt
end

function M.init(opt)
   --pl.dir.makepath(opt.data)
   --pl.dir.makepath(opt.gen)
   --pl.dir.makepath(opt.resume)
   pl.dir.makepath(opt.tmp)
end

return M
