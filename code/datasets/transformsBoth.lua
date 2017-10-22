--
--  Copyright (c) 2016, Facebook, Inc.
--  All rights reserved.
--
--  This source code is licensed under the BSD-style license found in the
--  LICENSE file in the root directory of this source tree. An additional grant
--  of patent rights can be found in the PATENTS file in the same directory.
--
--  Image transforms for data augmentation and input normalization
--

require 'image'
package.path = '../util/lua/?.lua;' .. package.path

local M = {}

function M.Compose(transforms)
   return function(input, input_2)
      for _, transform in ipairs(transforms) do
         input, input_2 = transform(input, input_2)
      end
      return input, input_2
   end
end

function M.ColorNormalize(meanstd)
   return function(img, input_2)
      img = img:clone()      
      for i = 1, 3 do      
         img[i]:add(-meanstd.mean[i])      
         img[i]:div(meanstd.std[i])      
      end
      return img, input_2
   end
end

function M.ColorUnnormalize(meanstd)
   return function(img)
      img = img:clone()
      for i = 1, 3 do
         img[i]:mul(meanstd.std[i])
         img[i]:add(meanstd.mean[i])
      end
      return img
   end
end

-- Scales the shorter/longer edge to size
function M.Scale(size, interpolation)
   interpolation = interpolation or 'bicubic'
   return function(input, input_2)
      local w, h = input:size(3), input:size(2)
      local width, height
      if w > h then
         width = size    
         height = h / w * size
      else
         width = w / h * size    
         height = size
      end
      local output_2
      if input_2 ~= nil then
         output_2 = image.scale(input_2, width, height, 'simple')
      end
      return image.scale(input, width, height, interpolation), output_2
   end
end

-- Scales the second input
function M.ScaleSecond(size, interpolation)
   interpolation = interpolation or 'simple'
   return function(input, input_2)
      assert(input_2, 'second input should not be empty')
      local output_2 = image.scale(input_2, size, size, interpolation)
      
      return input, output_2
   end
end

-- Scales the shorter/longer edge to size
function M.Resize(width, height, interpolation)
   interpolation = interpolation or 'bicubic'
   return function(input, input_2)
      local output_2
      if input_2 ~= nil then
	 output_2 = image.scale(input_2, width, height, 'simple')
      end
      return image.scale(input, width, height, interpolation), output_2
   end
end

-- Pads images in four dimensions
function M.Pad(size)
   return function(input, input_2)
      local temp = input.new(3, input:size(2) + 2*size, input:size(3) + 2*size)
      temp:fill(1)      
         :narrow(2, size+1, input:size(2))      
         :narrow(3, size+1, input:size(3))      
         :copy(input)
      local output_2
      if input_2 then
	 output_2 = torch.Tensor()
	 output_2:resize(input_2:size(1), input_2:size(2) + 2*size, input_2:size(3) + 2*size):fill(0)
            :narrow(2, size+1, input_2:size(2))      
            :narrow(3, size+1, input_2:size(3))
            :copy(input_2)
      end
      return temp, output_2
   end
end

-- Crop to centered rectangle
function M.CenterCrop(size)
   return function(input, input_2)
      local w1 = math.ceil((input:size(3) - size)/2)
      local h1 = math.ceil((input:size(2) - size)/2)
      local output_2
      if input_2 then
	 output_2 = image.crop(input_2, w1, h1, w1 + size, h1 + size)
      end
      return image.crop(input, w1, h1, w1 + size, h1 + size), output_2 -- center patch
   end
end

