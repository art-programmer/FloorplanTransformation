from gurobipy import *
import cv2
import numpy as np
import sys
import csv
import copy
from utils import *
from floorplan_utils import *
from skimage import measure

# if len(sys.argv) == 2 and int(sys.argv[1]) == 1:
#   withoutQP = True
# else:
#   withoutQP = False
#   pass
withoutQP = False

#GAP = 5
#GAPS = {'wall_extraction': 10, 'door_extraction': 5, 'icon_extraction': 5, 'wall_neighbor': 10, 'door_neighbor': 10, 'icon_neighbor': 10, 'wall_conflict': 10, 'door_conflict': 10, 'icon_conflict': 10, 'wall_icon_neighbor': 5, 'wall_icon_conflict': 5, 'wall_door_neighbor': 5}
#DISTANCES = {'wall_icon': 10, 'point': 10, 'wall': 10, 'door': 10, 'icon': 10}

GAPS = {'wall_extraction': 5, 'door_extraction': 5, 'icon_extraction': 5, 'wall_neighbor': 5, 'door_neighbor': 5, 'icon_neighbor': 5, 'wall_conflict': 5, 'door_conflict': 5, 'icon_conflict': 5, 'wall_icon_neighbor': 5, 'wall_icon_conflict': 5, 'wall_door_neighbor': 5, 'door_point_conflict': 5}
DISTANCES = {'wall_icon': 5, 'point': 5, 'wall': 10, 'door': 5, 'icon': 5}
LENGTH_THRESHOLDS = {'wall': 5, 'door': 5, 'icon': 5}


junctionWeight = 100
augmentedJunctionWeight = 50
labelWeight = 1

wallWeight = 10
doorWeight = 10
iconWeight = 10

#wallTypeWeight = 10
#doorTypeWeight = 10
iconTypeWeight = 10

wallLineWidth = 3
doorLineWidth = 2
#doorExposureWeight = 0


NUM_WALL_TYPES = 1
NUM_DOOR_TYPES = 2
#NUM_LABELS = NUM_WALL_TYPES + NUM_DOOR_TYPES + NUM_ICONS + NUM_ROOMS + 1
NUM_LABELS = NUM_ICONS + NUM_ROOMS

WALL_LABEL_OFFSET = NUM_FINAL_ROOMS
DOOR_LABEL_OFFSET = NUM_FINAL_ICONS + 1
ICON_LABEL_OFFSET = 0
ROOM_LABEL_OFFSET = NUM_ICONS


colorMap = ColorPalette(NUM_CORNERS).getColorMap()


#colorMap = np.random.rand(11, 3) * 255
#colorMap[0] = 160
# iconWallTypesMap[0] = 'bathtub'
# iconWallTypesMap[1] = 'cooking counter'
# iconWallTypesMap[2] = 'toilet'
# iconWallTypesMap[3] = 'entrance'
# iconWallTypesMap[4] = 'washing basin'
# iconWallTypesMap[5] = 'washing machine'
# iconWallTypesMap[6] = 'washing basin'
# iconWallTypesMap[7] = 'cross'
# iconWallTypesMap[8] = 'column'
# iconWallTypesMap[9] = 'stairs'

#floorplan = cv2.imread('test/floorplan.png')


width = 256
height = 256
maxDim = max(width, height)
sizes = np.array([width, height])

ORIENTATION_RANGES = getOrientationRanges(width, height)

#iconStyles = [1, 1, 1, 1, 1, 2, 1, 1, 3, 1]
iconNames = getIconNames()
iconNameNumberMap = dict(zip(iconNames, range(len(iconNames))))
iconNumberNameMap = dict(zip(range(len(iconNames)), iconNames))
#iconNumberStyleMap = dict(zip(range(len(iconStyles)), iconStyles))

def findMatches(pred_dict, gt_dict, distanceThreshold, width=256, height=256):
  correctSums = {k: 0.0 for k in gt_dict}
  countsGT = {k: 0.0 for k in gt_dict}
  countsPred = {k: 0.0 for k in gt_dict}
  for objectType, objects in gt_dict.iteritems():
    if objectType not in pred_dict:
      print(objectType + ' not in prediction')
      continue

    pointsGT = objects[0]
    pointsPred = pred_dict[objectType][0]
    if objectType == 'wall':
      validPointMaskGT = {}
      for line in objects[1]:
        validPointMaskGT[line[0]] = True
        validPointMaskGT[line[1]] = True
        continue
      validPointsGT = [pointsGT[pointIndex] for pointIndex in validPointMaskGT]

      #print([(pred_dict[objectType][0][line[0]][:2], pred_dict[objectType][0][line[1]][:2]) for line in pred_dict[objectType][1]])
      #exit(1)
      validPointMaskPred = {}
      for line in pred_dict[objectType][1]:
        validPointMaskPred[line[0]] = True
        validPointMaskPred[line[1]] = True
        continue
      validPointsPred = [pointsPred[pointIndex] for pointIndex in validPointMaskPred]

      if True:
        # degree insensitive
        pointIndexMap = []
        for pointIndexGT, pointGT in enumerate(validPointsGT):
          matchedPointMask = {}
          for pointIndexPred, pointPred in enumerate(validPointsPred):
            if pointPred[2] == pointGT[2] and pointPred[3] == pointGT[3] and pointDistance(pointPred[0:2], pointGT[0:2]) < distanceThreshold:
              matchedPointMask[pointIndexPred] = True
              pass
            continue
          if len(matchedPointMask) == 0:
            print(pointIndexGT, pointGT, 'point not found')
            pass
          pointIndexMap.append(matchedPointMask)
          continue

        correctSums[objectType] += len([indexMap for indexMap in pointIndexMap if len(indexMap) > 0])
        countsGT[objectType] += len(validPointsGT)
        countsPred[objectType] += len(validPointsPred)
      else:
        numMatches = 0
        matchedMask = {}
        pointMatchMap = {}
        for pointIndexPred, pointPred in enumerate(validPointsPred):
          minDistancePair = (10000, -1)
          for pointIndexGT, pointGT in enumerate(validPointsGT):
            distance = pointDistance(pointPred[0:2], pointGT[0:2])
            if distance < minDistancePair[0]:
              minDistancePair = (distance, pointIndexGT)
              pass
            continue
          pointMatchMap[pointIndexPred] = minDistancePair[1]
          continue

        for pointIndexGT, pointGT in enumerate(validPointsGT):
          matchedOrientations = {}
          for orientation in POINT_ORIENTATIONS[pointGT[2]][pointGT[3]]:
            matchedOrientations[orientation] = False
            continue
          for pointIndexPred, pointPred in enumerate(validPointsPred):
            if pointMatchMap[pointIndexPred] != pointIndexGT:
              continue
            if pointDistance(pointPred[0:2], pointGT[0:2]) < distanceThreshold:
              for orientation in POINT_ORIENTATIONS[pointPred[2]][pointPred[3]]:
                if orientation in matchedOrientations and matchedOrientations[orientation] == False:
                  if (pointIndexPred, orientation) not in matchedMask:
                    matchedMask[(pointIndexPred, orientation)] = True
                    matchedOrientations[orientation] = True
                    pass
                  pass
                continue
              pass
            continue
          for orientation, hasMatch in matchedOrientations.iteritems():
            if not hasMatch:
              print(pointIndexGT, pointGT, orientation, 'point not found')
              pass
            continue
          numMatches += len([orientation for orientation, value in matchedOrientations.iteritems() if value == True])
          continue

        correctSums[objectType] += numMatches
        countsGT[objectType] += sum([point[2] + 1 for point in validPointsGT])
        countsPred[objectType] += sum([point[2] + 1 for point in validPointsPred])

      continue

    if objectType == 'door':
      linesGT = objects[1]
      linesPred = pred_dict[objectType][1]
      lineIndexMap = []
      for lineIndexGT, lineGT in enumerate(linesGT):
        matchedLineMask = {}
        for lineIndexPred, linePred in enumerate(linesPred):
          #if (linePred[0] in pointIndexMap[lineGT[0]] and linePred[1] in pointIndexMap[lineGT[1]]) or (linePred[1] in pointIndexMap[lineGT[0]] and linePred[0] in pointIndexMap[lineGT[1]]):
          if (pointDistance(pointsPred[linePred[0]], pointsGT[lineGT[0]]) < distanceThreshold and pointDistance(pointsPred[linePred[1]], pointsGT[lineGT[1]]) < distanceThreshold) or (pointDistance(pointsPred[linePred[0]], pointsGT[lineGT[1]]) < distanceThreshold and pointDistance(pointsPred[linePred[1]], pointsGT[lineGT[0]]) < distanceThreshold):
            matchedLineMask[lineIndexPred] = True
            #print('match', lineGT, linePred)
            pass
          continue
        if len(matchedLineMask) == 0:
          print(lineIndexGT, lineGT, [pointsGT[pointIndex][:2] for pointIndex in lineGT], 'door not found')
          pass
        lineIndexMap.append(matchedLineMask)
        continue

      correctSums[objectType] += len([indexMap for indexMap in lineIndexMap if len(indexMap) > 0])
      countsGT[objectType] += len(linesGT)
      countsPred[objectType] += len(linesPred)
      continue

    if objectType == 'icon':
      rectanglesGT = objects[1]
      rectanglesPred = pred_dict[objectType][1]
      labelsGT = objects[2]
      labelsPred = pred_dict[objectType][2]

      rectangleIndexMap = []
      for indexGT, rectangleGT in enumerate(rectanglesGT):
        matchedRectangleMask = {}
        for indexPred, rectanglePred in enumerate(rectanglesPred):
          if labelsGT[indexGT] == labelsPred[indexPred] and calcIOU([pointsPred[pointIndex] for pointIndex in rectanglePred], [pointsGT[pointIndex] for pointIndex in rectangleGT]) >= 0.3:
            matchedRectangleMask[indexPred] = True
            pass
          continue
        if len(matchedRectangleMask) == 0:
          print(indexGT, rectangleGT, [pointsGT[pointIndex][:2] for pointIndex in rectangleGT], 'icon not found')
          pass
        rectangleIndexMap.append(matchedRectangleMask)
        continue

      correctSums[objectType] += len([indexMap for indexMap in rectangleIndexMap if len(indexMap) > 0])
      countsGT[objectType] += len(rectanglesGT)
      countsPred[objectType] += len(rectanglesPred)
      pass
    continue

  roomsInfo = []
  wallLineWidth = 3
  dicts = [gt_dict, pred_dict]
  for dictIndex in range(2):
    wall_dict = dicts[dictIndex]['wall']
    wallMask = drawWallMask([(wall_dict[0][line[0]], wall_dict[0][line[1]]) for line in wall_dict[1]], width, height, thickness=wallLineWidth)
    roomRegions = measure.label(1 - wallMask, background=0)
    cv2.imwrite('test/' + str(dictIndex) + '_segmentation_regions.png', drawSegmentationImage(roomRegions))
    backgroundIndex = roomRegions.min()
    wallPoints = wall_dict[0]
    roomSegmentation = np.zeros(roomRegions.shape, dtype=np.int32)
    roomLabels = {}
    adjacentRoomPairs = []
    for wallIndex, wallLabels in enumerate(wall_dict[2]):
      wallLine = wall_dict[1][wallIndex]
      lineDim = calcLineDim(wallPoints, wallLine)
      center = np.round((np.array(wallPoints[wallLine[0]][:2]) + np.array(wallPoints[wallLine[1]][:2])) / 2).astype(np.int32)
      adjacentRoomPair = []
      for c in range(2):
        direction = c * 2 - 1
        if lineDim == 1:
          direction *= -1
          pass
        point = center
        for offset in range(10):
          point[1 - lineDim] += direction
          if point[lineDim] < 0 or point[lineDim] >= sizes[lineDim]:
            break
          roomIndex = roomRegions[point[1], point[0]]
          if roomIndex != backgroundIndex:
            #print(wallIndex, center.tolist(), point.tolist(), wallLabels[c])
            # if wallLabels[c] not in rooms:
            #   rooms[wallLabels[c]] = []
            #   pass
            mask = roomRegions == roomIndex
            roomSegmentation[mask] = wallLabels[c]
            #rooms[wallLabels[c]].append(cv2.dilate(mask.astype(np.uint8), np.ones((3, 3)), iterations=wallLineWidth))
            #roomRegions[mask] = backgroundIndex
            if roomIndex not in roomLabels:
              roomLabels[roomIndex] = {}
              pass
            roomLabels[roomIndex][wallLabels[c]] = True
            adjacentRoomPair.append(roomIndex)
            break
            pass
          continue
        continue
      if len(adjacentRoomPair) == 2:
        adjacentRoomPairs.append(adjacentRoomPair)
        pass
      continue

    neighborRoomPairs = []
    door_dict = dicts[dictIndex]['door']
    for doorLine in door_dict[1]:
      lineDim = calcLineDim(door_dict[0], doorLine)
      center = np.round((np.array(door_dict[0][doorLine[0]][:2]) + np.array(door_dict[0][doorLine[1]][:2])) / 2).astype(np.int32)
      neighborRoomPair = []
      for c in range(2):
        direction = c * 2 - 1
        point = center
        for offset in range(10):
          point[1 - lineDim] += direction
          if point[lineDim] < 0 or point[lineDim] >= sizes[lineDim]:
            break
          roomIndex = roomRegions[point[1], point[0]]
          if roomIndex != backgroundIndex:
            neighborRoomPair.append(roomIndex)
            break
            pass
          continue
        continue
      if len(neighborRoomPair) == 2:
        neighborRoomPairs.append(neighborRoomPair)
        pass
      continue

    rooms = []
    indexMap = {}
    for roomIndex, labels in roomLabels.iteritems():
      indexMap[roomIndex] = len(rooms)
      mask = roomRegions == roomIndex
      mask = cv2.dilate(mask.astype(np.uint8), np.ones((3, 3)), iterations=wallLineWidth)
      if 7 in labels and 2 not in labels:
        labels[2] = True
        pass
      if 5 in labels and 3 not in labels:
        labels[3] = True
        pass
      if 9 in labels and 1 not in labels:
        labels[1] = True
        pass
      rooms.append((mask, labels))
      continue

    neighborRoomPairs = [(indexMap[neighborRoomPair[0]], indexMap[neighborRoomPair[1]]) for neighborRoomPair in neighborRoomPairs]
    neighborMatrix = np.zeros((len(rooms), len(rooms)))
    for neighborRoomPair in neighborRoomPairs:
      neighborMatrix[neighborRoomPair[0]][neighborRoomPair[1]] = 1
      neighborMatrix[neighborRoomPair[1]][neighborRoomPair[0]] = 1
      continue

    adjacentRoomPairs = [(indexMap[adjacentRoomPair[0]], indexMap[adjacentRoomPair[1]]) for adjacentRoomPair in adjacentRoomPairs]
    adjacentMatrix = np.zeros((len(rooms), len(rooms)))
    for adjacentRoomPair in adjacentRoomPairs:
      adjacentMatrix[adjacentRoomPair[0]][adjacentRoomPair[1]] = 1
      adjacentMatrix[adjacentRoomPair[1]][adjacentRoomPair[0]] = 1
      continue
    #exit(1)
    roomsInfo.append([rooms, neighborMatrix, adjacentMatrix])
    continue

  #gt_dict['room'] = zip(*roomsInfo[0][0])
  #pred_dict['room'] = zip(*roomsInfo[1][0])

  #countsPred['room'] = sum([len(roomsPred) for roomLabel, roomsPred in labelRooms[1].iteritems()])
  countsPred['room'] = len(roomsInfo[1][0])
  countsGT['room'] = len(roomsInfo[0][0])
  correctSums['room'] = 0.0
  for roomGT in roomsInfo[0][0]:
    hasMatch = False
    for roomPred in roomsInfo[1][0]:
      hasCommonLabel = False
      for labelGT in roomGT[1]:
        if labelGT in roomPred[1]:
          hasCommonLabel = True
          break
        continue
      # if 8 in roomGT[1]:
      #   print(roomPred[1], calcIOUMask(roomPred[0], roomGT[0]))
      #   pass
      if hasCommonLabel and calcIOUMask(roomPred[0], roomGT[0]) >= 0.5:
        correctSums['room'] += 1
        hasMatch = True
        break
      continue
    if not hasMatch:
      print(roomGT[1].keys(), roomGT[0].max(0).nonzero()[0].mean(), roomGT[0].max(1).nonzero()[0].mean(), 'room not found')
      pass
    continue
  #print(labelRooms[1])
  statistics = {k: [v, countsGT[k], countsPred[k]] for k, v in correctSums.iteritems()}


  roomIndexMap = np.zeros(len(roomsInfo[1][0]))
  orderedRoomPred = {}
  for roomIndexPred, roomPred in enumerate(roomsInfo[1][0]):
    maxIOURoom = (0, -1)
    for roomIndexGT, roomGT in enumerate(roomsInfo[0][0]):
      IOU = calcIOUMask(roomPred[0], roomGT[0])
      if IOU > maxIOURoom[0]:
        maxIOURoom = (IOU, roomIndexGT)
        pass
      continue
    if maxIOURoom[1] < 0:
      print(roomPred[1].keys(), roomPred[0].max(0).nonzero()[0].mean(), roomPred[0].max(1).nonzero()[0].mean(), 'room has no match')
      exit(1)
      pass
    roomIndexGT = maxIOURoom[1]
    roomIndexMap[roomIndexPred] = roomIndexGT
    if roomIndexGT not in orderedRoomPred:
      orderedRoomPred[roomIndexGT] = roomPred
    else:
      mask = orderedRoomPred[roomIndexGT][0] + roomPred[0]
      roomLabels = {}
      for label in orderedRoomPred[roomIndexGT][1]:
        roomLabels[label] = True
        continue
      for label in roomPred[1]:
        roomLabels[label] = True
        continue
      orderedRoomPred[roomIndexGT] = (mask, roomLabels)
      pass
    continue
  roomIndexMap = (np.expand_dims(roomIndexMap, -1) == np.expand_dims(np.arange(len(roomsInfo[0][0]), dtype=np.int32), 0)).astype(np.int32)

  # print('GT', [(roomIndexGT, roomGT[1].keys(), roomGT[0].max(0).nonzero()[0].mean(), roomGT[0].max(1).nonzero()[0].mean()) for roomIndexGT, roomGT in enumerate(roomsInfo[0][0])])
  # print('Pred', [(roomIndexPred, roomPred[1].keys(), roomPred[0].max(0).nonzero()[0].mean(), roomPred[0].max(1).nonzero()[0].mean()) for roomIndexPred, roomPred in enumerate(roomsInfo[1][0])])
  # print(roomsInfo[0][1], roomsInfo[0][2])
  # print(roomsInfo[1][1], roomsInfo[1][2])
  # print(roomIndexMap)
  roomsInfo[1][1] = np.matmul(roomIndexMap.transpose(), np.matmul(roomsInfo[1][1], roomIndexMap))
  roomsInfo[1][2] = np.matmul(roomIndexMap.transpose(), np.matmul(roomsInfo[1][2], roomIndexMap))
  #print(roomsInfo[1][1], roomsInfo[1][2])
  #print(roomsInfo[0][1], roomsInfo[0][2])
  # exit(1)

  topologyStatistics = {k: [0.0, 0.0, 0.0] for k in ['adjacent', 'neighbor', 'neighbor_foreground', 'adjacent_all' , 'neighbor_all', 'neighbor_all_foreground', 'all', 'all_foreground']}
  for k in ['adjacent_all' , 'neighbor_all', 'all']:
    topologyStatistics[k][1] = topologyStatistics[k][2] = len(roomsInfo[0][0])
    continue
  for k in ['neighbor_all_foreground', 'all_foreground']:
    topologyStatistics[k][1] = topologyStatistics[k][2] = len(roomsInfo[0][0]) - 1
    continue

  for roomIndex, roomGT in enumerate(roomsInfo[0][0]):
    if roomIndex not in orderedRoomPred:
      continue
    roomPred = orderedRoomPred[roomIndex]
    hasCommonLabel = False
    for labelGT in roomGT[1]:
      if labelGT in roomPred[1]:
        hasCommonLabel = True
        break
      continue
    if hasCommonLabel and calcIOUMask(roomPred[0], roomGT[0]) >= 0.5:
      neighborMatchMask = roomsInfo[0][1][roomIndex] == roomsInfo[1][1][roomIndex]
      topologyStatistics['neighbor'][0] += (neighborMatchMask * roomsInfo[0][1][roomIndex]).sum()
      topologyStatistics['neighbor'][1] += roomsInfo[0][1][roomIndex].sum()
      topologyStatistics['neighbor'][2] += roomsInfo[1][1][roomIndex].sum()
      topologyStatistics['neighbor_all'][0] += int(np.all(neighborMatchMask))

      adjacentMatchMask = roomsInfo[0][2][roomIndex] == roomsInfo[1][2][roomIndex]
      topologyStatistics['adjacent'][0] += (adjacentMatchMask * roomsInfo[0][2][roomIndex]).sum()
      topologyStatistics['adjacent'][1] += roomsInfo[0][2][roomIndex].sum()
      topologyStatistics['adjacent'][2] += roomsInfo[1][2][roomIndex].sum()
      topologyStatistics['adjacent_all'][0] += int(np.all(adjacentMatchMask))

      topologyStatistics['all'][0] += int(np.all(neighborMatchMask) and np.all(adjacentMatchMask))

      if roomIndex > 0:
        topologyStatistics['neighbor_foreground'][0] += (neighborMatchMask[1:] * roomsInfo[0][1][roomIndex][1:]).sum()
        topologyStatistics['neighbor_foreground'][1] += roomsInfo[0][1][roomIndex][1:].sum()
        topologyStatistics['neighbor_foreground'][2] += roomsInfo[1][1][roomIndex][1:].sum()
        topologyStatistics['neighbor_all_foreground'][0] += int(np.all(neighborMatchMask[1:]))
        topologyStatistics['all_foreground'][0] += int(np.all(neighborMatchMask[1:]) and np.all(adjacentMatchMask[1:]))
        pass
    else:
      print('incorrect label')
      print(roomGT[1].keys(), roomGT[0].max(0).nonzero()[0].mean(), roomGT[0].max(1).nonzero()[0].mean())
      print(roomPred[1].keys(), roomPred[0].max(0).nonzero()[0].mean(), roomPred[0].max(1).nonzero()[0].mean())
      pass
    continue
  #print(roomsInfo[0][1], roomsInfo[1][1], roomsInfo[0][2], roomsInfo[1][2])
  #print('topology', len(roomsInfo[0][0]), numMatchedRooms)

  #print(statistics['room'])

  #topologyStatistics = {k: topologyStatistics[k] for k in ['neighbor_foreground', 'neighbor', 'neighbor_all', 'neighbor_all_foreground']}

  for k in ['neighbor_foreground', 'neighbor_all_foreground']:
    statistics[k[:-11]] = topologyStatistics[k]
    continue
  return statistics


