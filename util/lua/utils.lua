require 'torch'
require 'lfs'
cv = require 'cv'
require 'cv.imgproc'

local utils = {}

function utils.to4DTensor(a)
  return utils.toXDTensor(a, 4)
end

function utils.toXDTensor(a, x)
  local sz = torch.LongStorage(x):fill(1)
  for i = 1, a:dim() do
    sz[i] = a:size(i)
  end
  return a:reshape(sz)
end

function utils.toNNSingleTensor(a)
  local opt = opt or {}
  opt.type = opt.type or 'CUDA'

  if opt.type == 'CPU' then 
    return a:double()
  elseif opt.type == 'CUDA' then 
    return a:cuda()
  else
    return a
  end
end

function utils.toNNTensor(a)
  if type(a) == 'userdata' then
    return utils.toNNSingleTensor(a)
  elseif type(a) == 'table' then
    local b = {}
    for key, value in pairs(a) do
      b[key] = utils.toNNTensor(value)
    end
    return b
  else
    return a
  end
end

function utils.getLength(a)
   if type(a) == 'userdata' then
    return a:size(1)
  elseif type(a) == 'table' then
    return #a
  end
end

function utils.getFirstDim(a)
  if type(a) == 'userdata' then
    return a:size(1)
  elseif type(a) == 'table' then
    return utils.getSize(a[1])
  end
end

-- to be replaced
function utils.getSize(a)
  return utils.getFirstDim(a)
end


function utils.getIndices(a, indices)
  if type(a) == 'userdata' then
    return a:index(1, indices)
  elseif type(a) == 'table' then
    local b = {} 
    for key, value in pairs(a) do
      b[key] = utils.getIndices(value, indices)
    end
    return b
  end
end

function utils.loadData(fileName)
  if lfs.attributes(fileName, 'mode') == 'file' then
    return torch.load(fileName)
  else
    return nil
  end
end

-- all inputs are ByteTensors, 0 is false and 1 is true.
function utils.isinf(value)
  return value == math.huge or value == -math.huge
end

function utils.isnan(value)
  return value ~= value
end

function utils.isfinite(value)
  return not utils.isinf(value) and not utils.isnan(value)
end

function utils.bitand(t1, t2)
  return torch.ge(t1 + t2, 2)
end

function utils.bitor(t1, t2)
  return torch.ge(t1 + t2, 1)
end

function utils.bitnot(t)
  return torch.lt(t, 1)
end

function utils.len(t)
  local n
  if type(t) == 'table' then
    n = #t
  elseif t:nDimension() == 1 then
    n = t:size(1)
  else
    error(string.format("t is a high-order tensor! t:nDimension() = %d", t:nDimension()))
  end
  return n
end

function utils.fromHead(t, k)
  local n = utils.len(t)
  local res = {}
  for i = 1, math.min(k, n) do
    table.insert(res, t[i])
  end
  return res
end

function utils.fromTail(t, k)
  local n = utils.len(t)
  local res = {}
  for i = n, math.max(n - k, 0) + 1, -1 do
    table.insert(res, t[i])
  end
  return res
end

-- Find nonzero and return a table.
function utils.nonzero(t)
  local indices = {}
  local n = utils.len(t)

  for i = 1, n do
    if t[i] == 1 then 
      table.insert(indices, i) 
    end
  end
  return indices
end

-- Select rows and return
function utils.selectRows(t, tb)
  assert(tb:size(1) == t:size(1), 'The first dimension of t and tb must be the same')
  local dims = t:size():totable()
  table.remove(dims, 1)

  local res = t.new():resize(tb:sum(), unpack(dims))
  local counter = 0
  for i = 1, t:size(1) do
    if tb[i] == 1 then 
      counter = counter + 1
      res[counter]:copy(t[i]) 
    end
  end
  return res
end

function utils.permCompose(indices1, indices2)
  -- body
  local n1 = utils.len(indices1)
  local n2 = utils.len(indices2)

  local indices = {}
  for i = 1, n2 do
    indices[i] = indices1[indices2[i]]
  end
  return indices
end

function utils.removeKeys(t, exclude)
  local res = {}
  for k, v in pairs(t) do
    if not exclude[k] then res[k] = v end
  end
  return res
end

--[[ 

Find the correlation between two matrices.
t1 : m1 by n
t2 : m2 by n

return matrix of size m1 by m2

--]]
function utils.innerprod(t1, t2, func, reduction)
  local n = t1:size(2)
  assert(n == t2:size(2), string.format('The column of t1 [%d] must be the same as the column of t2 [%d]', t1:size(2), t2:size(2)))
  local m1 = t1:size(1)
  local m2 = t2:size(1)

  local res = torch.Tensor(m1, m2)
  for i = 1, m1 do
    for j = 1, m2 do
      res[i][j] = func(t1[i], t2[j])
    end
  end

  -- Find the one with smallest distance
  local best, bestIndices
  if reduction then
    best, bestIndices = reduction(res, 2)
  end

  return res, best, bestIndices
