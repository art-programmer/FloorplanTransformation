local ffi = require 'ffi'
local image = require 'image'
local M = {}
require 'csvigo'

local function findImages(opt, split)
   ----------------------------------------------------------------------
   -- Options for the GNU and BSD find command
   
   local imageInfo = csvigo.load({path=opt.data .. '/' .. split .. '.txt', mode="large", header=false, separator='\t'})
   
   local floorplanPaths = {}
   local representationPaths = {}
   
   -- Generate a list of all the images and their class
   local maxLength = 0
   for k, v in pairs(photo_info) do
      local floorplanFilename = opt.data .. '/' .. v[1]
      local representationFilename = opt.data .. '/' .. v[2]
      
      local floorplanExists, floorplan = pcall(function()             
	    return image.load(floorplanFilename, 3)
      end)      
      assert(floorplanExists)
      --if floorplanExists == true then

      table.insert(representationPaths, representationFilename)
      table.insert(floorplanPaths, floorplanFilename)
      maxLength = math.max(maxLength, #representationFilename + 1)
      
      xlua.progress(#representationPaths, maxImgs)
   end
   
   local nImages = #representationPaths
   print('number of images: ' .. nImages)

   local floorplanPathTensor = torch.CharTensor(nImages, maxLength)
   local representationPathTensor = torch.CharTensor(nImages, maxLength)
   
   for i, path in pairs(floorplanPaths) do   
      ffi.copy(floorplanPathTensor[i]:data(), path)
   end
   for i, path in pairs(representationPaths) do   
      ffi.copy(representationPathTensor[i]:data(), path)   
   end
   
   return floorplanPathTensor, representationPathTensor
end

function M.exec(opt, cacheFile)
   -- find the image path names

   --assert(paths.dirp(opt.data), 'data directory not found: ' .. opt.data)

   print("=> Generating list of images")
   local floorplanPathsTrain, representationPathsTrain = findImages(opt, 'train')
   local floorplanPathsVal, representationPathsVal = findImages(opt, 'val')
   local floorplanPathsTest, representationPathsTest = findImages(opt, 'test')

   
   local info = {
      basedir = opt.data,
      train = {
         floorplanPaths = floorplanPathsTrain,
         representationPaths = representationPathsTrain,
      },
      val = {
         floorplanPaths = floorplanPathsVal,
         representationPaths = representationPathsVal,
      },
      test = {
         floorplanPaths = floorplanPathsTest,
         representationPaths = representationPathsTest,
      },
   }

   print(" | saving list of images to " .. cacheFile)
   torch.save(cacheFile, info)
   return info
end

return M