def extractCorners(heatmaps, threshold, gap, cornerType = 'wall', augment=False, h_points=False, gt=False):
  if gt:
    orientationPoints = heatmaps
  else:
    orientationPoints = extractCornersFromHeatmaps(heatmaps, threshold)
    pass
  #print(orientationPoints[7])
  #print(orientationPoints[12])
  #exit(1)
  if cornerType == 'wall':
    cornerOrientations = []
    for orientations in POINT_ORIENTATIONS:
      cornerOrientations += orientations
      continue
  elif cornerType == 'door':
    cornerOrientations = POINT_ORIENTATIONS[0]
  else:
    cornerOrientations = POINT_ORIENTATIONS[1]
    pass
  #print(orientationPoints)
  if h_points:
    res = myaugmenthack(orientationPoints, cornerOrientations, cornerType, gap)
    totalAugmentedPts = 0
    for k,v in res.items():
      orientationPoints[k].extend(v)
      totalAugmentedPts += len(v)
    print("total augmented points", totalAugmentedPts)

  if augment:
    orientationMap = {}
    for pointType, orientationOrientations in enumerate(POINT_ORIENTATIONS):
      for orientation, orientations in enumerate(orientationOrientations):
        orientationMap[orientations] = orientation
        continue
      continue

    for orientationIndex, corners in enumerate(orientationPoints):
      if len(corners) > 3:
        continue #skip aug
      pointType = orientationIndex / 4
      if pointType in [2]:
        orientation = orientationIndex % 4
        orientations = POINT_ORIENTATIONS[pointType][orientation]
        for i in range(len(orientations)):
          newOrientations = list(orientations)
          newOrientations.remove(orientations[i])
          newOrientations = tuple(newOrientations)
          if not newOrientations in orientationMap:
            continue
          newOrientation = orientationMap[newOrientations]
          for corner in corners:
            orientationPoints[(pointType - 1) * 4 + newOrientation].append(corner + (True, ))
            continue
          continue
      elif pointType in [1]:
        orientation = orientationIndex % 4
        orientations = POINT_ORIENTATIONS[pointType][orientation]
        for orientation in range(4):
          if orientation in orientations:
            continue
          newOrientations = list(orientations)
          newOrientations.append(orientation)
          newOrientations = tuple(newOrientations)
          if not newOrientations in orientationMap:
            continue
          newOrientation = orientationMap[newOrientations]
          for corner in corners:
            orientationPoints[(pointType + 1) * 4 + newOrientation].append(corner + (True, ))
            continue
          continue
        pass
      continue
    pass
  #print(orientationPoints)
  pointOffset = 0
  pointOffsets = []
  points = []
  pointOrientationLinesMap = []
  for orientationIndex, corners in enumerate(orientationPoints):
    pointOffsets.append(pointOffset)
    orientations = cornerOrientations[orientationIndex]
    for point in corners:
      orientationLines = {}
      for orientation in orientations:
        orientationLines[orientation] = []
        continue
      pointOrientationLinesMap.append(orientationLines)
      continue

    pointOffset += len(corners)

    if cornerType == 'wall':
      points += [[corner[0][0], corner[0][1], orientationIndex / 4, orientationIndex % 4] for corner in corners]
    elif cornerType == 'door':
      points += [[corner[0][0], corner[0][1], 0, orientationIndex] for corner in corners]
    else:
      points += [[corner[0][0], corner[0][1], 1, orientationIndex] for corner in corners]
      pass
    continue

  augmentedPointMask = {}


  lines = []
  pointNeighbors = [[] for point in points]

  for orientationIndex, corners in enumerate(orientationPoints):
    orientations = cornerOrientations[orientationIndex]
    for orientation in orientations:
      if orientation not in [1, 2]:
        continue
      oppositeOrientation = (orientation + 2) % 4
      lineDim = -1
      if orientation == 0 or orientation == 2:
        lineDim = 1
      else:
        lineDim = 0
        pass

      for cornerIndex, corner in enumerate(corners):
        pointIndex = pointOffsets[orientationIndex] + cornerIndex
        #print(corner)
        if len(corner) > 3:
          augmentedPointMask[pointIndex] = True
          pass

        ranges = copy.deepcopy(ORIENTATION_RANGES[orientation])

        ranges[lineDim] = min(ranges[lineDim], corner[0][lineDim])
        ranges[lineDim + 2] = max(ranges[lineDim + 2], corner[0][lineDim])
        ranges[1 - lineDim] = min(ranges[1 - lineDim], corner[1][1 - lineDim] - gap)
        ranges[1 - lineDim + 2] = max(ranges[1 - lineDim + 2], corner[2][1 - lineDim] + gap)

        for oppositeOrientationIndex, oppositeCorners in enumerate(orientationPoints):
          if oppositeOrientation not in cornerOrientations[oppositeOrientationIndex]:
            continue
          for oppositeCornerIndex, oppositeCorner in enumerate(oppositeCorners):
            if orientationIndex == oppositeOrientationIndex and oppositeCornerIndex == cornerIndex:
              continue

            oppositePointIndex = pointOffsets[oppositeOrientationIndex] + oppositeCornerIndex


            if oppositeCorner[0][lineDim] < ranges[lineDim] or oppositeCorner[0][lineDim] > ranges[lineDim + 2] or ranges[1 - lineDim] > oppositeCorner[2][1 - lineDim] or ranges[1 - lineDim + 2] < oppositeCorner[1][1 - lineDim]:
              continue


            if abs(oppositeCorner[0][lineDim] - corner[0][lineDim]) < LENGTH_THRESHOLDS[cornerType]:
              continue

            lineIndex = len(lines)
            pointOrientationLinesMap[pointIndex][orientation].append(lineIndex)
            pointOrientationLinesMap[oppositePointIndex][oppositeOrientation].append(lineIndex)
            pointNeighbors[pointIndex].append(oppositePointIndex)
            pointNeighbors[oppositePointIndex].append(pointIndex)

            lines.append((pointIndex, oppositePointIndex))
            continue
          continue
        continue
      continue
    continue
      # pointType = orientationIndex / 4
      # orientation = orientationIndex % 4
      # orientations = POINT_ORIENTATIONS[pointType][orientation]
      # for i in range(len(orientations)):
      #   newOrientations = list(orientations)
      #   newOrientations.remove(orientations[i])
      #   newOrientations = tuple(newOrientations)
      #   if not newOrientations in orientationMap:
      #     continue
      #   newOrientation = orientationMap[newOrientations]
      #   for corner in corners:
      #     orientationPoints[(pointType - 1) * 4 + newOrientation].append(corner + (True, ))
      #     continue
      #   continue
      # continue
  #print('augs', len(augmentedPointMask))
  return points, lines, pointOrientationLinesMap, pointNeighbors, augmentedPointMask