-- Random crop form larger image with optional zero padding
function M.RandomCrop(size, padding)
   padding = padding or 0

   return function(input, input_2)
      if padding > 0 then
         local temp = input.new(3, input:size(2) + 2*padding, input:size(3) + 2*padding)
         temp:zero()
            :narrow(2, padding+1, input:size(2))
            :narrow(3, padding+1, input:size(3))
            :copy(input)
         input = temp

	 if input_2 ~= nil then
	    local temp = input_2.new(input_2:size(1), input_2:size(2) + 2*padding, input_2:size(3) + 2*padding)
	    temp:zero()
	       :narrow(2, padding+1, input_2:size(2))
	       :narrow(3, padding+1, input_2:size(3))
            :copy(input_2)
	    input_2 = temp
	 end
      end
      
      local output
      local w, h = input:size(3), input:size(2)
      local x1, y1 = torch.random(0, w - size), torch.random(0, h - size)
      if w == size and h == size then
         output = input
      else
	 output = image.crop(input, x1, y1, x1 + size, y1 + size)
	 assert(output:size(2) == size and output:size(3) == size, 'wrong crop size')
      end

      local output_2
      if input_2 ~= nil then      
         local depth = input_2:dim()      
         local w, h = input_2:size(depth - 0), input_2:size(depth - 1)
         if w == size and h == size then
	    output_2 = input_2
	 else
	    output_2 = image.crop(input_2, x1, y1, x1 + size, y1 + size)
	    assert(output_2:size(depth - 1) == size and output_2:size(depth) == size, 'wrong crop size')
         end
      end
      
      return output, output_2
   end
end

-- Four corner patches and center crop from image and its horizontal reflection
function M.TenCrop(size)
   local centerCrop = M.CenterCrop(size)

   return function(input)
      local w, h = input:size(3), input:size(2)

      local output = {}
      for _, img in ipairs{input, image.hflip(input)} do
         table.insert(output, centerCrop(img))
         table.insert(output, image.crop(img, 0, 0, size, size))
         table.insert(output, image.crop(img, w-size, 0, w, size))
         table.insert(output, image.crop(img, 0, h-size, size, h))
         table.insert(output, image.crop(img, w-size, h-size, w, h))
      end

      -- View as mini-batch
      for i, img in ipairs(output) do
         output[i] = img:view(1, img:size(1), img:size(2), img:size(3))
      end

      return input.cat(output, 1)
   end
end

-- Resized with shorter side randomly sampled from [minSize, maxSize] (ResNet-style)
function M.RandomScale(minSize, maxSize)
   return function(input)
      local w, h = input:size(3), input:size(2)

      local targetSz = torch.random(minSize, maxSize)
      local targetW, targetH = targetSz, targetSz
      if w < h then
         targetH = torch.round(h / w * targetW)
      else
         targetW = torch.round(w / h * targetH)
      end

      return image.scale(input, targetW, targetH, 'bicubic')
   end
end

-- Random crop with size 8%-100% and aspect ratio 3/4 - 4/3 (Inception-style)
function M.RandomSizedCrop(size)
   local scale = M.Scale(size)
   local crop = M.CenterCrop(size)

   return function(input)
      local attempt = 0
      repeat
         local area = input:size(2) * input:size(3)
         local targetArea = torch.uniform(0.08, 1.0) * area

         local aspectRatio = torch.uniform(3/4, 4/3)
         local w = torch.round(math.sqrt(targetArea * aspectRatio))
         local h = torch.round(math.sqrt(targetArea / aspectRatio))

         if torch.uniform() < 0.5 then
            w, h = h, w
         end

         if h <= input:size(2) and w <= input:size(3) then
            local y1 = torch.random(0, input:size(2) - h)
            local x1 = torch.random(0, input:size(3) - w)

            local out = image.crop(input, x1, y1, x1 + w, y1 + h)
            assert(out:size(2) == h and out:size(3) == w, 'wrong crop size')

            return image.scale(out, size, size, 'bicubic')
         end
         attempt = attempt + 1
      until attempt >= 10

      -- fallback
      return crop(scale(input))
   end
end

function M.HorizontalFlip(prob)
   return function(input, input_2)
      local output_2
      if torch.uniform() < prob then
         input = image.hflip(input)
	 if input_2 ~= nil then
	    if input_2:type() == 'torch.IntTensor' then
	       input_2 = image.hflip(input_2:double()):int()
            else
	       input_2 = image.hflip(input_2)
	    end
         end
      end
      return input, input_2
   end
end