end

-----------------------------------------------
-- Landmarks related.

function utils.inRect(rect, p, margin)
  margin = margin or 0;

  return rect[1] + margin <= p[1] and p[1] <= rect[3] - margin and
  rect[2] + margin <= p[2] and p[2] <= rect[4] - margin;
end

function utils.fillKernel(m, x, y, r, c)
  assert(m, "Input image should not be null")
  assert(x and y, "Input coordinates should not be null")
  assert(r and c, "Input radius and color should not be null")
  assert(#m:size() == 2, 'fill_kernel: input m is not 2D!')

  -- fill a circle (x, y, r) with number c.
  local w = m:size(2)
  local h = m:size(1)

  local minX = math.min(math.max(x - r, 1), w)
  local maxX = math.min(math.max(x + r, 1), w)
  -- if minX > maxX then minX, maxX = maxX, minX end

  local minY = math.min(math.max(y - r, 1), h)
  local maxY = math.min(math.max(y + r, 1), h)
  -- if minY > maxY then minY, maxY = maxY, minY end

  -- local img_rect = {1, 1, m:size(2), m:size(1)}
  -- assert(util.rect_isin(img_rect, {minX, minY}) == true, string.format("out of bound, minX = %f, minY = %f", minX, minY))
  -- assert(util.rect_isin(img_rect, {maxX, maxY}) == true, string.format("out of bound, maxX = %f, maxY = %f", maxX, maxY))

  m:sub(minY, maxY, minX, maxX):fill(c);
end

-- Input a 2D mask, find its minimal value and associated location.
function utils.imin(m)
  local min1, minI1 = torch.min(m, 1)
  local minVal, minI2 = torch.min(min1, 2)

  local x = minI2[1][1]
  local y = minI1[1][x]
  return x, y, minVal
end

-- Input a 2D mask, find its maximal value and associated location.
function utils.imax(m)
  local max1, maxI1 = torch.max(m, 1)
  local maxVal, maxI2 = torch.max(max1, 2)

  local x = maxI2[1][1]
  local y = maxI1[1][x]
  return x, y, maxVal
end
-------------------------------------Save to json--------------------
function utils.set2Array(t)
  if type(t) ~= 'table' then return end
  t.__array = true
  for i, v in ipairs(t) do
    utils.set2Array(v)
  end
end

function utils.convert2Table(t)
  local res = {}
  if type(t) == 'table' then
    if debug then print("parsing table") end
    for k, v in pairs(t) do
      res[k] = utils.convert2Table(v)
    end
  elseif type(t) == 'number' then
    if debug then print("parsing number") end
    res = t
  elseif torch.typename(t) and torch.typename(t):match('Tensor') then
    -- if t is a tensor
    if debug then print("parsing tensor") end
    res = t:totable()
    utils.set2Array(t)
    -- Layer 
  else
    local typename = type(t)
    typename = typename or torch.typename(t)
    error("Convert_to_table error, unsupported datatype = " .. typename)
  end
  return res
end

function utils.saveJson(t, f)
  -- save a table to json
  if type(t) == 'number' then
    f:write(tostring(t))
    return
  end
  if t.__array then
    -- array must contain all numbers.
    f:write("[\n")
    for i, v in ipairs(t) do
      utils.saveJson(v, f)
      if i ~= #t then f:write(",") end
    end
    f:write("]\n")
  else
    local counter = 0
    for k, v in pairs(t) do counter = counter + 1 end
    f:write("{\n")
    for k, v in pairs(t) do
      f:write(tostring(k) .. " : ")
      utils.saveJson(v, f)
      counter = counter - 1
      if counter >= 1 then f:write(",\n") end
    end
    f:write("}\n")
  end
end

-------------------------------------Save to numpy-----------------
-- run it using PATH=/usr/bin/python

function utils.savePickle(f, t)
  local py = require 'fb.python'
  py.exec([=[
import numpy as np
import cPickle
with open(filename, "wb") as outfile:
    cPickle.dump(variable, outfile, protocol=cPickle.HIGHEST_PROTOCOL)
]=], {variable = t, filename = f})
end

--

local function getTermLength()
  if sys.uname() == 'windows' then return 80 end
  local tputf = io.popen('tput cols', 'r')
  local w = tonumber(tputf:read('*a'))
  local rc = {tputf:close()}
  if rc[3] == 0 then return w
  else return 80 end 
end

local barDone = true
local previous = -1
local tm = ''
local timer
local times
local indices
local termLength = math.min(getTermLength(), 120)

local function formatTime(seconds)
  -- decompose:
  local floor = math.floor
  local days = floor(seconds / 3600/24)
  seconds = seconds - days*3600*24
  local hours = floor(seconds / 3600)
  seconds = seconds - hours*3600
  local minutes = floor(seconds / 60)
  seconds = seconds - minutes*60
  local secondsf = floor(seconds)
  seconds = seconds - secondsf
  local millis = floor(seconds*1000)

  -- string
  local f = ''
  local i = 1
  if days > 0 then f = f .. days .. 'D' i=i+1 end
  if hours > 0 and i <= 2 then f = f .. hours .. 'h' i=i+1 end
  if minutes > 0 and i <= 2 then f = f .. minutes .. 'm' i=i+1 end
  if secondsf > 0 and i <= 2 then f = f .. secondsf .. 's' i=i+1 end
  if millis > 0 and i <= 2 then f = f .. millis .. 'ms' i=i+1 end
  if f == '' then f = '0ms' end

  -- return formatted time
  return f
end

function utils.progress(current, goal, addinfo)
  -- defaults:
  local barLength = termLength - 37 - #addinfo
  local smoothing = 100 
  local maxfps = 10

  -- Compute percentage
  local percent = math.floor(((current) * barLength) / goal)

  -- start new bar
  if (barDone and ((previous == -1) or (percent < previous))) then
    barDone = false
    previous = -1
    tm = ''
    timer = torch.Timer()
    times = {timer:time().real}
    indices = {current}
  else
    io.write('\r')
  end

  --if (percent ~= previous and not barDone) then
  if (not barDone) then
    previous = percent
    -- print bar
    io.write(' [')
    for i=1,barLength do
      if (i < percent) then io.write('=')
      elseif (i == percent) then io.write('>')
      else io.write('.') end
    end
    io.write('] ')
    for i=1,termLength-barLength-4 do io.write(' ') end
    for i=1,termLength-barLength-4 do io.write('\b') end
    -- time stats
    local elapsed = timer:time().real
    local step = (elapsed-times[1]) / (current-indices[1])
    if current==indices[1] then step = 0 end
    local remaining = math.max(0,(goal - current)*step)
    table.insert(indices, current)
    table.insert(times, elapsed)
    if #indices > smoothing then
      indices = table.splice(indices)
      times = table.splice(times)
    end
    -- Print remaining time when running or total time when done.
    if (percent < barLength) then
      tm = ' ETA: ' .. formatTime(remaining)
    else
      tm = ' Tot: ' .. formatTime(elapsed)
    end
    tm = tm .. ' | Step: ' .. formatTime(step) .. ' | ' .. addinfo
    io.write(tm)
    -- go back to center of bar, and print progress
    for i=1,5+#tm+barLength/2 do io.write('\b') end
    io.write(' ', current, '/', goal, ' ')
    -- reset for next bar
    if (percent == barLength) then
      barDone = true
      io.write('\n')
    end
    -- flush
    io.write('\r')
    io.flush()
  end
end

function utils.drawHeatMapImage(image, heatMap, alpha, beta)
   local scale = math.ceil(math.max((#image)[2] / (#heatMap)[1], (#image)[3] / (#heatMap)[2]))
   resizedHeatMap = require('nn').SpatialUpSamplingBilinear(scale):forward(heatMap:repeatTensor(1, 1, 1))[1]
   
   local paddingX = (#image)[2] - (#resizedHeatMap)[1]   
   local paddingLeft = math.floor(paddingX / 2)   
   local paddingRight = paddingX - paddingLeft
   local paddingY = (#image)[3] - (#resizedHeatMap)[2]   
   local paddingTop = math.floor(paddingY / 2)
   local paddingBottom = paddingY - paddingTop
   resizedHeatMap = require('nn').SpatialZeroPadding(paddingLeft, paddingRight, paddingTop, paddingBottom):forward(resizedHeatMap:repeatTensor(1, 1, 1))[1]
   --print(scale)
   --print(padding)
   --os.exit(1)

   local heatMapHSL = torch.DoubleTensor(3, (#resizedHeatMap)[1], (#resizedHeatMap)[2])
   heatMapHSL[1] = 2 / 3 * (1 - resizedHeatMap)
   heatMapHSL[2] = 1
   heatMapHSL[3] = 0.5
   local heatMapRGB = require('image').hsl2rgb(heatMapHSL)
   local heatMapImage = image * alpha + heatMapRGB * beta
   heatMapImage:clamp(0, 1)
   return heatMapImage
end



function utils.segmentFloorplan(floorplan, binaryThreshold, numOpenOperations, reverse)

   local floorplanBinary = torch.ones((#floorplan)[2], (#floorplan)[3])
   for c = 1, 3 do
      local mask = floorplan[c]:lt(binaryThreshold):double()
      floorplanBinary = torch.cmul(floorplanBinary, mask)
   end

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

function utils.drawSegmentation(floorplanComponent, numComponents, denotedColorMap)
   local colorMap = denotedColorMap
   if colorMap == nil then
      colorMap = {}
      for i = 1, numComponents do
         colorMap[i] = torch.rand(3)
      end
      colorMap[0] = torch.zeros(3)
      colorMap[-1] = torch.ones(3)
   end

   local floorplanLabels = floorplanComponent:repeatTensor(3, 1, 1):double()
   for c = 1, 3 do
      floorplanLabels[c]:apply(function(x) return colorMap[x][c] end)
   end
   return floorplanLabels
end

return utils