def myaugmenthack(orientationPoints, cornerOrientations, cornerType, gap):
  lines = []
  pointOffset = 0
  pointOffsets = []
  points = []
  pointOrientationLinesMap = []
  for orientationIndex, corners in enumerate(orientationPoints):
    pointOffsets.append(pointOffset)
    orientations = cornerOrientations[orientationIndex]
    for point in corners:
      orientationLines = {}
      for orientation in orientations:
        orientationLines[orientation] = []
        continue
      pointOrientationLinesMap.append(orientationLines)
      continue

    pointOffset += len(corners)

    if cornerType == 'wall':
      points += [[corner[0][0], corner[0][1], orientationIndex / 4, orientationIndex % 4] for corner in corners]
    elif cornerType == 'door':
      points += [[corner[0][0], corner[0][1], 0, orientationIndex] for corner in corners]
    else:
      points += [[corner[0][0], corner[0][1], 1, orientationIndex] for corner in corners]
      pass
    continue

  augmentedPointMask = {}


  lines = []
  pointNeighbors = [[] for point in points]

  for orientationIndex, corners in enumerate(orientationPoints):
    orientations = cornerOrientations[orientationIndex]
    for orientation in orientations:
      if orientation not in [1, 2]:
        continue
      oppositeOrientation = (orientation + 2) % 4
      lineDim = -1
      if orientation == 0 or orientation == 2:
        lineDim = 1
      else:
        lineDim = 0
        pass

      for cornerIndex, corner in enumerate(corners):
        pointIndex = pointOffsets[orientationIndex] + cornerIndex

        ranges = copy.deepcopy(ORIENTATION_RANGES[orientation])

        ranges[lineDim] = min(ranges[lineDim], corner[0][lineDim])
        ranges[lineDim + 2] = max(ranges[lineDim + 2], corner[0][lineDim])
        ranges[1 - lineDim] = min(ranges[1 - lineDim], corner[1][1 - lineDim] - gap)
        ranges[1 - lineDim + 2] = max(ranges[1 - lineDim + 2], corner[2][1 - lineDim] + gap)

        for oppositeOrientationIndex, oppositeCorners in enumerate(orientationPoints):
          if oppositeOrientation not in cornerOrientations[oppositeOrientationIndex]:
            continue
          for oppositeCornerIndex, oppositeCorner in enumerate(oppositeCorners):
            if orientationIndex == oppositeOrientationIndex and oppositeCornerIndex == cornerIndex:
              continue

            oppositePointIndex = pointOffsets[oppositeOrientationIndex] + oppositeCornerIndex


            if oppositeCorner[0][lineDim] < ranges[lineDim] or oppositeCorner[0][lineDim] > ranges[lineDim + 2] or ranges[1 - lineDim] > oppositeCorner[2][1 - lineDim] or ranges[1 - lineDim + 2] < oppositeCorner[1][1 - lineDim]:
              continue


            if abs(oppositeCorner[0][lineDim] - corner[0][lineDim]) < LENGTH_THRESHOLDS[cornerType]:
              continue

            lineIndex = len(lines)
            pointOrientationLinesMap[pointIndex][orientation].append(lineIndex)
            pointOrientationLinesMap[oppositePointIndex][oppositeOrientation].append(lineIndex)
            pointNeighbors[pointIndex].append(oppositePointIndex)
            pointNeighbors[oppositePointIndex].append(pointIndex)

            lines.append((pointIndex, oppositePointIndex))
            continue
          continue
        continue
      continue
    continue
  augmented_points = {}
  # for orientationIndex, corners in enumerate(orientationPoints):
  #   augmented_points[orientationIndex] = []
  orientationMap = {}
  for pointType, orientationOrientations in enumerate(POINT_ORIENTATIONS):
    for orientation, orientations in enumerate(orientationOrientations):
      orientationMap[orientations] = pointType*4 + orientation
      continue
    continue
  # for k,vs in enumerate(pointNeighbors):
  #   for v in vs:
  #     print(points[k], points[v])
  for orientationIndex1, corners1 in enumerate(orientationPoints):
    for cornerIndex1, corner1 in enumerate(corners1):
      pointIndex1 = pointOffsets[orientationIndex1] + cornerIndex1
      point1 = points[pointIndex1]
      for orientationIndex2, corners2 in enumerate(orientationPoints):
        for cornerIndex2, corner2 in enumerate(corners2):
          if orientationIndex2 == orientationIndex1 and cornerIndex2 == cornerIndex1:
            continue
          pointIndex2 = pointOffsets[orientationIndex2] + cornerIndex2
          point2 = points[pointIndex2]
          for orientationIndex3, corners3 in enumerate(orientationPoints):
            for cornerIndex3, corner3 in enumerate(corners3):
              if orientationIndex3 == orientationIndex1 and cornerIndex3 == cornerIndex1:
                continue
              if orientationIndex3 == orientationIndex2 and cornerIndex3 == cornerIndex2:
                continue
              pointIndex3 = pointOffsets[orientationIndex3] + cornerIndex3
              point3 = points[pointIndex3]
              if pointIndex2 in pointNeighbors[pointIndex1] and pointIndex3 in pointNeighbors[pointIndex2]:
                if abs(point1[0] - point3[0]) < gap or abs(point1[1] - point3[1]) < gap:
                  continue
                fourthPoints = set(pointNeighbors[pointIndex1]) & set(pointNeighbors[pointIndex3])
                valid_fourth = []
                for point4 in fourthPoints:
                  if abs(points[point4][0] - point2[0]) > gap and abs(points[point4][1] - point2[1]) > gap:
                    valid_fourth.append(point4)
                    pass
                  pass
                # usable_orientations = set(range(len(POINT_ORIENTATIONS[point1[2]])))
                # used_orientation = set([point1[3], point2[3], point3[3]])
                # fourth_orientation = usable_orientations - used_orientation
                pt2_has = set(POINT_ORIENTATIONS[point2[2]][point2[3]])
                oppositeOrientation2 = set([(orient+2)%4for orient in pt2_has])

                pt1_has = set(POINT_ORIENTATIONS[point1[2]][point1[3]])
                oppositeOrientation1 = set([(orient+2)%4for orient in pt1_has])
                # pt1_needed = oppositeOrientation1 - pt2_has

                pt3_has = set(POINT_ORIENTATIONS[point3[2]][point3[3]])
                oppositeOrientation3 = set([(orient+2)%4for orient in pt3_has])
                # pt3_needed = oppositeOrientation3 - pt2_has
                newPoint_orientation = orientationMap[tuple(oppositeOrientation2)]
                print('orient', newPoint_orientation, oppositeOrientation2)
                if len(valid_fourth) == 0:


                  print('test orientation', oppositeOrientation2, oppositeOrientation1, oppositeOrientation3)
                  newPoint1 = [point1[0], point3[1], newPoint_orientation/4, newPoint_orientation%4]
                  newPoint2 = [point3[0], point1[1], newPoint_orientation/4, newPoint_orientation%4]
                  verify11 = myVerifyCompatibility(oppositeOrientation1, oppositeOrientation2, point1, newPoint1, gap)
                  verify31 = myVerifyCompatibility(oppositeOrientation3, oppositeOrientation2, point3, newPoint1, gap)
                  verify12 = myVerifyCompatibility(oppositeOrientation1, oppositeOrientation2, point1, newPoint2, gap)
                  verify32 = myVerifyCompatibility(oppositeOrientation3, oppositeOrientation2, point3, newPoint2, gap)
                  if abs(newPoint1[0] - point2[0]) > gap and abs(newPoint1[1] - point2[1]) > gap and verify11 and verify31:
                    if newPoint_orientation not in augmented_points:
                      augmented_points[newPoint_orientation] = []
                    print('case1', newPoint1, point1, point2, point3, abs(newPoint1[0] - point2[0]), abs(newPoint1[1]-point2[1]))
                    augmented_points[newPoint_orientation].append(((newPoint1[0], newPoint1[1]) ,(newPoint1[0]-gap, newPoint1[1]-gap), (newPoint1[0]+gap,newPoint1[1]+gap), True))
                    pass
                  elif verify12 and verify32:
                    if newPoint_orientation not in augmented_points:
                      augmented_points[newPoint_orientation] = []
                      pass
                    print('case2', newPoint2, point1, point2, point3, abs(newPoint2[0] - point2[0]), abs(newPoint2[1]-point2[1]))
                    augmented_points[newPoint_orientation].append(((newPoint2[0], newPoint2[1]) ,(newPoint2[0]-gap,newPoint2[1]-gap), (newPoint2[0]+gap,newPoint2[1]+gap), True))
                    pass


                  pass
                pass
              continue
            continue
          continue
        continue
      continue
    continue
  pass

  return augmented_points
def myVerifyCompatibility(orients1, orients2, pt1, pt2, gap):
  verification_set = orients1 & orients2
  passed_verification = False
  for v in verification_set:
    if v == 0:
      if pt2[1] - pt1[1] > 0 and abs(pt1[0] - pt2[0]) < gap:
        passed_verification = True
    if v == 1:
      if pt2[0] - pt1[0] < 0 and abs(pt1[1] - pt2[1]) < gap:
        passed_verification = True
      pass
    if v == 2:
      if pt2[1] - pt1[1] < 0 and abs(pt1[0] - pt2[0]) < gap:
        passed_verification = True
      pass
    if v == 3:
      if pt2[0] - pt1[0] > 0 and abs(pt1[1] - pt2[1]) < gap:
        passed_verification = True
      pass
  return passed_verification

def augmentPoints(points, decreasingTypes = [2], increasingTypes = [1]):
  orientationMap = {}
  for pointType, orientationOrientations in enumerate(POINT_ORIENTATIONS):
    for orientation, orientations in enumerate(orientationOrientations):
      orientationMap[orientations] = orientation
      continue
    continue

  newPoints = []
  for pointIndex, point in enumerate(points):
    if point[2] not in decreasingTypes:
      continue
    orientations = POINT_ORIENTATIONS[point[2]][point[3]]
    for i in range(len(orientations)):
      newOrientations = list(orientations)
      newOrientations.remove(orientations[i])
      newOrientations = tuple(newOrientations)
      if not newOrientations in orientationMap:
        continue
      newOrientation = orientationMap[newOrientations]
      newPoints.append([point[0], point[1], point[2] - 1, newOrientation])
      continue
    continue

  for pointIndex, point in enumerate(points):
    if point[2] not in increasingTypes:
      continue
    orientations = POINT_ORIENTATIONS[point[2]][point[3]]
    for orientation in range(4):
      if orientation in orientations:
        continue

      oppositeOrientation = (orientation + 2) % 4
      ranges = copy.deepcopy(ORIENTATION_RANGES[orientation])
      lineDim = -1
      if orientation == 0 or orientation == 2:
        lineDim = 1
      else:
        lineDim = 0
        pass
      deltas = [0, 0]

      if lineDim == 1:
        deltas[0] = gap
      else:
        deltas[1] = gap
        pass

      for c in range(2):
        ranges[c] = min(ranges[c], point[c] - deltas[c])
        ranges[c + 2] = max(ranges[c + 2], point[c] + deltas[c])
        continue

      hasNeighbor = False
      for neighborPointIndex, neighborPoint in enumerate(points):
        if neighborPointIndex == pointIndex:
          continue

        neighborOrientations = POINT_ORIENTATIONS[neighborPoint[2]][neighborPoint[3]]
        if oppositeOrientation not in neighborOrientations:
          continue

        inRange = True
        for c in range(2):
          if neighborPoint[c] < ranges[c] or neighborPoint[c] > ranges[c + 2]:
            inRange = False
            break
          continue

        if not inRange or abs(neighborPoint[lineDim] - point[lineDim]) < max(abs(neighborPoint[1 - lineDim] - point[1 - lineDim]), 1):
          continue

        hasNeighbor = True
        break

      if not hasNeighbor:
        continue

      newOrientations = list(orientations)
      newOrientations.append(orientation)
      newOrientations = tuple(newOrientations)
      if not newOrientations in orientationMap:
        continue
      newOrientation = orientationMap[newOrientations]
      newPoints.append([point[0], point[1], point[2] + 1, newOrientation])
      continue
    continue
  return points + newPoints


def filterWalls(wallPoints, wallLines):
  orientationMap = {}
  for pointType, orientationOrientations in enumerate(POINT_ORIENTATIONS):
    for orientation, orientations in enumerate(orientationOrientations):
      orientationMap[orientations] = orientation
      continue
    continue

  #print(POINT_ORIENTATIONS)

  while True:
    pointOrientationNeighborsMap = {}
    for line in wallLines:
      lineDim = calcLineDim(wallPoints, line)
      for c, pointIndex in enumerate(line):
        if lineDim == 0:
          if c == 0:
            orientation = 1
          else:
            orientation = 3
        else:
          if c == 0:
            orientation = 2
          else:
            orientation = 0
            pass
          pass

        if pointIndex not in pointOrientationNeighborsMap:
          pointOrientationNeighborsMap[pointIndex] = {}
          pass
        if orientation not in pointOrientationNeighborsMap[pointIndex]:
          pointOrientationNeighborsMap[pointIndex][orientation] = []
          pass
        pointOrientationNeighborsMap[pointIndex][orientation].append(line[1 - c])
        continue
      continue


    invalidPointMask = {}
    for pointIndex, point in enumerate(wallPoints):
      if pointIndex not in pointOrientationNeighborsMap:
        invalidPointMask[pointIndex] = True
        continue
      orientationNeighborMap = pointOrientationNeighborsMap[pointIndex]
      orientations = POINT_ORIENTATIONS[point[2]][point[3]]
      if len(orientationNeighborMap) < len(orientations):
        if len(orientationNeighborMap) >= 2 and tuple(orientationNeighborMap.keys()) in orientationMap:
          newOrientation = orientationMap[tuple(orientationNeighborMap.keys())]
          wallPoints[pointIndex][2] = len(orientationNeighborMap) - 1
          wallPoints[pointIndex][3] = newOrientation
          #print(orientationNeighborMap)
          #print('new', len(orientationNeighborMap), newOrientation)
          continue
        invalidPointMask[pointIndex] = True
        pass
      continue

    if len(invalidPointMask) == 0:
      break

    newWallPoints = []
    pointIndexMap = {}
    for pointIndex, point in enumerate(wallPoints):
      if pointIndex not in invalidPointMask:
        pointIndexMap[pointIndex] = len(newWallPoints)
        newWallPoints.append(point)
        pass
      continue

    print(pointIndexMap)
    # for pointIndex, point in enumerate(wallPoints):
    #   if pointIndex in pointOrientationNeighborsMap:
    #     print(pointIndex, point, pointOrientationNeighborsMap[pointIndex])
    #     pass
    #   continue

    #print(len(wallPoints), len(newWallPoints), len(wallLines))
    #print(invalidPointMask)
    #exit(1)

    wallPoints = newWallPoints

    newWallLines = []
    for lineIndex, line in enumerate(wallLines):
      if line[0] in pointIndexMap and line[1] in pointIndexMap:
        newLine = (pointIndexMap[line[0]], pointIndexMap[line[1]])
        newWallLines.append(newLine)
        pass
      continue
    wallLines = newWallLines
    continue

  pointOrientationLinesMap = [{} for _ in range(len(wallPoints))]
  pointNeighbors = [[] for _ in range(len(wallPoints))]

  #print(wallLines[76])
  #print(wallPoints[wallLines[76][0]], wallPoints[wallLines[76][1]])

  for lineIndex, line in enumerate(wallLines):
    lineDim = calcLineDim(wallPoints, line)
    for c, pointIndex in enumerate(line):
      if lineDim == 0:
        if wallPoints[pointIndex][lineDim] < wallPoints[line[1 - c]][lineDim]:
          orientation = 1
        else:
          orientation = 3
          pass
      else:
        if wallPoints[pointIndex][lineDim] < wallPoints[line[1 - c]][lineDim]:
          orientation = 2
        else:
          orientation = 0
          pass
        pass

      if orientation not in pointOrientationLinesMap[pointIndex]:
        pointOrientationLinesMap[pointIndex][orientation] = []
        pass
      pointOrientationLinesMap[pointIndex][orientation].append(lineIndex)
      pointNeighbors[pointIndex].append(line[1 - c])
      continue
    continue

  return wallPoints, wallLines, pointOrientationLinesMap, pointNeighbors


def filterWallsDynamic(wallPoints, wallLines):
  iteration = 0
  while True:
    pointOrientationNeighborsMap = {}
    for line in wallLines:
      lineDim = calcLineDim(wallPoints, line)
      #print(line, lineDim)

      for c, pointIndex in enumerate(line):
        if lineDim == 0:
          if c == 0:
            orientation = 1
          else:
            orientation = 3
        else:
          if c == 0:
            orientation = 2
          else:
            orientation = 0
            pass
          pass

        if pointIndex not in pointOrientationNeighborsMap:
          pointOrientationNeighborsMap[pointIndex] = {}
          pass
        if orientation not in pointOrientationNeighborsMap[pointIndex]:
          pointOrientationNeighborsMap[pointIndex][orientation] = []
          pass
        pointOrientationNeighborsMap[pointIndex][orientation].append(line[1 - c])
        continue
      continue

    #print(pointOrientationNeighborsMap[3])
    #print(pointOrientationNeighborsMap[8])
    #print(pointOrientationNeighborsMap[12])
    #exit(1)

    invalidPointMask = {}
    for pointIndex, point in enumerate(wallPoints):
      if pointIndex not in pointOrientationNeighborsMap:
        invalidPointMask[pointIndex] = True
        continue
      orientationNeighborMap = pointOrientationNeighborsMap[pointIndex]
      orientations = POINT_ORIENTATIONS[point[2]][point[3]]
      for orientation in orientations:
        if orientation not in orientationNeighborMap:
          invalidPointMask[pointIndex] = True
          break
        continue
      continue

    if len(invalidPointMask) == 0:
      break

    image = drawLines('', width, height, wallPoints, wallLines, [], None, lineWidth=0, lineColor=np.array([0, 0, 128]))
    image = drawPoints('', width, height, wallPoints, image, pointSize=3, pointColor=255)
    cv2.imwrite('test/walls/walls_' + str(iteration) + '.png', image)
    for pointIndex, _ in invalidPointMask.iteritems():
      newImage = image.copy()
      newImage = drawPoints('', width, height, [wallPoints[pointIndex]], newImage, pointSize=3, pointColor=np.array([255, 0, 255]))
      connectingLines = []
      for line in wallLines:
        if pointIndex in line:
          connectingLines.append(line)
          pass
        continue
      print(iteration, pointIndex, wallPoints[pointIndex])
      newImage = drawLines('', width, height, wallPoints, connectingLines, [], newImage, 1, lineColor=np.array([255, 0, 0]))
      cv2.imwrite('test/walls/walls_' + str(iteration) + '_' + str(pointIndex) + '.png', newImage)
      continue

    newWallPoints = []
    pointIndexMap = {}
    for pointIndex, point in enumerate(wallPoints):
      if pointIndex not in invalidPointMask:
        pointIndexMap[pointIndex] = len(newWallPoints)
        newWallPoints.append(point)
        pass
      continue

    # for pointIndex, point in enumerate(wallPoints):
    #   if pointIndex in pointOrientationNeighborsMap:
    #     print(pointIndex, point, pointOrientationNeighborsMap[pointIndex])
    #     pass
    #   continue

    #print(len(wallPoints), len(newWallPoints), len(wallLines))
    #print(invalidPointMask)
    #exit(1)

    wallPoints = newWallPoints

    newWallLines = []
    for lineIndex, line in enumerate(wallLines):
      if line[0] in pointIndexMap and line[1] in pointIndexMap:
        newLine = (pointIndexMap[line[0]], pointIndexMap[line[1]])
        newWallLines.append(newLine)
        pass
      continue
    wallLines = newWallLines
    iteration += 1
    continue

  pointOrientationLinesMap = [{} for _ in range(len(wallPoints))]
  pointNeighbors = [[] for _ in range(len(wallPoints))]

  for lineIndex, line in enumerate(wallLines):
    lineDim = calcLineDim(wallPoints, line)
    for c, pointIndex in enumerate(line):
      if lineDim == 0:
        if c == 0:
          orientation = 1
        else:
          orientation = 3
      else:
        if c == 0:
          orientation = 2
        else:
          orientation = 0
          pass
        pass

      if orientation not in pointOrientationLinesMap[pointIndex]:
        pointOrientationLinesMap[pointIndex][orientation] = []
        pass
      pointOrientationLinesMap[pointIndex][orientation].append(lineIndex)
      pointNeighbors[pointIndex].append(line[1 - c])
      continue
    continue

  return wallPoints, wallLines, pointOrientationLinesMap, pointNeighbors


