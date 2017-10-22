local M = {}

function M.create(opt, split)
   local cachePath = paths.concat(opt.gen, opt.dataset .. '.t7')
   if not paths.filep(cachePath) then
      local script = paths.dofile(opt.dataset .. '-gen.lua')
      script.exec(opt, cachePath)
   end
   local imageInfo = torch.load(cachePath)

   local Dataset = require('datasets/' .. opt.dataset)
   return Dataset(imageInfo, opt, split)
end

return M
