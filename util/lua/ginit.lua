function ginit(opt)
   require 'torch'
  require 'image'
  require 'nn'
--  require 'nngraph'
--  require 'inn'

  --require 'cutorch'
  --require 'cunn'
  require 'cudnn'
  cudnn.benchmark = true

  -- require 'optim'
  -- require 'gnuplot'
  -- require 'lfs'
  -- require 'xlua'

  pl = require 'pl.import_into' ()

  --class = require 'class'
  --profi = require 'ProFi'
  --display = require 'display'
  --mat = require 'fb.mattorch'
  -- if opt and opt.debug then
  --   dbg = require 'fb.debugger'
  -- end
--  py = require 'fb.python'

  --gp = require 'gpath'
  --ut = require 'utils'
  fp_ut = require 'floorplan_utils'
  --nnut = require 'nn_utils'
  --wut = require 'www_utils'
  --fbut = require 'fb.util'
  --iut = require 'itorch_utils'

  --require 'audio'
  --require 'hdf5'
  --require 'loadcaffe'
  --require 'tds'
  --require 'npy4th'
  --require 'svm'


  ---------------------------------------

  --[[
  require 'nn.Convolve'
  require 'nn.Crop'
  require 'nn.CrossConvolve'
  require 'nn.CrossConvolveParallel'
  require 'nn.CrossMergeTable'
  require 'nn.Print'
  require 'nn.Projection'
  require 'nn.Sampler'
  require 'nn.Scale'

  require 'nn.GaussianCriterion'
  require 'nn.GDLCriterion'
  require 'nn.KLDCriterion'
  ]]--
end

return ginit