def writePoints(points, pointLabels):
  with open('test/points_out.txt', 'w') as points_file:
    for point in points:
      points_file.write(str(point[0] + 1) + '\t' + str(point[1] + 1) + '\t')
      points_file.write(str(point[0] + 1) + '\t' + str(point[1] + 1) + '\t')
      points_file.write('point\t')
      points_file.write(str(point[2] + 1) + '\t' + str(point[3] + 1) + '\n')
  points_file.close()

  with open('test/point_labels.txt', 'w') as point_label_file:
    for point in pointLabels:
      point_label_file.write(str(point[0]) + '\t' + str(point[1]) + '\t' + str(point[2]) + '\t' + str(point[3]) + '\n')
  point_label_file.close()

def writeDoors(points, lines, doorTypes):
  with open('test/doors_out.txt', 'w') as doors_file:
    for lineIndex, line in enumerate(lines):
      point_1 = points[line[0]]
      point_2 = points[line[1]]

      doors_file.write(str(point_1[0] + 1) + '\t' + str(point_1[1] + 1) + '\t')
      doors_file.write(str(point_2[0] + 1) + '\t' + str(point_2[1] + 1) + '\t')
      doors_file.write('door\t')
      doors_file.write(str(doorTypes[lineIndex] + 1) + '\t1\n')
    doors_file.close()

def writeIcons(points, icons, iconTypes):
  with open('test/icons_out.txt', 'w') as icons_file:
    for iconIndex, icon in enumerate(icons):
      point_1 = points[icon[0]]
      point_2 = points[icon[1]]
      point_3 = points[icon[2]]
      point_4 = points[icon[3]]

      x_1 = int(round((point_1[0] + point_3[0]) / 2)) + 1
      x_2 = int(round((point_2[0] + point_4[0]) / 2)) + 1
      y_1 = int(round((point_1[1] + point_2[1]) / 2)) + 1
      y_2 = int(round((point_3[1] + point_4[1]) / 2)) + 1

      icons_file.write(str(x_1) + '\t' + str(y_1) + '\t')
      icons_file.write(str(x_2) + '\t' + str(y_2) + '\t')
      icons_file.write(iconNumberNameMap[iconTypes[iconIndex]] + '\t')
      #icons_file.write(str(iconNumberStyleMap[iconTypes[iconIndex]]) + '\t')
      icons_file.write('1\t')
      icons_file.write('1\n')
    icons_file.close()


def adjustPoints(points, lines):
  lineNeighbors = []
  for lineIndex, line in enumerate(lines):
    lineDim = calcLineDim(points, line)
    neighbors = []
    for neighborLineIndex, neighborLine in enumerate(lines):
      if neighborLineIndex <= lineIndex:
        continue
      neighborLineDim = calcLineDim(points, neighborLine)
      point_1 = points[neighborLine[0]]
      point_2 = points[neighborLine[1]]
      lineDimNeighbor = calcLineDim(points, neighborLine)

      if lineDimNeighbor != lineDim:
        continue
      if neighborLine[0] != line[0] and neighborLine[0] != line[1] and neighborLine[1] != line[0] and neighborLine[1] != line[1]:
        continue
      neighbors.append(neighborLineIndex)
      continue
    lineNeighbors.append(neighbors)
    continue

  visitedLines = {}
  for lineIndex in range(len(lines)):
    if lineIndex in visitedLines:
      continue
    lineGroup = [lineIndex]
    while True:
      newLineGroup = lineGroup
      hasChange = False
      for line in lineGroup:
        neighbors = lineNeighbors[line]
        for neighbor in neighbors:
          if neighbor not in newLineGroup:
            newLineGroup.append(neighbor)
            hasChange = True
            pass
          continue
        continue
      if not hasChange:
        break
      lineGroup = newLineGroup
      continue

    for line in lineGroup:
      visitedLines[line] = True
      continue

    #print([[points[pointIndex] for pointIndex in lines[lineIndex]] for lineIndex in lineGroup], calcLineDim(points, lines[lineGroup[0]]))

    pointGroup = []
    for line in lineGroup:
      for index in range(2):
        pointIndex = lines[line][index]
        if pointIndex not in pointGroup:
          pointGroup.append(pointIndex)
          pass
        continue
      continue

    #lineDim = calcLineDim(points, lines[lineGroup[0]])
    xy = np.concatenate([np.array([points[pointIndex][:2] for pointIndex in lines[lineIndex]]) for lineIndex in lineGroup], axis=0)
    mins = xy.min(0)
    maxs = xy.max(0)
    if maxs[0] - mins[0] > maxs[1] - mins[1]:
      lineDim = 0
    else:
      lineDim = 1
      pass

    fixedValue = 0
    for point in pointGroup:
      fixedValue += points[point][1 - lineDim]
      continue
    fixedValue /= len(pointGroup)

    for point in pointGroup:
      points[point][1 - lineDim] = fixedValue
      continue
    continue
  return

def mergePoints(points, lines):
  validPointMask = {}
  for line in lines:
    validPointMask[line[0]] = True
    validPointMask[line[1]] = True
    continue

  orientationMap = {}
  for pointType, orientationOrientations in enumerate(POINT_ORIENTATIONS):
    for orientation, orientations in enumerate(orientationOrientations):
      orientationMap[orientations] = (pointType, orientation)
      continue
    continue

  for pointIndex_1, point_1 in enumerate(points):
    if pointIndex_1 not in validPointMask:
      continue
    for pointIndex_2, point_2 in enumerate(points):
      if pointIndex_2 <= pointIndex_1:
        continue
      if pointIndex_2 not in validPointMask:
        continue
      if pointDistance(point_1[:2], point_2[:2]) <= DISTANCES['point']:
        orientations = list(POINT_ORIENTATIONS[point_1[2]][point_1[3]] + POINT_ORIENTATIONS[point_2[2]][point_2[3]])
        if len([line for line in lines if pointIndex_1 in line and pointIndex_2 in line]) > 0:
          if abs(point_1[0] - point_2[0]) > abs(point_1[1] - point_2[1]):
            orientations.remove(1)
            orientations.remove(3)
          else:
            orientations.remove(0)
            orientations.remove(2)
            pass
          pass
        orientations = tuple(set(orientations))
        if orientations not in orientationMap:
          for lineIndex, line in enumerate(lines):
            if pointIndex_1 in line and pointIndex_2 in line:
              lines[lineIndex] = (-1, -1)
              pass
            continue

          lineIndices_1 = [(lineIndex, tuple(set(line) - set((pointIndex_1, )))[0]) for lineIndex, line in enumerate(lines) if pointIndex_1 in line and pointIndex_2 not in line]
          lineIndices_2 = [(lineIndex, tuple(set(line) - set((pointIndex_2, )))[0]) for lineIndex, line in enumerate(lines) if pointIndex_2 in line and pointIndex_1 not in line]
          if len(lineIndices_1) == 1 and len(lineIndices_2) == 1:
            lineIndex_1, index_1 = lineIndices_1[0]
            lineIndex_2, index_2 = lineIndices_2[0]
            lines[lineIndex_1] = (index_1, index_2)
            lines[lineIndex_2] = (-1, -1)
            pass
          continue

        pointInfo = orientationMap[orientations]
        newPoint = [(point_1[0] + point_2[0]) / 2, (point_1[1] + point_2[1]) / 2, pointInfo[0], pointInfo[1]]
        points[pointIndex_1] = newPoint
        for lineIndex, line in enumerate(lines):
          if pointIndex_2 == line[0]:
            lines[lineIndex] = (pointIndex_1, line[1])
            pass
          if pointIndex_2 == line[1]:
            lines[lineIndex] = (line[0], pointIndex_1)
            pass
          continue
        pass
      continue
    continue
  return

def adjustDoorPoints(doorPoints, doorLines, wallPoints, wallLines, doorWallMap):
  for doorLineIndex, doorLine in enumerate(doorLines):
    lineDim = calcLineDim(doorPoints, doorLine)
    wallLine = wallLines[doorWallMap[doorLineIndex]]
    wallPoint_1 = wallPoints[wallLine[0]]
    wallPoint_2 = wallPoints[wallLine[1]]
    fixedValue = (wallPoint_1[1 - lineDim] + wallPoint_2[1 - lineDim]) / 2
    for endPointIndex in range(2):
      doorPoints[doorLine[endPointIndex]][1 - lineDim] = fixedValue
      continue
    continue


def findIconsFromLines(iconPoints, iconLines):
  icons = []
  pointOrientationNeighborsMap = {}
  for line in iconLines:
    lineDim = calcLineDim(iconPoints, line)
    for c, pointIndex in enumerate(line):
      if lineDim == 0:
        if c == 0:
          orientation = 1
        else:
          orientation = 3
      else:
        if c == 0:
          orientation = 2
        else:
          orientation = 0
          pass
        pass

      if pointIndex not in pointOrientationNeighborsMap:
        pointOrientationNeighborsMap[pointIndex] = {}
        pass
      if orientation not in pointOrientationNeighborsMap[pointIndex]:
        pointOrientationNeighborsMap[pointIndex][orientation] = []
        pass
      pointOrientationNeighborsMap[pointIndex][orientation].append(line[1 - c])
      continue
    continue

  for pointIndex, orientationNeighborMap in pointOrientationNeighborsMap.iteritems():
    if 1 not in orientationNeighborMap or 2 not in orientationNeighborMap:
      continue
    for neighborIndex_1 in orientationNeighborMap[1]:
      if 2 not in pointOrientationNeighborsMap[neighborIndex_1]:
        continue
      lastCornerCandiates = pointOrientationNeighborsMap[neighborIndex_1][2]
      for neighborIndex_2 in orientationNeighborMap[2]:
        if 1 not in pointOrientationNeighborsMap[neighborIndex_2]:
          continue
        for lastCornerIndex in pointOrientationNeighborsMap[neighborIndex_2][1]:
          if lastCornerIndex not in lastCornerCandiates:
            continue

          point_1 = iconPoints[pointIndex]
          point_2 = iconPoints[neighborIndex_1]
          point_3 = iconPoints[neighborIndex_2]
          point_4 = iconPoints[lastCornerIndex]

          x_1 = int((point_1[0] + point_3[0]) / 2)
          x_2 = int((point_2[0] + point_4[0]) / 2)
          y_1 = int((point_1[1] + point_2[1]) / 2)
          y_2 = int((point_3[1] + point_4[1]) / 2)

          #if x_2 <= x_1 or y_2 <= y_1:
          #continue
          if (x_2 - x_1 + 1) * (y_2 - y_1 + 1) <= LENGTH_THRESHOLDS['icon'] * LENGTH_THRESHOLDS['icon']:
            continue

          icons.append((pointIndex, neighborIndex_1, neighborIndex_2, lastCornerIndex))
          continue
        continue
      continue
    continue
  return icons


def findLineNeighbors(points, lines, labelVotesMap, gap):
  lineNeighbors = [[{}, {}] for lineIndex in range(len(lines))]
  for lineIndex, line in enumerate(lines):
    lineDim = calcLineDim(points, line)
    for neighborLineIndex, neighborLine in enumerate(lines):
      if neighborLineIndex <= lineIndex:
        continue
      neighborLineDim = calcLineDim(points, neighborLine)
      if lineDim != neighborLineDim:
        continue

      minValue = max(points[line[0]][lineDim], points[neighborLine[0]][lineDim])
      maxValue = min(points[line[1]][lineDim], points[neighborLine[1]][lineDim])
      if maxValue - minValue < gap:
        continue
      fixedValue_1 = points[line[0]][1 - lineDim]
      fixedValue_2 = points[neighborLine[0]][1 - lineDim]

      minValue = int(minValue)
      maxValue = int(maxValue)
      fixedValue_1 = int(fixedValue_1)
      fixedValue_2 = int(fixedValue_2)

      if abs(fixedValue_2 - fixedValue_1) < gap:
        continue
      if lineDim == 0:
        if fixedValue_1 < fixedValue_2:
          region = ((minValue, fixedValue_1), (maxValue, fixedValue_2))
          lineNeighbors[lineIndex][1][neighborLineIndex] = region
          lineNeighbors[neighborLineIndex][0][lineIndex] = region
        else:
          region = ((minValue, fixedValue_2), (maxValue, fixedValue_1))
          lineNeighbors[lineIndex][0][neighborLineIndex] = region
          lineNeighbors[neighborLineIndex][1][lineIndex] = region
      else:
        if fixedValue_1 < fixedValue_2:
          region = ((fixedValue_1, minValue), (fixedValue_2, maxValue))
          lineNeighbors[lineIndex][0][neighborLineIndex] = region
          lineNeighbors[neighborLineIndex][1][lineIndex] = region
        else:
          region = ((fixedValue_2, minValue), (fixedValue_1, maxValue))
          lineNeighbors[lineIndex][1][neighborLineIndex] = region
          lineNeighbors[neighborLineIndex][0][lineIndex] = region
          pass
        pass
      continue
    continue

  # remove neighbor pairs which are separated by another line
  while True:
    hasChange = False
    for lineIndex, neighbors in enumerate(lineNeighbors):
      lineDim = calcLineDim(points, lines[lineIndex])
      for neighbor_1, region_1 in neighbors[1].iteritems():
        for neighbor_2, _ in neighbors[0].iteritems():
          if neighbor_2 not in lineNeighbors[neighbor_1][0]:
            continue
          region_2 = lineNeighbors[neighbor_1][0][neighbor_2]
          if region_1[0][lineDim] < region_2[0][lineDim] + gap and region_1[1][lineDim] > region_2[1][lineDim] - gap:
            lineNeighbors[neighbor_1][0].pop(neighbor_2)
            lineNeighbors[neighbor_2][1].pop(neighbor_1)
            hasChange = True
            pass
          continue
        continue
      continue
    if not hasChange:
      break


  for lineIndex, directionNeighbors in enumerate(lineNeighbors):
    for direction, neighbors in enumerate(directionNeighbors):
      for neighbor, region in neighbors.iteritems():
        labelVotes = labelVotesMap[:, region[1][1], region[1][0]] + labelVotesMap[:, region[0][1], region[0][0]] - labelVotesMap[:, region[0][1], region[1][0]] - labelVotesMap[:, region[1][1], region[0][0]]
        neighbors[neighbor] = labelVotes
        continue
      continue
    continue
  return lineNeighbors