function M.Rotate()
   return function(img, input_2)
      local imgRotated
      local orientation = math.random(4)
      if orientation == 1 then      
         imgRotated = img:clone()      
      elseif orientation == 2 then      
         imgRotated = image.hflip(img:transpose(2, 3))      
      elseif orientation == 3 then      
         imgRotated = image.hflip(image.vflip(img))            
      else      
         imgRotated = image.vflip(img:transpose(2, 3))      
      end
      local output_2
      if input_2 ~= nil then
         if orientation == 1 then      
            output_2 = input_2:clone()      
         elseif orientation == 2 then      
            output_2 = image.hflip(input_2:transpose(2, 3))      
         elseif orientation == 3 then      
            output_2 = image.hflip(image.vflip(input_2))
         else      
            output_2 = image.vflip(input_2:transpose(2, 3))      
         end         
      end
      return imgRotated, output_2
   end
end

function M.Rotation(deg)
   return function(input)
      if deg ~= 0 then
         input = image.rotate(input, (torch.uniform() - 0.5) * deg * math.pi / 180, 'bilinear')
      end
      return input
   end
end

-- Lighting noise (AlexNet-style PCA-based noise)
function M.Lighting(alphastd, eigval, eigvec)
   return function(input)
      if alphastd == 0 then
         return input
      end

      local alpha = torch.Tensor(3):normal(0, alphastd)
      local rgb = eigvec:clone()
         :cmul(alpha:view(1, 3):expand(3, 3))
         :cmul(eigval:view(1, 3):expand(3, 3))
         :sum(2)
         :squeeze()

      input = input:clone()
      for i=1,3 do
         input[i]:add(rgb[i])
      end
      return input
   end
end

local function blend(img1, img2, alpha)
   return img1:mul(alpha):add(1 - alpha, img2)
end

local function grayscale(dst, img)
   dst:resizeAs(img)
   dst[1]:zero()
   dst[1]:add(0.299, img[1]):add(0.587, img[2]):add(0.114, img[3])
   dst[2]:copy(dst[1])
   dst[3]:copy(dst[1])
   return dst
end

function M.Saturation(var)
   local gs

   return function(input)
      gs = gs or input.new()
      grayscale(gs, input)

      local alpha = 1.0 + torch.uniform(-var, var)
      blend(input, gs, alpha)
      return input
   end
end

function M.Brightness(var)
   local gs

   return function(input)
      gs = gs or input.new()
      gs:resizeAs(input):zero()

      local alpha = 1.0 + torch.uniform(-var, var)
      blend(input, gs, alpha)
      return input
   end
end

function M.Contrast(var)
   local gs

   return function(input)
      gs = gs or input.new()
      grayscale(gs, input)
      gs:fill(gs[1]:mean())

      local alpha = 1.0 + torch.uniform(-var, var)
      blend(input, gs, alpha)
      return input
   end
end

function M.RandomOrder(ts)
   return function(input, input_2)
      local img = input.img or input
      local order = torch.randperm(#ts)
      for i=1,#ts do
         img = ts[order[i]](img)
      end
      return img, input_2
   end
end

function M.ColorJitter(opt)
   local brightness = opt.brightness or 0
   local contrast = opt.contrast or 0
   local saturation = opt.saturation or 0

   local ts = {}
   if brightness ~= 0 then
      table.insert(ts, M.Brightness(brightness))
   end
   if contrast ~= 0 then
      table.insert(ts, M.Contrast(contrast))
   end
   if saturation ~= 0 then
      table.insert(ts, M.Saturation(saturation))
   end

   if #ts == 0 then
      return function(input, input_2) return input, input_2 end
   end

   return M.RandomOrder(ts)
end

function M.Binarize(threshold)
   return function(img)
      local imgBinary = torch.ones(1, (#img)[2], (#img)[3])
      for i = 1, 3 do
         local mask = img[i]:lt(threshold):double()
         imgBinary[1] = torch.cmul(imgBinary[1], mask)
      end
      return imgBinary:repeatTensor(3, 1, 1)
   end
end

function M.Gray2RGB()
   return function(img)
      local imgRGB = img:repeatTensor(3, 1, 1):double()
      return imgRGB
   end
end

function M.RGB2Gray()
   return function(img)
      local imgGray = img[1]:clone():int()
      return imgGray
   end
end

function M.ColorShift()
   return function(img)
      local imgShifted = img:clone()
      local nChannels = (#img)[1]
      for c = 1, nChannels do
         imgShifted[c] = img[math.random(nChannels)]:clone()
      end
      return imgShifted
   end
end

return M
