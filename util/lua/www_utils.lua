require 'lfs'
local ut = require 'utils'

local www_utils = {}

-- isNorm is deprecated
function www_utils.saveIms(ims, imPath, isNorm, count)
  count = count or 0
  isNorm = isNorm or false
  local numIms = ut.getLength(ims)

  local filenames = {}
  for i = 1, numIms do
    filenames[i] = string.format("%08d.jpg", count + i)
    -- Scale the image and save
    local im = ims[i]
    if isNorm then
      im = ims[i]:clone()
      local maxVal = im:max()
      local minVal = im:min()
      im:add(-minVal):mul(1.0 / (maxVal - minVal))
    end
    image.save(paths.concat(imPath, filenames[i]), im)
  end

  return filenames, count + numIms
end

-- ims and captions are both tables
function www_utils.renderTables(ims, captions, ncol, width, imPath)
  assert(#captions == 0 or #captions == #ims, "#captions should be either 0 or equal to #ims")

  local nrow = math.ceil(#ims / ncol)
  local htmlStr = "<table>\n"

  local k = 0

  for i = 1, nrow do
    local captionRow = "<td>"..i.."</td>"
    local imRow = "<td>"..i.."</td>"
    for j = 1, ncol do
      k = k + 1

      if #captions > 0 then
        captionRow = captionRow .. string.format("<td>%s</td>", captions[k])
      end
      imRow = imRow .. string.format("<td><img width="..width.." src='%s'></img></td>", imPath .. '/' .. ims[k])
      if k >= #ims then break end
    end

    if #captions > 0 then
      htmlStr = htmlStr .. "<tr>" .. captionRow .. "</tr>\n"
    end
    htmlStr = htmlStr .. "<tr>" .. imRow .. "</tr>\n"

    if k >= #ims then break end
  end

  return htmlStr .. "</table>\n"
end

function www_utils.renderKeyValues(t)
  -- Write all key_value pairs
  local htmlStr = "<table>\n<tr><td>Key</td><td>Value</td></tr>\n"

  for k, v in pairs(t) do
    htmlStr = htmlStr .. "<tr><td>" .. k .. "</td><td>" .. v .. "</td><tr>\n"
  end

  return htmlStr .. "</table>\n"
end

function www_utils.renderHeader()
  return [[
<head>
<style>
    * {
        font-size: 24px;
    }
</style>
</head>
]]
end

function www_utils.renderHtml(rootDir, ims, captions, ncol, isNorm, width, htmlFile)
  captions = captions or {}
  ncol = ncol or 8
  isNorm = isNorm or false
  width = width or 256
  htmlFile = htmlFile or 'index.html'

  local imRelativeDir = './im'
  local imDir = paths.concat(rootDir, imRelativeDir)

  lfs.mkdir(rootDir)
  lfs.mkdir(imDir)

  local count = 0

  local f = io.open(paths.concat(rootDir, htmlFile), "w")
  f:write('<html>\n'..www_utils.renderHeader()..'<body>\n')

  local imNames = www_utils.saveIms(ims, imDir, isNorm, count)
  local htmlStr = www_utils.renderTables(imNames, captions, ncol, width, imRelativeDir)

  f:write(htmlStr .. '</body>\n</html>')
  f:close()

  return count
end

return www_utils