def findRectangleLineNeighbors(rectanglePoints, rectangles, linePoints, lines, lineNeighbors, gap, distanceThreshold):
  rectangleLineNeighbors = [{} for rectangleIndex in range(len(rectangles))]
  minDistanceLineNeighbors = {}
  for rectangleIndex, rectangle in enumerate(rectangles):
    for lineIndex, line in enumerate(lines):
      lineDim = calcLineDim(linePoints, line)

      minValue = max(rectanglePoints[rectangle[0]][lineDim], rectanglePoints[rectangle[2 - lineDim]][lineDim], linePoints[line[0]][lineDim])
      maxValue = min(rectanglePoints[rectangle[1 + lineDim]][lineDim], rectanglePoints[rectangle[3]][lineDim], linePoints[line[1]][lineDim])

      if maxValue - minValue < gap:
        continue

      rectangleFixedValue_1 = (rectanglePoints[rectangle[0]][1 - lineDim] + rectanglePoints[rectangle[1 + lineDim]][1 - lineDim]) / 2
      rectangleFixedValue_2 = (rectanglePoints[rectangle[2 - lineDim]][1 - lineDim] + rectanglePoints[rectangle[3]][1 - lineDim]) / 2
      lineFixedValue = (linePoints[line[0]][1 - lineDim] + linePoints[line[1]][1 - lineDim]) / 2

      if lineFixedValue < rectangleFixedValue_2 - gap and lineFixedValue > rectangleFixedValue_1 + gap:
        continue

      if lineFixedValue <= rectangleFixedValue_1 + gap:
        index = lineDim * 2 + 0
        distance = rectangleFixedValue_1 - lineFixedValue
        if index not in minDistanceLineNeighbors or distance < minDistanceLineNeighbors[index][1]:
          minDistanceLineNeighbors[index] = (lineIndex, distance, 1 - lineDim)
      else:
        index = lineDim * 2 + 1
        distance = lineFixedValue - rectangleFixedValue_2
        if index not in minDistanceLineNeighbors or distance < minDistanceLineNeighbors[index][1]:
          minDistanceLineNeighbors[index] = (lineIndex, distance, lineDim)

      if lineFixedValue < rectangleFixedValue_1 - distanceThreshold or lineFixedValue > rectangleFixedValue_2 + distanceThreshold:
        continue

      if lineFixedValue <= rectangleFixedValue_1 + gap:
        if lineDim == 0:
          rectangleLineNeighbors[rectangleIndex][lineIndex] = 1
        else:
          rectangleLineNeighbors[rectangleIndex][lineIndex] = 0
          pass
        pass
      else:
        if lineDim == 0:
          rectangleLineNeighbors[rectangleIndex][lineIndex] = 0
        else:
          rectangleLineNeighbors[rectangleIndex][lineIndex] = 1
          pass
        pass

      continue
    if len(rectangleLineNeighbors[rectangleIndex]) == 0 or True:
      for index, lineNeighbor in minDistanceLineNeighbors.iteritems():
        rectangleLineNeighbors[rectangleIndex][lineNeighbor[0]] = lineNeighbor[2]
        continue
      pass
    continue

  return rectangleLineNeighbors


def findLineMap(points, lines, points_2, lines_2, gap):
  lineMap = [{} for lineIndex in range(len(lines))]
  for lineIndex, line in enumerate(lines):
    lineDim = calcLineDim(points, line)
    for neighborLineIndex, neighborLine in enumerate(lines_2):
      neighborLineDim = calcLineDim(points_2, neighborLine)
      if lineDim != neighborLineDim:
        continue

      minValue = max(points[line[0]][lineDim], points_2[neighborLine[0]][lineDim])
      maxValue = min(points[line[1]][lineDim], points_2[neighborLine[1]][lineDim])
      if maxValue - minValue < gap:
        continue
      fixedValue_1 = (points[line[0]][1 - lineDim] + points[line[1]][1 - lineDim]) / 2
      fixedValue_2 = (points_2[neighborLine[0]][1 - lineDim] + points_2[neighborLine[1]][1 - lineDim]) / 2

      if abs(fixedValue_2 - fixedValue_1) > gap:
        continue

      lineMinValue = points[line[0]][lineDim]
      lineMaxValue = points[line[1]][lineDim]
      ratio = float(maxValue - minValue + 1) / (lineMaxValue - lineMinValue + 1)

      lineMap[lineIndex][neighborLineIndex] = ratio
      continue
    continue

  return lineMap


def findLineMapSingle(points, lines, points_2, lines_2, gap):
  lineMap = []
  for lineIndex, line in enumerate(lines):
    lineDim = calcLineDim(points, line)
    minDistance = max(width, height)
    minDistanceLineIndex = -1
    for neighborLineIndex, neighborLine in enumerate(lines_2):
      neighborLineDim = calcLineDim(points_2, neighborLine)
      if lineDim != neighborLineDim:
        continue

      minValue = max(points[line[0]][lineDim], points_2[neighborLine[0]][lineDim])
      maxValue = min(points[line[1]][lineDim], points_2[neighborLine[1]][lineDim])
      if maxValue - minValue < gap:
        continue
      fixedValue_1 = (points[line[0]][1 - lineDim] + points[line[1]][1 - lineDim]) / 2
      fixedValue_2 = (points_2[neighborLine[0]][1 - lineDim] + points_2[neighborLine[1]][1 - lineDim]) / 2

      distance = abs(fixedValue_2 - fixedValue_1)
      if distance < minDistance:
        minDistance = distance
        minDistanceLineIndex = neighborLineIndex
        pass
      continue

    #if abs(fixedValue_2 - fixedValue_1) > gap:
    #continue
    #print((lineIndex, minDistance, minDistanceLineIndex))
    lineMap.append(minDistanceLineIndex)
    continue

  return lineMap


def findConflictLinePairs(points, lines, gap, distanceThreshold, considerEndPoints=False):
  conflictLinePairs = []
  for lineIndex_1, line_1 in enumerate(lines):
    lineDim_1 = calcLineDim(points, line_1)
    point_1 = points[line_1[0]]
    point_2 = points[line_1[1]]
    fixedValue_1 = int(round((point_1[1 - lineDim_1] + point_2[1 - lineDim_1]) / 2))
    minValue_1 = int(min(point_1[lineDim_1], point_2[lineDim_1]))
    maxValue_1 = int(max(point_1[lineDim_1], point_2[lineDim_1]))

    for lineIndex_2, line_2 in enumerate(lines):
      if lineIndex_2 <= lineIndex_1:
        continue

      lineDim_2 = calcLineDim(points, line_2)
      point_1 = points[line_2[0]]
      point_2 = points[line_2[1]]

      if lineDim_2 == lineDim_1:
        if line_1[0] == line_2[0] or line_1[1] == line_2[1]:
          conflictLinePairs.append((lineIndex_1, lineIndex_2))
          continue
        elif line_1[0] == line_2[1] or line_1[1] == line_2[0]:
          continue
        pass
      else:
        if (line_1[0] in line_2 or line_1[1] in line_2):
          continue
        pass

      if considerEndPoints:
        if min([pointDistance(points[line_1[0]], points[line_2[0]]), pointDistance(points[line_1[0]], points[line_2[1]]), pointDistance(points[line_1[1]], points[line_2[0]]), pointDistance(points[line_1[1]], points[line_2[1]])]) <= gap:
          conflictLinePairs.append((lineIndex_1, lineIndex_2))
          continue
        pass

      fixedValue_2 = int(round((point_1[1 - lineDim_2] + point_2[1 - lineDim_2]) / 2))
      minValue_2 = int(min(point_1[lineDim_2], point_2[lineDim_2]))
      maxValue_2 = int(max(point_1[lineDim_2], point_2[lineDim_2]))

      # if lineIndex_1 == 3 and lineIndex_2 == 4:
      #   print(line_1)
      #   print(line_2)
      #   print(points[line_1[0]])
      #   print(points[line_1[1]])
      #   print(point_1)
      #   print(point_2)
      #   print((fixedValue_2, fixedValue_1, minValue_1, maxValue_2))
      #   exit(1)

      if lineDim_1 == lineDim_2:
        if abs(fixedValue_2 - fixedValue_1) >= distanceThreshold or minValue_1 > maxValue_2 - gap or minValue_2 > maxValue_1 - gap:
          continue

        #print('parallel', lineIndex_1, lineIndex_2)
        #print([points[pointIndex] for pointIndex in lines[lineIndex_1]], [points[pointIndex] for pointIndex in lines[lineIndex_2]])

        conflictLinePairs.append((lineIndex_1, lineIndex_2))
        #drawLines('test/lines_' + str(lineIndex_1) + "_" + str(lineIndex_2) + '.png', width, height, points, [line_1, line_2])
      else:
        if minValue_1 > fixedValue_2 - gap or maxValue_1 < fixedValue_2 + gap or minValue_2 > fixedValue_1 - gap or maxValue_2 < fixedValue_1 + gap:
          continue

        #print('vertical', lineIndex_1, lineIndex_2)
        #print([points[pointIndex] for pointIndex in lines[lineIndex_1]], [points[pointIndex] for pointIndex in lines[lineIndex_2]])

        conflictLinePairs.append((lineIndex_1, lineIndex_2))
        pass
      continue
    continue

  return conflictLinePairs


def findConflictRectanglePairs(points, rectangles, gap):
  conflictRectanglePairs = []
  for rectangleIndex_1, rectangle_1 in enumerate(rectangles):
    for rectangleIndex_2, rectangle_2 in enumerate(rectangles):
      if rectangleIndex_2 <= rectangleIndex_1:
        continue

      conflict = False
      for cornerIndex in range(4):
        if rectangle_1[cornerIndex] == rectangle_2[cornerIndex]:
          conflictRectanglePairs.append((rectangleIndex_1, rectangleIndex_2))
          conflict = True
          break
        continue

      if conflict:
        continue

      minX = max((points[rectangle_1[0]][0] + points[rectangle_1[2]][0]) / 2, (points[rectangle_2[0]][0] + points[rectangle_2[2]][0]) / 2)
      maxX = min((points[rectangle_1[1]][0] + points[rectangle_1[3]][0]) / 2, (points[rectangle_2[1]][0] + points[rectangle_2[3]][0]) / 2)
      if minX > maxX - gap:
        continue
      minY = max((points[rectangle_1[0]][1] + points[rectangle_1[1]][1]) / 2, (points[rectangle_2[0]][1] + points[rectangle_2[1]][1]) / 2)
      maxY = min((points[rectangle_1[2]][1] + points[rectangle_1[3]][1]) / 2, (points[rectangle_2[2]][1] + points[rectangle_2[3]][1]) / 2)
      if minY > maxY - gap:
        continue
      conflictRectanglePairs.append((rectangleIndex_1, rectangleIndex_2))
      continue
    continue

  return conflictRectanglePairs


def findConflictRectangleLinePairs(rectanglePoints, rectangles, linePoints, lines, gap):
  conflictRectangleLinePairs = []
  for rectangleIndex, rectangle in enumerate(rectangles):
    for lineIndex, line in enumerate(lines):
      # for c in range(4):
      #   print(rectanglePoints[rectangle[c]])
      #   continue
      # for c in range(2):
      #   print(linePoints[line[c]])
      #   continue
      lineDim = calcLineDim(linePoints, line)
      if lineDim == 0:
        minX = max(rectanglePoints[rectangle[0]][0], rectanglePoints[rectangle[2]][0], linePoints[line[0]][0])
        maxX = min(rectanglePoints[rectangle[1]][0], rectanglePoints[rectangle[3]][0], linePoints[line[1]][0])
        if minX > maxX - gap:
          continue
        if max(rectanglePoints[rectangle[0]][1], rectanglePoints[rectangle[1]][1]) + gap > min(linePoints[line[0]][1], linePoints[line[1]][1]):
          continue
        if min(rectanglePoints[rectangle[2]][1], rectanglePoints[rectangle[3]][1]) - gap < max(linePoints[line[0]][1], linePoints[line[1]][1]):
          continue

      elif lineDim == 1:
        minY = max(rectanglePoints[rectangle[0]][1], rectanglePoints[rectangle[1]][1], linePoints[line[0]][1])
        maxY = min(rectanglePoints[rectangle[2]][1], rectanglePoints[rectangle[3]][1], linePoints[line[1]][1])
        if minY > maxY - gap:
          continue
        if max(rectanglePoints[rectangle[0]][0], rectanglePoints[rectangle[2]][0]) + gap > min(linePoints[line[0]][0], linePoints[line[1]][0]):
          continue
        if min(rectanglePoints[rectangle[1]][0], rectanglePoints[rectangle[3]][0]) - gap < max(linePoints[line[0]][0], linePoints[line[1]][0]):
          continue

      conflictRectangleLinePairs.append((rectangleIndex, lineIndex))
      continue
    continue

  return conflictRectangleLinePairs

def findLinePointMap(points, lines, points_2, gap):
  lineMap = [[] for lineIndex in range(len(lines))]
  for lineIndex, line in enumerate(lines):
    lineDim = calcLineDim(points, line)
    fixedValue = (points[line[0]][1 - lineDim] + points[line[1]][1 - lineDim]) / 2
    for neighborPointIndex, neighborPoint in enumerate(points_2):
      if neighborPoint[lineDim] < points[line[0]][lineDim] + gap or neighborPoint[lineDim] > points[line[1]][lineDim] - gap:
        continue

      if abs((neighborPoint[1 - lineDim] + neighborPoint[1 - lineDim]) / 2 - fixedValue) > gap:
        continue

      lineMap[lineIndex].append(neighborPointIndex)
      continue
    continue
  return lineMap

def scalePoints(points, sampleDim):
  for point in points:
    point[0] *= width / sampleDim
    point[1] *= height / sampleDim
    continue
  return points

def findCandidatesFromHeatmaps(iconHeatmaps, iconPointOffset, doorPointOffset):
  newIcons = []
  newIconPoints = []
  newDoorLines = []
  newDoorPoints = []
  for iconIndex in range(1, 13):
    heatmap = iconHeatmaps[:, :, iconIndex] > 0.5
    kernel = np.ones((3, 3), dtype=np.uint8)
    heatmap = cv2.dilate(cv2.erode(heatmap.astype(np.uint8), kernel), kernel)
    regions = measure.label(heatmap, background=0)
    for regionIndex in range(regions.min() + 1, regions.max() + 1):
      regionMask = regions == regionIndex
      ys, xs = regionMask.nonzero()
      minX, maxX = xs.min(), xs.max()
      minY, maxY = ys.min(), ys.max()
      if iconIndex <= 10:
        if maxX - minX < GAPS['icon_extraction'] or maxY - minY < GAPS['icon_extraction']:
          continue
        mask = regionMask[minY:maxY + 1, minX:maxX + 1]
        sizeX, sizeY = maxX - minX + 1, maxY - minY + 1
        sumX = mask.sum(0)

        for x in range(sizeX):
          if sumX[x] * 2 >= sizeY:
            break
          minX += 1
          continue

        for x in range(sizeX - 1, -1, -1):
          if sumX[x] * 2 >= sizeY:
            break
          maxX -= 1
          continue


        sumY = mask.sum(1)
        for y in range(sizeY):
          if sumY[y] * 2 >= sizeX:
            break
          minY += 1
          continue

        for y in range(sizeY - 1, -1, -1):
          if sumY[y] * 2 >= sizeX:
            break
          maxY -= 1
          continue
        if (maxY - minY + 1) * (maxX - minX + 1) <= LENGTH_THRESHOLDS['icon'] * LENGTH_THRESHOLDS['icon'] * 2:
          continue
        newIconPoints += [[minX, minY, 1, 2], [maxX, minY, 1, 3], [minX, maxY, 1, 1], [maxX, maxY, 1, 0]]
        newIcons.append((iconPointOffset, iconPointOffset + 1, iconPointOffset + 2, iconPointOffset + 3))
        iconPointOffset += 4
      else:
        sizeX, sizeY = maxX - minX + 1, maxY - minY + 1
        if sizeX >= LENGTH_THRESHOLDS['door'] and sizeY * 2 <= sizeX:
          newDoorPoints += [[minX, (minY + maxY) / 2, 0, 1], [maxX, (minY + maxY) / 2, 0, 3]]
          newDoorLines.append((doorPointOffset, doorPointOffset + 1))
          doorPointOffset += 2
        elif sizeY >= LENGTH_THRESHOLDS['door'] and sizeX * 2 <= sizeY:
          newDoorPoints += [[(minX + maxX) / 2, minY, 0, 2], [(minX + maxX) / 2, maxY, 0, 0]]
          newDoorLines.append((doorPointOffset, doorPointOffset + 1))
          doorPointOffset += 2
        elif sizeX >= LENGTH_THRESHOLDS['door'] and sizeY >= LENGTH_THRESHOLDS['door']:
          mask = regionMask[minY:maxY + 1, minX:maxX + 1]
          sumX = mask.sum(0)
          minOffset, maxOffset = 0, 0
          for x in range(sizeX):
            if sumX[x] * 2 >= sizeY:
              break
            minOffset += 1
            continue

          for x in range(sizeX - 1, -1, -1):
            if sumX[x] * 2 >= sizeY:
              break
            maxOffset += 1
            continue

          if (sizeX - minOffset - maxOffset) * 2 <= sizeY and sizeX - minOffset - maxOffset > 0:
            newDoorPoints += [[(minX + minOffset + maxX - maxOffset) / 2, minY, 0, 2], [(minX + minOffset + maxX - maxOffset) / 2, maxY, 0, 0]]
            newDoorLines.append((doorPointOffset, doorPointOffset + 1))
            doorPointOffset += 2
            pass

          sumY = mask.sum(1)
          minOffset, maxOffset = 0, 0
          for y in range(sizeY):
            if sumY[y] * 2 >= sizeX:
              break
            minOffset += 1
            continue

          for y in range(sizeY - 1, -1, -1):
            if sumY[y] * 2 >= sizeX:
              break
            maxOffset += 1
            continue

          if (sizeY - minOffset - maxOffset) * 2 <= sizeX and sizeY - minOffset - maxOffset > 0:
            newDoorPoints += [[minX, (minY + minOffset + maxY - maxOffset) / 2, 0, 1], [maxX, (minY + minOffset + maxY - maxOffset) / 2, 0, 3]]
            newDoorLines.append((doorPointOffset, doorPointOffset + 1))
            doorPointOffset += 2
            pass
          pass
        pass
      continue
    continue
  return newIcons, newIconPoints, newDoorLines, newDoorPoints

