require 'csvigo'
require 'image'
local pl = require 'pl.import_into' ()
cv = require 'cv'
require 'cv.imgproc'

local utils = {}

function utils.transform(transformation, points)
   if points:dim() == 1 then
      points = points:repeatTensor(1, 1)
   end
   points = torch.cat(points, torch.ones(points:size(1)), 2)
   local newPoints = (transformation * points:transpose(1, 2)):transpose(1, 2)
   newPoints = torch.cdiv(newPoints[{{}, {1, 3}}], newPoints[{{}, {4}}]:expand(newPoints:size(1), 3))
   return newPoints
end

function utils.project(transformation, points)
   if points:dim() == 1 then
      points = points:repeatTensor(1, 1)
   end
   points = torch.cat(points, torch.ones(points:size(1)), 2)
   local points2D = (transformation * points:transpose(1, 2)):transpose(1, 2)
   points2D = torch.cdiv(points2D[{{}, {1, 2}}], points2D[{{}, {3}}]:expand(points2D:size(1), 2))
   return points2D:squeeze()
end

function utils.unproject(transformation, points2D, additionalConstraint)
   if points2D:dim() == 1 then
      points2D = points2D:repeatTensor(1, 1)
   end
   points2D = torch.cat(points2D, torch.ones(points2D:size(1)), 2)
   local A = torch.cat(transformation, additionalConstraint, 1)
   local b = torch.cat(points2D, torch.zeros(points2D:size(1), additionalConstraint:size(1)), 2)

   local points = (torch.inverse(A) * b:transpose(1, 2)):transpose(1, 2)
   points = torch.cdiv(points[{{}, {1, 3}}], points[{{}, {4}}]:expand(points:size(1), 3))
   return points:squeeze()
end

-- function utils.fitPlanes(points, numPlanes = 100, numIterations = 20)
--    local numPoints = points:size(1)
--    local numSampledPoints = 10000
--    local sampledPoints = points:index(1, perm:narrow(1, 1, numSampledPoints):long())

--    local perm = torch.randperm(numSampledPoints)
--    local indices = perm:narrow(1, 1, numIterations * 3):long()
--    local selectedPoints = sampledPoints:index(1, indices):reshape(numIterations, 3, 3)
--    local vectors_1 = selectedPoints[{{}, 1, {}}] - selectedPoints[{{}, 2, {}}]
--    local vectors_2 = selectedPoints[{{}, 1, {}}] - selectedPoints[{{}, 3, {}}]
--    local normals = torch.zeros(vectors_1:size())
--    normals[{{}, 1}] = vectors_1[{{}, 2}] * vectors_2[{{}, 3}] - vectors_1[{{}, 3}] * vectors_2[{{}, 2}]
--    normals[{{}, 2}] = vectors_1[{{}, 3}] * vectors_2[{{}, 1}] - vectors_1[{{}, 1}] * vectors_2[{{}, 3}]
--    normals[{{}, 3}] = vectors_1[{{}, 1}] * vectors_2[{{}, 2}] - vectors_1[{{}, 2}] * vectors_2[{{}, 1}]
--    local mean = torch.mean(selectedPoints, 2):squeeze()
--    local planeD = torch.sum(torch.cmul(normals, mean), 2)
--    local planes = normals * planeD:repeatTensor(1, 3)
-- end

function utils.projectLines(transformation, lines)
   local lines2D
   for lineIndex = 1, lines:size(1) do
      local line = lines[lineIndex]
      local points = torch.cat(line, torch.ones(2), 2)
      local points2D = (transformation * points:transpose(1, 2)):transpose(1, 2)
      points2D[{{}, 1}] = torch.cdiv(points2D[{{}, 1}], points2D[{{}, 3}])
      points2D[{{}, 2}] = torch.cdiv(points2D[{{}, 2}], points2D[{{}, 3}])
      local lineExists = false
      for pointIndex = 1, 2 do
         local point2D = points2D[pointIndex]
         --if point2D[3] > 0 and point2D[1] >= 1 and point2D[1] <= width and point2D[2] >= 1 and point2D[2] <= height then
         if point2D[3] > 0 then
            lineExists = true
         end
      end
      lineExists = true
      local line2D = torch.zeros(1, 2, 2)
      if lineExists then
         line2D = points2D[{{}, {1, 2}}]:repeatTensor(1, 1, 1)
      end
      if not lines2D then
         lines2D = line2D
      else
         lines2D = torch.cat(lines2D, line2D, 1)
      end
   end
   return lines2D
end

function utils.loadPointCloud(filename)
   local representationExists, representationInfo = pcall(function()
         return csvigo.load({path=filename, mode="large", header=false, separator=' ', verbose=false})
   end)
   local points = {}
   if representationExists and representationInfo ~= nil then
      local numPoints = tonumber(representationInfo[1][3])
      for pointIndex, point in pairs(representationInfo) do
	 if pointIndex >= 3 then
	    table.insert(points, {point[2], point[3], point[4]})
	 end
	 if pointIndex - 2 == numPoints then
	    break
	 end
      end
   end
   return torch.Tensor(points)
end

function utils.samplePoints(points, numSampledPoints)
   local indices = torch.randperm(points:size(1)):narrow(1, 1, numSampledPoints):long()
   local sampledPoints = points:index(1, indices)
   return sampledPoints
end

function utils.drawTopDownView(width, height, points, angle, transformation)
   local X = points[{{}, 1}]
   local Y = points[{{}, 2}]
   local points2D = torch.cat(X, Y, 2)

   local mean = torch.mean(points2D, 1)
   points2D = points2D - mean:expandAs(points2D)
   points2D:div(math.sqrt(points2D:size(1) - 1))

   if not transformation then
      if not angle then
      --local w, _, _ = torch.svd(points2D:t())
      --angle = torch.atan2(w[1][2], w[1][1])
      angle = 0
      end

      local newX = X * torch.cos(angle) + Y * torch.sin(angle)
      local newY = X * torch.sin(angle) - Y * torch.cos(angle)
      local newPoints2D = torch.cat(newX, newY, 2)

      local mins = torch.min(newPoints2D, 1)[1]
      local maxs = torch.max(newPoints2D, 1)[1]
      local paddingRatio = 0.05
      local padding = (maxs - mins) * paddingRatio
      mins = mins - padding
      maxs = maxs + padding

      local scaleFactor = math.min(width / (maxs[1] - mins[1]), height / (maxs[2] - mins[2]))
      transformation = torch.zeros(3, 4)
      transformation[1][1] = torch.cos(angle)
      transformation[1][2] = torch.sin(angle)
      transformation[1][4] = -mins[1]
      transformation[2][1] = torch.sin(angle)
      transformation[2][2] = -torch.cos(angle)
      transformation[2][4] = -mins[2]
      transformation[3][4] = 1
      transformation[1] = transformation[1] * scaleFactor
      transformation[2] = transformation[2] * scaleFactor
      --transformation[1], transformation[2] = transformation[2], transformation[1]\
      
   end

   local uv = utils.project(transformation, points)
   local topDownView = torch.zeros(height, width)
   for i = 1, uv:size(1) do
      local point = uv[i]
      topDownView[math.min(math.max(point[2], 1), height)][math.min(math.max(point[1], 1), width)] = topDownView[math.min(math.max(point[2], 1), height)][math.min(math.max(point[1], 1), width)] + 1
   end
   --image.save('test/pointcloud.png', topDownView)
   local pointDensity = 1
   topDownView = topDownView / topDownView:max()
--   topDownView[topDownView:gt(1)] = 1

   topDownView = torch.repeatTensor(topDownView, 3, 1, 1)
   return topDownView, transformation
end

function utils.getRotationMatrix(quaternion)
   qi = quaternion[1]
   qj = quaternion[2]
   qk = quaternion[3]
   qr = quaternion[4]
   local rotation = torch.zeros(4, 4)
   rotation[1][1] = 1 - 2 * (qj^2 + qk^2)
   rotation[1][2] = 2 * (qi * qj - qk * qr)
   rotation[1][3] = 2 * (qi * qk + qj * qr)
   rotation[2][1] = 2 * (qi * qj + qk * qr)
   rotation[2][2] = 1 - 2 * (qi^2 + qk^2)
   rotation[2][3] = 2 * (qj * qk - qi * qr)
   rotation[3][1] = 2 * (qi * qk - qj * qr)
   rotation[3][2] = 2 * (qj * qk + qi * qr)
   rotation[3][3] = 1 - 2 * (qi^2 + qj^2)
   rotation[4][4] = 1
   return rotation
end

function utils.getTransformation(camera, pose, orientation)
   local K = torch.zeros(3, 3)
   K[1][2] = 1
   K[2][1] = -1
   K[3][3] = 1
   local intrinsics = camera.intrinsics:clone()

   if not orientation or orientation == 1 then
      intrinsics[{{}, 1}] = -intrinsics[{{}, 1}]
      intrinsics[{{}, 3}] = -intrinsics[{{}, 3}]
   elseif orientation == 2 then
      intrinsics[{{}, 3}] = -intrinsics[{{}, 3}]
      local temp = intrinsics[{{}, 1}]:clone()
      intrinsics[{{}, 1}] = -intrinsics[{{}, 2}]
      intrinsics[{{}, 2}] = -temp
      local temp = intrinsics[1][3]
      intrinsics[1][3] = intrinsics[2][3]
      intrinsics[2][3] = temp
   end

   --intrinsics[2][2] = -intrinsics[2][2]
   intrinsics = torch.cat(intrinsics, torch.zeros(3), 2)

   local inverseQuaternion = pose[{{4, 7}}]:clone()
   inverseQuaternion[{{1, 3}}] = -inverseQuaternion[{{1, 3}}]
   local rotation = utils.getRotationMatrix(inverseQuaternion)
   local translation = torch.zeros(4, 4)
   translation[1][1] = 1
   translation[2][2] = 1
   translation[3][3] = 1
   translation[1][4] = -pose[1]
   translation[2][4] = -pose[2]
   translation[3][4] = -pose[3]
   translation[4][4] = 1
   local transformation = intrinsics * rotation * translation
   print('frame')
   print(pose)
   print(intrinsics)
   -- print(K)
   print(rotation)
   print(translation)
   print(transformation)

   local point = torch.Tensor({-0.0527, 2.0441, 1.000, 1})
   -- print(point)
   -- print(rotation * point)
   -- print(translation * rotation * point)
   -- print(transformation * point)
   return transformation
end

-- function utils.getRotationFromAngle(angle)
--    rotation[1][1] = torch.cos(angle)
--    rotation[1][2] = torch.sin(angle)
--    rotation[2][1] = torch.sin(angle)
--    rotation[2][2] = -torch.cos(angle)
--    rotation[3][3] = 1
--    return rotation
-- end

return utils