def sortLines(points, lines):
  for lineIndex, line in enumerate(lines):
    lineDim = calcLineDim(points, line)
    if points[line[0]][lineDim] > points[line[1]][lineDim]:
      lines[lineIndex] = (line[1], line[0])
      pass
    continue

def reconstructFloorplan(wallCornerHeatmaps, doorCornerHeatmaps, iconCornerHeatmaps, iconHeatmaps, roomHeatmaps, densityImage=None, gt_dict=None, gt=False, gap=-1, distanceThreshold=-1, lengthThreshold=-1, debug_prefix='test', heatmapValueThresholdWall=None, heatmapValueThresholdDoor=None, heatmapValueThresholdIcon=None):
  print('reconstruct')

  wallPoints = []
  iconPoints = []
  doorPoints = []
  if withoutQP:
    numWallPoints = 30
    numDoorPoints = 30
    numIconPoints = 30
    heatmapValueThresholdWall = 0.5
    heatmapValueThresholdDoor = 0.5
    heatmapValueThresholdIcon = 0.5
  else:
    numWallPoints = 100
    numDoorPoints = 100
    numIconPoints = 100
    if heatmapValueThresholdWall is None:
      heatmapValueThresholdWall = 0.5

    heatmapValueThresholdDoor = 0.5

    heatmapValueThresholdIcon = 0.5
    pass

  if gap > 0:
    for k in GAPS:
      GAPS[k] = gap
      continue
    pass
  if distanceThreshold > 0:
    for k in DISTANCES:
      DISTANCES[k] = distanceThreshold
      continue
    pass
  if lengthThreshold > 0:
    for k in LENGTH_THRESHOLDS:
      LENGTH_THRESHOLDS[k] = lengthThreshold
      continue
    pass
  enable_augment = not gt
  enable_augment = False
  wallPoints, wallLines, wallPointOrientationLinesMap, wallPointNeighbors, augmentedPointMask = extractCorners(wallCornerHeatmaps, heatmapValueThresholdWall, gap=GAPS['wall_extraction'], augment=enable_augment, h_points=enable_augment, gt=gt)
  doorPoints, doorLines, doorPointOrientationLinesMap, doorPointNeighbors, _ = extractCorners(doorCornerHeatmaps, heatmapValueThresholdDoor, gap=GAPS['door_extraction'], cornerType='door', gt=gt)
  iconPoints, iconLines, iconPointOrientationLinesMap, iconPointNeighbors, _ = extractCorners(iconCornerHeatmaps, heatmapValueThresholdIcon, gap=GAPS['icon_extraction'], cornerType='icon', gt=gt)

  if not gt:
    #print([[wallPoints[pointIndex] for pointIndex in wallLines[wallIndex]] for wallIndex in range(len(wallLines))])
    for pointIndex, point in enumerate(wallPoints):
      print((pointIndex, np.array(point[:2]).astype(np.int32).tolist(), point[2], point[3]))
      continue
    # print(wallPoints[19])
    # print(wallPointNeighbors[19])
    # print(wallPointOrientationLinesMap[19])

    wallPoints, wallLines, wallPointOrientationLinesMap, wallPointNeighbors = filterWalls(wallPoints, wallLines)
    #wallPoints, wallLines, wallPointOrientationLinesMap, wallPointNeighbors = filterWallsDynamic(wallPoints, wallLines)
    #print('after filtering')
    #print([[wallPoints[pointIndex] for pointIndex in wallLines[wallIndex]] for wallIndex in range(len(wallLines))])

    # for pointIndex, point in enumerate(wallPoints):
    #   print((pointIndex, np.array(point[:2]).astype(np.int32).tolist(), point[2], point[3]))
    #   continue
    # print(wallPoints[15])
    # print(wallPointNeighbors[15])
    # print(wallPointOrientationLinesMap[15])
    # exit(1)
    pass


  sortLines(doorPoints, doorLines)
  sortLines(wallPoints, wallLines)

  print('the number of points', len(wallPoints), len(doorPoints), len(iconPoints))
  print('the number of lines', len(wallLines), len(doorLines), len(iconLines))

  #print(wallPointNeighbors[26])
  #print(wallPointOrientationLinesMap[26])
  #exit(1)

  if True:
    #densityImg = cv2.imread('test/predict_density.png', 0)
    drawPoints(os.path.join(debug_prefix, "points.png"), width, height, wallPoints, densityImage, pointSize=3)
    drawPointsSeparately(os.path.join(debug_prefix, 'points'), width, height, wallPoints, densityImage, pointSize=3)
    drawLines(os.path.join(debug_prefix, 'lines.png'), width, height, wallPoints, wallLines, [], None, 1, lineColor=255)
  else:
    drawPoints(os.path.join(debug_prefix, 'points.png'), width, height, wallPoints)
    drawPointsSeparately(os.path.join(debug_prefix, 'points'), wallPoints)
    drawLines(os.path.join(debug_prefix, 'lines.png'), width, height, wallPoints, wallLines, [], None, 2, lineColor=255)
    pass

  if gt_dict != None and False:
    findMatches({'wall': [wallPoints, wallLines, []]}, gt_dict, distanceThreshold=DISTANCES['wall'])
    pass

  wallMask = drawLineMask(width, height, wallPoints, wallLines)
  print('gt', gt)

  labelVotesMap = np.zeros((NUM_FINAL_ROOMS, height, width))
  #labelMap = np.zeros((NUM_LABELS, height, width))
  #semanticHeatmaps = np.concatenate([iconHeatmaps, roomHeatmaps], axis=2)
  for segmentIndex in range(NUM_FINAL_ROOMS):
    segmentation_img = roomHeatmaps[:, :, segmentIndex]
    #segmentation_img = (segmentation_img > 0.5).astype(np.float)
    labelVotesMap[segmentIndex] = segmentation_img
    #labelMap[segmentIndex] = segmentation_img
    continue

  labelVotesMap = np.cumsum(np.cumsum(labelVotesMap, axis=1), axis=2)

  #doorLines, doorPointOrientationLinesMap, doorPointNeighbors = calcPointInfo(doorPoints, gap, True)
  #icons = findIcons(iconPoints, GAP, False)
  icons = findIconsFromLines(iconPoints, iconLines)

  if not gt:
    newIcons, newIconPoints, newDoorLines, newDoorPoints = findCandidatesFromHeatmaps(iconHeatmaps, len(iconPoints), len(doorPoints))

    icons += newIcons
    iconPoints += newIconPoints
    doorLines += newDoorLines
    doorPoints += newDoorPoints
    pass

  # print([(doorPoints[line[0]][:2], doorPoints[line[1]][:2]) for line in newDoorLines])
  # print([(iconPoints[icon[0]][:2], iconPoints[icon[1]][:2], iconPoints[icon[2]][:2], iconPoints[icon[3]][:2]) for icon in newIcons])
  # print('num icons', len(icons), len(newIcons))
  # if len(newIcons) > 10:
  #   exit(1)
  #   pass


  #print([(doorPoints[line[0]][:2], doorPoints[line[1]][:2]) for line in newDoorLines])
  #print([(iconPoints[icon[0]][:2], iconPoints[icon[1]][:2], iconPoints[icon[2]][:2], iconPoints[icon[3]][:2]) for icon in newIcons])
  #print([(iconPoints[icon[0]][:2], iconPoints[icon[1]][:2], iconPoints[icon[2]][:2], iconPoints[icon[3]][:2]) for icon in icons[:10]])
  #exit(1)


  #icons = [icons[0]]
  #iconLines, iconPointOrientationLinesMap, iconPointNeighbors = calcPointInfo(iconPoints, gap, True)

  if True:
    drawLines(os.path.join(debug_prefix, 'lines.png'), width, height, wallPoints, wallLines, [], None, 2, lineColor=255)
    drawLines(os.path.join(debug_prefix, 'doors.png'), width, height, doorPoints, doorLines, [], None, 2, lineColor=255)
    drawRectangles(os.path.join(debug_prefix, 'icons.png'), width, height, iconPoints, icons, {}, 2)
    print('number of walls: ' + str(len(wallLines)))
    print('number of doors: ' + str(len(doorLines)))
    print('number of icons: ' + str(len(icons)))
    pass


  doorWallLineMap = findLineMap(doorPoints, doorLines, wallPoints, wallLines, gap=GAPS['wall_door_neighbor'])

  newDoorLines = []
  newDoorWallLineMap = []
  for lineIndex, walls in enumerate(doorWallLineMap):
    if len(walls) > 0:
      newDoorLines.append(doorLines[lineIndex])
      newDoorWallLineMap.append(walls)
      pass
    continue
  doorLines = newDoorLines
  doorWallLineMap = newDoorWallLineMap


  #print(len(wallLines))
  conflictWallLinePairs = findConflictLinePairs(wallPoints, wallLines, gap=GAPS['wall_conflict'], distanceThreshold=DISTANCES['wall'], considerEndPoints=True)
  #print(len(wallLines))

  # print([(pointIndex, wallPoints[pointIndex]) for pointIndex in range(len(wallPoints))])
  # print(wallPointNeighbors[15])
  # print([(lineIndex, wallLine) for lineIndex, wallLine in enumerate(wallLines)])


  conflictDoorLinePairs = findConflictLinePairs(doorPoints, doorLines, gap=GAPS['door_conflict'], distanceThreshold=DISTANCES['door'])
  conflictIconPairs = findConflictRectanglePairs(iconPoints, icons, gap=GAPS['icon_conflict'])
  #print(conflictIconPairs)
  #print([[[np.array(iconPoints[pointIndex][:2]).astype(np.int32).tolist() for pointIndex in icons[iconIndex]] for iconIndex in iconPair] for iconPair in conflictIconPairs])
  #print([(iconIndex, [np.array(iconPoints[pointIndex][:2]).astype(np.int32).tolist() for pointIndex in icons[iconIndex]]) for iconIndex in range(len(icons))])
  #exit(1)



  if False:
    # for lineIndex, line in enumerate(doorLines):
    #   drawLines('test/doors/line_' + str(lineIndex) + '.png', width, height, doorPoints, [line])
    #   continue

    print(wallLines)

    os.system('mkdir ' + debug_prefix + '/lines')
    for lineIndex, line in enumerate(wallLines):
      drawLines(os.path.join(debug_prefix, 'lines/line_' + str(lineIndex) + '.png'), width, height, wallPoints, [line], [], lineColor=255)
      continue
    exit(1)
    pass


  wallLineNeighbors = findLineNeighbors(wallPoints, wallLines, labelVotesMap, gap=GAPS['wall_neighbor'])

  iconWallLineNeighbors = findRectangleLineNeighbors(iconPoints, icons, wallPoints, wallLines, wallLineNeighbors, gap=GAPS['wall_icon_neighbor'], distanceThreshold=DISTANCES['wall_icon'])
  conflictIconWallPairs = findConflictRectangleLinePairs(iconPoints, icons, wallPoints, wallLines, gap=GAPS['wall_icon_conflict'])


  # print(wallLineNeighbors[18])
  # print(wallLineNeighbors[35])
  # print([pair for pair in conflictWallLinePairs if 35 in pair])
  # exit(1)

  if False:
    print(conflictWallLinePairs)
    #for wallIndex in [0, 1, 29, 48, 34, 59, 37, 61]:
    for wallIndex in [0, 17]:
      print(wallLines[wallIndex])
      print([wallPoints[pointIndex] for pointIndex in wallLines[wallIndex]])
      print(wallPointOrientationLinesMap[wallLines[wallIndex][0]])
      print(wallPointOrientationLinesMap[wallLines[wallIndex][1]])
      continue
    exit(1)
    pass


  exteriorLines = {}
  for lineIndex, neighbors in enumerate(wallLineNeighbors):
    if len(neighbors[0]) == 0 and len(neighbors[1]) > 0:
      exteriorLines[lineIndex] = 0
    elif len(neighbors[0]) > 0 and len(neighbors[1]) == 0:
      exteriorLines[lineIndex] = 1
      pass
    continue

  #print(exteriorLines)
  #exit(1)

  if False:
    # for i in range(2):
    #   print(wallLineNeighbors[43][i].keys())
    #   print(wallLineNeighbors[81][i].keys())
    #   print(wallLineNeighbors[84][i].keys())
    # exit(1)
    filteredWallLines = []
    for lineIndex, neighbors in enumerate(wallLineNeighbors):
      if len(neighbors[0]) == 0 and len(neighbors[1]) > 0:
        print(lineIndex)
        filteredWallLines.append(wallLines[lineIndex])
        pass
      continue
    drawLines(os.path.join(debug_prefix, 'exterior_1.png'), width, height, wallPoints, filteredWallLines, lineColor=255)

    filteredWallLines = []
    for lineIndex, neighbors in enumerate(wallLineNeighbors):
      if len(neighbors[0]) > 0 and len(neighbors[1]) == 0:
        print(lineIndex)
        filteredWallLines.append(wallLines[lineIndex])
        pass
      continue
    drawLines(os.path.join(debug_prefix, 'exterior_2.png'), width, height, wallPoints, filteredWallLines, lineColor=255)
    exit(1)
    pass



  try:
  #if True:
    model = Model("JunctionFilter")

    #add variables
    w_p = [model.addVar(vtype = GRB.BINARY, name="point_" + str(pointIndex)) for pointIndex in range(len(wallPoints))]
    w_l = [model.addVar(vtype = GRB.BINARY, name="line_" + str(lineIndex)) for lineIndex in range(len(wallLines))]

    d_l = [model.addVar(vtype = GRB.BINARY, name="door_line_" + str(lineIndex)) for lineIndex in range(len(doorLines))]

    i_r = [model.addVar(vtype = GRB.BINARY, name="icon_rectangle_" + str(lineIndex)) for lineIndex in range(len(icons))]

    i_types = []
    for iconIndex in range(len(icons)):
      i_types.append([model.addVar(vtype = GRB.BINARY, name="icon_type_" + str(iconIndex) + "_" + str(typeIndex)) for typeIndex in range(NUM_FINAL_ICONS)])
      continue

    l_dir_labels = []
    for lineIndex in range(len(wallLines)):
      dir_labels = []
      for direction in range(2):
        labels = []
        for label in range(NUM_FINAL_ROOMS):
          labels.append(model.addVar(vtype = GRB.BINARY, name="line_" + str(lineIndex) + "_" + str(direction) + "_" + str(label)))
        dir_labels.append(labels)
      l_dir_labels.append(dir_labels)



    #model.update()
    obj = QuadExpr()

    if gt:
      for pointIndex in range(len(wallPoints)):
        model.addConstr(w_p[pointIndex] == 1, 'gt_point_active_' + str(pointIndex))
        continue

      pointIconMap = {}
      for iconIndex, icon in enumerate(icons):
        for pointIndex in icon:
          if pointIndex not in pointIconMap:
            pointIconMap[pointIndex] = []
            pass
          pointIconMap[pointIndex].append(iconIndex)
          continue
        continue
      for pointIndex, iconIndices in pointIconMap.iteritems():
        break
        iconSum = LinExpr()
        for iconIndex in iconIndices:
          iconSum += i_r[iconIndex]
          continue
        model.addConstr(iconSum == 1)
        continue
      pass


    #label sum constraints
    for lineIndex in range(len(wallLines)):
      for direction in range(2):
        labelSum = LinExpr()
        for label in range(NUM_FINAL_ROOMS):
          labelSum += l_dir_labels[lineIndex][direction][label]
          continue
        model.addConstr(labelSum == w_l[lineIndex], 'label_sum')
        continue
      continue


    #opposite room constraints
    if False:
      oppositeRoomPairs = [(1, 1), (2, 2), (4, 4), (5, 5), (7, 7), (9, 9)]
      for lineIndex in range(len(wallLines)):
        for oppositeRoomPair in oppositeRoomPairs:
          model.addConstr(l_dir_labels[lineIndex][0][oppositeRoomPair[0]] + l_dir_labels[lineIndex][0][oppositeRoomPair[1]] <= 1)
          if oppositeRoomPair[0] != oppositeRoomPair[1]:
            model.addConstr(l_dir_labels[lineIndex][0][oppositeRoomPair[1]] + l_dir_labels[lineIndex][0][oppositeRoomPair[0]] <= 1)
            pass
          continue
        continue
      pass

    #loop constraints
    closeRooms = {}
    for label in range(NUM_FINAL_ROOMS):
      closeRooms[label] = True
      continue
    closeRooms[1] = False
    closeRooms[2] = False
    #closeRooms[3] = False
    closeRooms[8] = False
    closeRooms[9] = False

    for label in range(NUM_FINAL_ROOMS):
      if not closeRooms[label]:
        continue
      for pointIndex, orientationLinesMap in enumerate(wallPointOrientationLinesMap):
        for orientation, lines in orientationLinesMap.iteritems():
          direction = int(orientation in [1, 2])
          lineSum = LinExpr()
          for lineIndex in lines:
            lineSum += l_dir_labels[lineIndex][direction][label]
            continue
          for nextOrientation in range(orientation + 1, 8):
            if not (nextOrientation % 4) in orientationLinesMap:
              continue
            nextLines = orientationLinesMap[nextOrientation % 4]
            nextDirection = int((nextOrientation % 4) in [0, 3])
            nextLineSum = LinExpr()
            for nextLineIndex in nextLines:
              nextLineSum += l_dir_labels[nextLineIndex][nextDirection][label]
              continue
            model.addConstr(lineSum == nextLineSum)
            break
          continue
        continue
      continue


    #exterior constraints
    exteriorLineSum = LinExpr()
    for lineIndex in range(len(wallLines)):
      if lineIndex not in exteriorLines:
        continue
      #direction = exteriorLines[lineIndex]
      label = 0
      model.addConstr(l_dir_labels[lineIndex][0][label] + l_dir_labels[lineIndex][1][label] == w_l[lineIndex], 'exterior_wall')
      exteriorLineSum += w_l[lineIndex]
      continue
    model.addConstr(exteriorLineSum >= 1, 'exterior_wall_sum')


    #line label constraints and objectives
    for lineIndex, directionNeighbors in enumerate(wallLineNeighbors):
      for direction, neighbors in enumerate(directionNeighbors):
        labelVotesSum = np.zeros(NUM_FINAL_ROOMS)
        for neighbor, labelVotes in neighbors.iteritems():
          labelVotesSum += labelVotes
          continue

        votesSum = labelVotesSum.sum()
        if votesSum == 0:
          continue
        labelVotesSum /= votesSum


        for label in range(NUM_FINAL_ROOMS):
          obj += l_dir_labels[lineIndex][direction][label] * (0.0 - labelVotesSum[label]) * labelWeight
          continue
        continue
      continue


    # if not gt:
    #   print(wallLineNeighbors[47][1])
    #   print(wallLineNeighbors[140][1])
    #   print(wallLineNeighbors[67][0])
    #   print(wallLineNeighbors[128][0])
    #   pass


    # for pointIndex in range(len(wallPoints)):
    #   if pointIndex not in augmentedPointMask:
    #     obj += (1 - w_p[pointIndex]) * junctionWeight #* len(wallPointOrientationLinesMap[pointIndex])
    #   else:
    #     obj += w_p[pointIndex] * augmentedJunctionWeight #* len(wallPointOrientationLinesMap[pointIndex])
    #   continue


    #door endpoint constraints
    pointDoorsMap = {}
    for doorIndex, line in enumerate(doorLines):
      for endpointIndex in range(2):
        pointIndex = line[endpointIndex]
        if pointIndex not in pointDoorsMap:
          pointDoorsMap[pointIndex] = []
          pass
        pointDoorsMap[pointIndex].append(doorIndex)
        continue
      continue



    # confidence insensitive objectives
    # for pointIndex, doorIndices in pointDoorsMap.iteritems():
    #   doorSum = LinExpr(0)
    #   for doorIndex in doorIndices:
    #     doorSum += d_l[doorIndex]
    #     continue
    #   obj += (1 - doorSum) * doorWeight
    #   #model.addConstr(doorSum <= 1, "door_line_sum_" + str(pointIndex) + "_" + str(orientation))
    #   continue




    #icon corner constraints
    pointIconsMap = {}
    for iconIndex, icon in enumerate(icons):
      for cornerIndex in range(4):
        pointIndex = icon[cornerIndex]
        if pointIndex not in pointIconsMap:
          pointIconsMap[pointIndex] = []
          pass
        pointIconsMap[pointIndex].append(iconIndex)
        continue
      continue

    for pointIndex, iconIndices in pointIconsMap.iteritems():
      iconSum = LinExpr(0)
      for iconIndex in iconIndices:
        iconSum += i_r[iconIndex]
        continue
      #obj += (1 - iconSum) * iconWeight
      #print(iconIndices)
      model.addConstr(iconSum <= 1)
      continue

    #exit(1)
    #print(pointIconsMap)


    #gapWeight = 1
    #pixelEvidenceWeight = 1


    if False:
      for lineIndex, line in enumerate(wallLines):
        point = wallPoints[line[0]]
        neighborPoint = wallPoints[line[1]]
        lineDim = calcLineDim(wallPoints, line)
        #wallCost = (abs(neighborPoint[1 - lineDim] - point[1 - lineDim]) / GAP - 0.5) * gapWeight
        #obj += w_l[lineIndex] * wallCost * wallWeight

        fixedValue = int(round((neighborPoint[1 - lineDim] + point[1 - lineDim]) / 2))

        # wallEvidenceSums = [0, 0]
        # for delta in range(int(abs(neighborPoint[lineDim] - point[lineDim]) + 1)):
        #   intermediatePoint = [0, 0]
        #   intermediatePoint[lineDim] = int(min(neighborPoint[lineDim], point[lineDim]) + delta)
        #   intermediatePoint[1 - lineDim] = fixedValue
        #   for typeIndex in range(NUM_WALL_TYPES):
        #     wallEvidenceSums[typeIndex] += labelMap[WALL_LABEL_OFFSET + typeIndex][min(max(intermediatePoint[1], 0), height - 1)][min(max(intermediatePoint[0], 0), width - 1)]
        #     continue
        #   continue
        # wallEvidenceSum = wallEvidenceSums[0] + wallEvidenceSums[1]
        # wallEvidenceSum /= maxDim

        wallEvidenceSum = 0.0
        count = 0

        for delta in range(int(round(abs(neighborPoint[lineDim] - point[lineDim]))) + 1):
          intermediatePoint = [0, 0]
          intermediatePoint[lineDim] = int(min(neighborPoint[lineDim], point[lineDim]) + delta)
          intermediatePoint[1 - lineDim] = fixedValue
          if lineDim == 0:
            fixedValue_1 = min(max(intermediatePoint[1] - wallLineWidth, 0), height - 1)
            fixedValue_2 = min(max(intermediatePoint[1] + wallLineWidth + 1, 0), height - 1)
            wallEvidenceSum += roomHeatmaps[fixedValue_1:fixedValue_2, min(max(intermediatePoint[0], 0), width - 1), WALL_LABEL_OFFSET].sum()
          else:
            fixedValue_1 = min(max(intermediatePoint[0] - wallLineWidth, 0), width - 1)
            fixedValue_2 = min(max(intermediatePoint[0] + wallLineWidth + 1, 0), width - 1)
            wallEvidenceSum += roomHeatmaps[min(max(intermediatePoint[1], 0), height - 1), fixedValue_1:fixedValue_2, WALL_LABEL_OFFSET].sum()
            pass
          count += fixedValue_2 - fixedValue_1
          continue
        wallEvidenceSum /= count
        #print(lineIndex, wallEvidenceSum, [wallPoints[pointIndex] for pointIndex in wallLines[lineIndex]])
        obj += -wallEvidenceSum * w_l[lineIndex] * wallWeight
        continue
    else:
      wallLineConfidenceMap = roomHeatmaps[:, :, WALL_LABEL_OFFSET]
      wallConfidences = []
      for lineIndex, line in enumerate(wallLines):
        point_1 = np.array(wallPoints[line[0]][:2])
        point_2 = np.array(wallPoints[line[1]][:2])
        lineDim = calcLineDim(wallPoints, line)

        fixedValue = int(round((point_1[1 - lineDim] + point_2[1 - lineDim]) / 2))
        point_1[lineDim], point_2[lineDim] = min(point_1[lineDim], point_2[lineDim]), max(point_1[lineDim], point_2[lineDim])

        point_1[1 - lineDim] = fixedValue - wallLineWidth
        point_2[1 - lineDim] = fixedValue + wallLineWidth


        point_1 = np.maximum(point_1, 0).astype(np.int32)
        point_2 = np.minimum(point_2, sizes - 1).astype(np.int32)

        wallLineConfidence = np.sum(wallLineConfidenceMap[point_1[1]:point_2[1] + 1, point_1[0]:point_2[0] + 1]) / ((point_2[1] + 1 - point_1[1]) * (point_2[0] + 1 - point_1[0])) - 0.5

        obj += -wallLineConfidence * w_l[lineIndex] * wallWeight

        wallConfidences.append(wallLineConfidence)
        continue
      pass

    if not gt:
      for wallIndex, wallLine in enumerate(wallLines):
        print(wallIndex, [np.array(wallPoints[pointIndex][:2]).astype(np.int32).tolist() for pointIndex in wallLine], wallConfidences[wallIndex])
        continue
      #model.addConstr(w_l[28] == 1)
      pass


    doorLineConfidenceMap = iconHeatmaps[:, :, DOOR_LABEL_OFFSET] + iconHeatmaps[:, :, DOOR_LABEL_OFFSET + 1]
    for lineIndex, line in enumerate(doorLines):
      #obj += -d_l[lineIndex] * doorWeight * abs(neighborPoint[lineDim] - point[lineDim] + 1) / maxDim
      #continue
      point_1 = np.array(doorPoints[line[0]][:2])
      point_2 = np.array(doorPoints[line[1]][:2])
      lineDim = calcLineDim(doorPoints, line)

      #doorCost = (abs(neighborPoint[1 - lineDim] - point[1 - lineDim]) / gap - 1) * gapWeight
      #obj += d_l[lineIndex] * doorCost * doorWeight
      fixedValue = int(round((point_1[1 - lineDim] + point_2[1 - lineDim]) / 2))

      #assert(point_1[lineDim] < point_2[lineDim], 'door line reversed')
      point_1[lineDim], point_2[lineDim] = min(point_1[lineDim], point_2[lineDim]), max(point_1[lineDim], point_2[lineDim])

      point_1[1 - lineDim] = fixedValue - doorLineWidth
      point_2[1 - lineDim] = fixedValue + doorLineWidth

      point_1 = np.maximum(point_1, 0).astype(np.int32)
      point_2 = np.minimum(point_2, sizes - 1).astype(np.int32)

      if not gt:
        doorLineConfidence = np.sum(doorLineConfidenceMap[point_1[1]:point_2[1] + 1, point_1[0]:point_2[0] + 1]) / ((point_2[1] + 1 - point_1[1]) * (point_2[0] + 1 - point_1[0]))

        if lineDim == 0:
          doorPointConfidence = (doorCornerHeatmaps[point_1[1], point_1[0], 3] + doorCornerHeatmaps[point_2[1], point_2[0], 1]) / 2
        else:
          doorPointConfidence = (doorCornerHeatmaps[point_1[1], point_1[0], 0] + doorCornerHeatmaps[point_2[1], point_2[0], 2]) / 2
          pass
        doorConfidence = (doorLineConfidence + doorPointConfidence) / 2 - 0.5
        obj += -doorConfidence * d_l[lineIndex] * doorWeight
      else:
        obj += -0.5 * d_l[lineIndex] * doorWeight
        pass

      #doorEvidenceSums = [0 for typeIndex in range(NUM_DOOR_TYPES)]
      #doorEvidenceSum = 0
      # for delta in range(int(abs(neighborPoint[lineDim] - point[lineDim]) + 1)):
      #   intermediatePoint = [0, 0]
      #   intermediatePoint[lineDim] = int(min(neighborPoint[lineDim], point[lineDim]) + delta)
      #   intermediatePoint[1 - lineDim] = fixedValue

      #   doorEvidenceSum += np.sum(labelMap[DOOR_LABEL_OFFSET:DOOR_LABEL_OFFSET + NUM_DOOR_TYPES, min(max(intermediatePoint[1], 0), height - 1), min(max(intermediatePoint[0], 0), width - 1)])
      #   continue
      # doorEvidenceSum /= maxDim

      #print(point_1.tolist(), point_2.tolist(), doorConfidence)

      #print(('door confidence', lineIndex, [np.array(doorPoints[pointIndex][:2]).astype(np.int32).tolist() for pointIndex in doorLines[lineIndex]]))


      continue


    for iconIndex, icon in enumerate(icons):
      point_1 = iconPoints[icon[0]]
      point_2 = iconPoints[icon[1]]
      point_3 = iconPoints[icon[2]]
      point_4 = iconPoints[icon[3]]

      x_1 = int((point_1[0] + point_3[0]) / 2)
      x_2 = int((point_2[0] + point_4[0]) / 2)
      y_1 = int((point_1[1] + point_2[1]) / 2)
      y_2 = int((point_3[1] + point_4[1]) / 2)

      iconArea = (x_2 - x_1 + 1) * (y_2 - y_1 + 1)
      #iconEvidenceSums = labelVotesMap[ICON_LABEL_OFFSET:ICON_LABEL_OFFSET + NUM_FINAL_ICONS, y_2, x_2] + labelVotesMap[ICON_LABEL_OFFSET:ICON_LABEL_OFFSET + NUM_FINAL_ICONS, y_1, x_1] - labelVotesMap[ICON_LABEL_OFFSET:ICON_LABEL_OFFSET + NUM_FINAL_ICONS, y_2, x_1] - labelVotesMap[ICON_LABEL_OFFSET:ICON_LABEL_OFFSET + NUM_FINAL_ICONS, y_1, x_2]

      # for typeIndex in range(NUM_FINAL_ICONS):
      #   iconRatio = iconEvidenceSums[typeIndex] / iconArea
      #   if iconRatio < 0.5 and False:
      #     model.addConstr(i_types[iconIndex][typeIndex] == 0)
      #   else:
      #     obj += i_types[iconIndex][typeIndex] * (0 - iconEvidenceSums[typeIndex] / iconArea) * iconTypeWeight
      #   continue
      # continue

      if iconArea <= 1e-4:
        print(icon)
        print([iconPoints[pointIndex] for pointIndex in icon])
        print('zero size icon')
        exit(1)
        pass

      iconTypeConfidence = iconHeatmaps[y_1:y_2 + 1, x_1:x_2 + 1, :NUM_FINAL_ICONS + 1].sum(axis=(0, 1)) / iconArea
      iconTypeConfidence[1] += iconTypeConfidence[8]
      iconTypeConfidence[6] += iconTypeConfidence[9]
      iconTypeConfidence[8] = 0
      iconTypeConfidence[9] = 0
      iconTypeConfidence = iconTypeConfidence[1:] - iconTypeConfidence[0]

      if not gt:
        #iconPointConfidence = (iconCornerHeatmaps[y_1, x_1, 2] + iconCornerHeatmaps[y_1, x_2, 3] + iconCornerHeatmaps[y_2, x_1, 1] + iconCornerHeatmaps[y_2, x_2, 0]) / 4 - 0.5
        iconPointConfidence = (iconCornerHeatmaps[int(round(point_1[1])), int(round(point_1[0])), 2] + iconCornerHeatmaps[int(round(point_2[1])), int(round(point_2[0])), 3] + iconCornerHeatmaps[int(round(point_3[1])), int(round(point_3[0])), 1] + iconCornerHeatmaps[int(round(point_4[1])), int(round(point_4[0])), 0]) / 4 - 0.5
        iconConfidence = (iconTypeConfidence + iconPointConfidence) / 2
      else:
        iconConfidence = iconTypeConfidence
        pass

      #iconTypeConfidence[1:] = 0
      #iconTypeConfidence[0] = 0
      for typeIndex in range(NUM_FINAL_ICONS):
        obj += -i_types[iconIndex][typeIndex] * (iconConfidence[typeIndex]) * iconTypeWeight
        continue

      #print('icon confidence', iconIndex, x_1, y_1, x_2, y_2, iconTypeConfidence.argmax(), iconTypeConfidence[iconTypeConfidence.argmax()], iconConfidence[iconTypeConfidence.argmax()])
      continue

    #if not gt:
    #exit(1)

    for iconIndex in range(len(icons)):
      typeSum = LinExpr(0)
      for typeIndex in range(NUM_FINAL_ICONS - 1):
        typeSum += i_types[iconIndex][typeIndex]
        continue
      model.addConstr(typeSum == i_r[iconIndex])
      continue


    #line sum constraints and objectives
    for pointIndex, orientationLinesMap in enumerate(wallPointOrientationLinesMap):
      pointLineSum = LinExpr(0)
      for orientation, lines in orientationLinesMap.iteritems():
        #if len(lines) > 1:
        #print(lines)
        lineSum = LinExpr(0)
        for lineIndex in lines:
          lineSum += w_l[lineIndex]
          continue

        model.addConstr(lineSum == w_p[pointIndex], "line_sum_" + str(pointIndex) + "_" + str(orientation))
        #obj += (w_p[pointIndex] - lineSum) * junctionLineWeight
        #obj += (1 - lineSum) * junctionWeight
        pointLineSum += lineSum
        continue

      #if wallPoints[pointIndex][2] > 0:
      #model.addConstr(pointLineSum >= wallPoints[pointIndex][2] * w_p[pointIndex], 'point line sum')
        #model.addConstr(pointLineSum >= 2 * w_p[pointIndex], 'point line sum')
        #pass

      continue


    # #close points constraints
    # for pointIndex, point in enumerate(wallPoints):
    #   for neighborPointIndex, neighborPoint in enumerate(wallPoints):
    #     if neighborPointIndex <= pointIndex:
    #       continue
    #     distance = pow(pow(point[0] - neighborPoint[0], 2) + pow(point[1] - neighborPoint[1], 2), 0.5)
    #     if distance < DISTANCES['point'] and neighborPointIndex not in wallPointNeighbors[pointIndex]:
    #       #print('close point', pointIndex, neighborPointIndex)
    #       #obj += p[pointIndex] * p[neighborPointIndex] * closePointWeight
    #       model.addConstr(w_p[pointIndex] + w_p[neighborPointIndex] <= 1, 'close point')
    #       pass
    #     continue
    #   continue


    # print('conflict')
    # conflictLines = [0, ]
    # for conflictLinePair in conflictWallLinePairs:
    #   if conflictLinePair[0] == 0:
    #     conflictLines.append(conflictLinePair[1])
    #     pass
    #   for c in range(2):
    #     if conflictLinePair[c] in [1, 29, 48, 34, 59, 37, 61] and conflictLinePair[1 - c] not in conflictLines:
    #       print(conflictLinePair)
    #       pass
    #     if conflictLinePair[c] in [1, 29, 48, 34, 59, 37, 61] and conflictLinePair[1 - c] in [1, 29, 48, 34, 59, 37, 61]:
    #       print(conflictLinePair)
    #       pass
    #     continue
    #   continue
    # drawLines('test/lines/line_0_combined.png', width, height, wallPoints, [wallLines[lineIndex] for lineIndex in [1, 29, 48, 34, 59, 37, 61]], [], None, 2, lineColor=255)
    # exit(1)


    #conflict pair constraints

    # ratio_1 = 0.47
    # ratio_2 = 0.5
    #print('ratio', int(round(len(conflictWallLinePairs) * ratio_1)), int(round(len(conflictWallLinePairs) * ratio_2)), len(conflictWallLinePairs))
    # conflictWallLinePairs = conflictWallLinePairs[int(round(len(conflictWallLinePairs) * ratio_1)):int(round(len(conflictWallLinePairs) * ratio_2))]


    #print(len(conflictWallLinePairs))
    #conflictWallLinePairs = conflictWallLinePairs[135:136] + conflictWallLinePairs[240:]
    #conflictWallLinePairs = []
    #print(conflictWallLinePairs[135:136])
    #exit(1)


    for conflictLinePair in conflictWallLinePairs:
      model.addConstr(w_l[conflictLinePair[0]] + w_l[conflictLinePair[1]] <= 1, 'conflict_wall_line_pair')
      continue

    for conflictLinePair in conflictDoorLinePairs:
      model.addConstr(d_l[conflictLinePair[0]] + d_l[conflictLinePair[1]] <= 1, 'conflict_door_line_pair')
      continue

    for conflictIconPair in conflictIconPairs:
      model.addConstr(i_r[conflictIconPair[0]] + i_r[conflictIconPair[1]] <= 1, 'conflict_icon_pair')
      continue

    for conflictLinePair in conflictIconWallPairs:
      model.addConstr(i_r[conflictLinePair[0]] + w_l[conflictLinePair[1]] <= 1, 'conflict_icon_wall_pair')
      continue


    #door wall line map constraints
    for doorIndex, lines in enumerate(doorWallLineMap):
      if len(lines) == 0:
        model.addConstr(d_l[doorIndex] == 0, 'door_not_on_walls')
        continue
      lineSum = LinExpr(0)
      for lineIndex in lines:
        lineSum += w_l[lineIndex]
        continue
      model.addConstr(d_l[doorIndex] <= lineSum, 'd<=line_sum')
      continue

    doorWallPointMap = findLinePointMap(doorPoints, doorLines, wallPoints, gap=GAPS['door_point_conflict'])
    for doorIndex, points in enumerate(doorWallPointMap):
      if len(points) == 0:
        continue
      #print('door', [doorPoints[pointIndex] for pointIndex in doorLines[doorIndex][:2]])
      #print([wallPoints[pointIndex][:2] for pointIndex in points])
      pointSum = LinExpr(0)
      for pointIndex in points:
        model.addConstr(d_l[doorIndex] + w_p[pointIndex] <= 1, 'door_on_two_walls')
        continue
      continue
    #exit(1)


    if not gt:
      # print(wallLines[91])
      #print(wallPointOrientationLinesMap[24])
      #print(wallPointNeighbors[24])
      #exit(1)

      #print(conflictWallLinePairs)

      #1, 29, 48, 34, 59, 37, 61
      #model.addConstr(w_l[13] == 0)
      #model.addConstr(w_p[7] == 1)
      #model.addConstr(w_l[55] == 1)
      #model.addConstr(w_l[63] == 1)

      #model.addConstr(w_l[45] == 0)

      # for wallIndex in [44, 57, 60]:
      #   model.addConstr(w_l[wallIndex] == 1)
      #   continue

      #model.addConstr(d_l[3] == 1)
      #print(wallLines[90])
      #print(wallLines[62])
      #print(wallLines[73])
      #print(wallLines[107])
      #print(wallLines[111])
      #print(wallPointOrientationLinesMap[wallLines[0][0]])
      #print(wallPointOrientationLinesMap[wallLines[111][1]])
      #print(wallPointOrientationLinesMap[25])
      #print(wallLines[])
      #exit(1)
      #model.addConstr(d_l[8] == 1)
      #model.addConstr(i_types[8][1] == 1)
      #model.addConstr(l_dir_labels[39][1][7] == 1)
      #exit(1)
      pass


    model.setObjective(obj, GRB.MINIMIZE)
    #model.update()
    model.setParam('TimeLimit', 120)
    model.optimize()


    if model.status == GRB.Status.INF_OR_UNBD:
      # Turn presolve off to determine whether model is infeasible
      # or unbounded
      model.setParam(GRB.Param.Presolve, 0)
      model.optimize()

    model.write('test/model.lp')
    #print(model.status)
    if model.status == GRB.Status.OPTIMAL:
      filteredWallLines = []
      filteredWallLabels = []
      filteredWallTypes = []
      wallPointLabels = [[-1, -1, -1, -1] for pointIndex in range(len(wallPoints))]

      for lineIndex, lineVar in enumerate(w_l):
        if lineVar.x < 0.5:
          continue
        filteredWallLines.append(wallLines[lineIndex])

        filteredWallTypes.append(0)

        labels = [11, 11]
        for direction in range(2):
          for label in range(NUM_FINAL_ROOMS):
            if l_dir_labels[lineIndex][direction][label].x > 0.5:
              labels[direction] = label
              break
            continue
          continue

        filteredWallLabels.append(labels)
        print('wall', lineIndex, labels, [np.array(wallPoints[pointIndex][:2]).astype(np.int32).tolist() for pointIndex in wallLines[lineIndex]], wallLineNeighbors[lineIndex][0].keys(), wallLineNeighbors[lineIndex][1].keys())
        line = wallLines[lineIndex]
        lineDim = calcLineDim(wallPoints, line)
        if lineDim == 0:
          wallPointLabels[line[0]][0] = labels[0]
          wallPointLabels[line[0]][1] = labels[1]
          wallPointLabels[line[1]][3] = labels[0]
          wallPointLabels[line[1]][2] = labels[1]
        else:
          wallPointLabels[line[0]][1] = labels[0]
          wallPointLabels[line[0]][2] = labels[1]
          wallPointLabels[line[1]][0] = labels[0]
          wallPointLabels[line[1]][3] = labels[1]
          pass
        continue


      #if not gt:
      #print([(lineIndex, [np.array(wallPoints[pointIndex][:2]).astype(np.int32).tolist() for pointIndex in wallLine]) for lineIndex, wallLine in enumerate(filteredWallLines)])
      #exit(1)

      if not gt:
        adjustPoints(wallPoints, filteredWallLines)
        mergePoints(wallPoints, filteredWallLines)
        adjustPoints(wallPoints, filteredWallLines)
        filteredWallLabels = [filteredWallLabels[lineIndex] for lineIndex in range(len(filteredWallLines)) if filteredWallLines[lineIndex][0] != filteredWallLines[lineIndex][1]]
        filteredWallLines = [line for line in filteredWallLines if line[0] != line[1]]
        pass


      drawLines('test/result_line.png', width, height, wallPoints, filteredWallLines, filteredWallLabels, lineColor=255)
      #resultImage = drawLines('', width, height, wallPoints, filteredWallLines, filteredWallLabels, None, lineWidth=5, lineColor=255)

      filteredDoorLines = []
      filteredDoorTypes = []
      for lineIndex, lineVar in enumerate(d_l):
        if lineVar.x < 0.5:
          continue
        print(('door', lineIndex, [doorPoints[pointIndex][:2] for pointIndex in doorLines[lineIndex]]))
        filteredDoorLines.append(doorLines[lineIndex])

        filteredDoorTypes.append(0)
        continue

      filteredDoorWallMap = findLineMapSingle(doorPoints, filteredDoorLines, wallPoints, filteredWallLines, gap=GAPS['wall_door_neighbor'])
      adjustDoorPoints(doorPoints, filteredDoorLines, wallPoints, filteredWallLines, filteredDoorWallMap)
      drawLines('test/result_door.png', width, height, doorPoints, filteredDoorLines, lineColor=255)

      filteredIcons = []
      filteredIconTypes = []
      for iconIndex, iconVar in enumerate(i_r):
        if iconVar.x < 0.5:
          continue

        filteredIcons.append(icons[iconIndex])
        iconType = -1
        for typeIndex in range(NUM_FINAL_ICONS):
          if i_types[iconIndex][typeIndex].x > 0.5:
            iconType = typeIndex
            break
          continue

        print(('icon', iconIndex, iconType, [iconPoints[pointIndex][:2] for pointIndex in icons[iconIndex]]))

        filteredIconTypes.append(iconType)
        continue



      # print(icons)
      # print(conflictIconWallPairs)
      # print(filteredIcons)
      # exit(1)

      #adjustPoints(iconPoints, filteredIconLines)
      #drawLines('test/lines_results_icon.png', width, height, iconPoints, filteredIconLines)
      drawRectangles('test/result_icon.png', width, height, iconPoints, filteredIcons, filteredIconTypes)


      #resultImage = drawLines('', width, height, doorPoints, filteredDoorLines, [], resultImage, lineWidth=3, lineColor=0)
      #resultImage = drawRectangles('', width, height, iconPoints, filteredIcons, filteredIconTypes, 2, resultImage)
      #cv2.imwrite('test/result.png', resultImage)


      filteredWallPoints = []
      filteredWallPointLabels = []
      orientationMap = {}
      for pointType, orientationOrientations in enumerate(POINT_ORIENTATIONS):
        for orientation, orientations in enumerate(orientationOrientations):
          orientationMap[orientations] = orientation

      for pointIndex, point in enumerate(wallPoints):
        #if w_p[pointIndex].x < 0.5:
        #continue

        orientations = []
        orientationLines = {}
        for orientation, lines in wallPointOrientationLinesMap[pointIndex].iteritems():
          orientationLine = -1
          for lineIndex in lines:
            if w_l[lineIndex].x > 0.5:
              orientations.append(orientation)
              orientationLines[orientation] = lineIndex
              break
            continue
          continue

        if len(orientations) == 0:
          continue

        #print((pointIndex, orientationLines))

        if len(orientations) < len(wallPointOrientationLinesMap[pointIndex]):
          print('invalid point', pointIndex, orientations, wallPointOrientationLinesMap[pointIndex])
          print(wallPoints[pointIndex])
          wallPoints[pointIndex][2] = len(orientations) - 1
          orientations = tuple(orientations)
          if orientations not in orientationMap:
            continue
          wallPoints[pointIndex][3] = orientationMap[orientations]
          print(wallPoints[pointIndex])
          exit(1)
          pass

        filteredWallPoints.append(wallPoints[pointIndex])
        filteredWallPointLabels.append(wallPointLabels[pointIndex])
        continue


      writePoints(filteredWallPoints, filteredWallPointLabels)


      with open('test/floorplan.txt', 'w') as result_file:
        result_file.write(str(width) + '\t' + str(height) + '\n')
        result_file.write(str(len(filteredWallLines)) + '\n')
        for wallIndex, wall in enumerate(filteredWallLines):
          point_1 = wallPoints[wall[0]]
          point_2 = wallPoints[wall[1]]

          result_file.write(str(point_1[0]) + '\t' + str(point_1[1]) + '\t')
          result_file.write(str(point_2[0]) + '\t' + str(point_2[1]) + '\t')
          result_file.write(str(filteredWallLabels[wallIndex][0]) + '\t' + str(filteredWallLabels[wallIndex][1]) + '\n')

        for doorIndex, door in enumerate(filteredDoorLines):
          point_1 = doorPoints[door[0]]
          point_2 = doorPoints[door[1]]

          result_file.write(str(point_1[0]) + '\t' + str(point_1[1]) + '\t')
          result_file.write(str(point_2[0]) + '\t' + str(point_2[1]) + '\t')
          result_file.write('door\t')
          result_file.write(str(filteredDoorTypes[doorIndex] + 1) + '\t1\n')

        for iconIndex, icon in enumerate(filteredIcons):
          point_1 = iconPoints[icon[0]]
          point_2 = iconPoints[icon[1]]
          point_3 = iconPoints[icon[2]]
          point_4 = iconPoints[icon[3]]

          x_1 = int((point_1[0] + point_3[0]) / 2)
          x_2 = int((point_2[0] + point_4[0]) / 2)
          y_1 = int((point_1[1] + point_2[1]) / 2)
          y_2 = int((point_3[1] + point_4[1]) / 2)

          result_file.write(str(x_1) + '\t' + str(y_1) + '\t')
          result_file.write(str(x_2) + '\t' + str(y_2) + '\t')
          result_file.write(iconNumberNameMap[filteredIconTypes[iconIndex]] + '\t')
          #result_file.write(str(iconNumberStyleMap[filteredIconTypes[iconIndex]]) + '\t')
          result_file.write('1\t')
          result_file.write('1\n')

        result_file.close()


      if len(filteredDoorLines) > 0:
        writeDoors(doorPoints, filteredDoorLines, filteredDoorTypes)
        pass
      else:
        try:
          os.remove('test/doors_out.txt')
        except OSError:
          pass

      if len(filteredIcons) > 0:
        writeIcons(iconPoints, filteredIcons, filteredIconTypes)
        pass
      else:
        try:
          os.remove('test/icons_out.txt')
        except OSError:
          pass
        pass



    elif model.status != GRB.Status.INFEASIBLE:
      print('Optimization was stopped with status %d' % model.status)
      return {}
    else:
      print('infeasible')
      #model.ComputeIIS()
      #model.write("test/model.ilp")
      return {}
      pass

  except GurobiError as e:
    print('Error code ' + str(e.errno) + ": " + str(e))
    return {}
    pass
  except AttributeError:
    print('Encountered an attribute error')
    return {}
    pass

  result_dict = {'wall': [wallPoints, filteredWallLines, filteredWallLabels], 'door': [doorPoints, filteredDoorLines, []], 'icon': [iconPoints, filteredIcons, filteredIconTypes]}
  return result_dict
