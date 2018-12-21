#from gurobipy import *
from pulp import *
import cv2
import numpy as np
import sys
import csv
import copy
from utils import *
from skimage import measure

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

WALL_LABEL_OFFSET = NUM_ROOMS + 1
DOOR_LABEL_OFFSET = NUM_ICONS + 1
ICON_LABEL_OFFSET = 0
ROOM_LABEL_OFFSET = NUM_ICONS


colorMap = ColorPalette(NUM_CORNERS).getColorMap()

width = 256
height = 256
maxDim = max(width, height)
sizes = np.array([width, height])

ORIENTATION_RANGES = getOrientationRanges(width, height)

iconNames = getIconNames()
iconNameNumberMap = dict(zip(iconNames, range(len(iconNames))))
iconNumberNameMap = dict(zip(range(len(iconNames)), iconNames))


## Extract corners from corner heatmp predictions
def extractCorners(heatmaps, threshold, gap, cornerType = 'wall', augment=False, gt=False):
  if gt:
    orientationPoints = heatmaps
  else:
    orientationPoints = extractCornersFromHeatmaps(heatmaps, threshold)
    pass

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
      pointType = orientationIndex // 4
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
      points += [[corner[0][0], corner[0][1], orientationIndex // 4, orientationIndex % 4] for corner in corners]
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
  return points, lines, pointOrientationLinesMap, pointNeighbors, augmentedPointMask


## Corner type augmentation to enrich the candidate set (e.g., a T-shape corner can be treated as a L-shape corner)
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


## Remove invalid walls as preprocessing
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

## Write wall points to result file
def writePoints(points, pointLabels, output_prefix='test/'):
  with open(output_prefix + 'points_out.txt', 'w') as points_file:
    for point in points:
      points_file.write(str(point[0] + 1) + '\t' + str(point[1] + 1) + '\t')
      points_file.write(str(point[0] + 1) + '\t' + str(point[1] + 1) + '\t')
      points_file.write('point\t')
      points_file.write(str(point[2] + 1) + '\t' + str(point[3] + 1) + '\n')
  points_file.close()

  with open(output_prefix + 'point_labels.txt', 'w') as point_label_file:
    for point in pointLabels:
      point_label_file.write(str(point[0]) + '\t' + str(point[1]) + '\t' + str(point[2]) + '\t' + str(point[3]) + '\n')
  point_label_file.close()

## Write doors to result file
def writeDoors(points, lines, doorTypes, output_prefix='test/'):
  with open(output_prefix + 'doors_out.txt', 'w') as doors_file:
    for lineIndex, line in enumerate(lines):
      point_1 = points[line[0]]
      point_2 = points[line[1]]

      doors_file.write(str(point_1[0] + 1) + '\t' + str(point_1[1] + 1) + '\t')
      doors_file.write(str(point_2[0] + 1) + '\t' + str(point_2[1] + 1) + '\t')
      doors_file.write('door\t')
      doors_file.write(str(doorTypes[lineIndex] + 1) + '\t1\n')
    doors_file.close()

## Write icons to result file    
def writeIcons(points, icons, iconTypes, output_prefix='test/'):
  with open(output_prefix + 'icons_out.txt', 'w') as icons_file:
    for iconIndex, icon in enumerate(icons):
      point_1 = points[icon[0]]
      point_2 = points[icon[1]]
      point_3 = points[icon[2]]
      point_4 = points[icon[3]]

      x_1 = int(round((point_1[0] + point_3[0]) // 2)) + 1
      x_2 = int(round((point_2[0] + point_4[0]) // 2)) + 1
      y_1 = int(round((point_1[1] + point_2[1]) // 2)) + 1
      y_2 = int(round((point_3[1] + point_4[1]) // 2)) + 1

      icons_file.write(str(x_1) + '\t' + str(y_1) + '\t')
      icons_file.write(str(x_2) + '\t' + str(y_2) + '\t')
      icons_file.write(iconNumberNameMap[iconTypes[iconIndex]] + '\t')
      #icons_file.write(str(iconNumberStyleMap[iconTypes[iconIndex]]) + '\t')
      icons_file.write('1\t')
      icons_file.write('1\n')
    icons_file.close()


## Adjust wall corner locations to align with each other after optimization
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

## Merge two close points after optimization
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
        newPoint = [(point_1[0] + point_2[0]) // 2, (point_1[1] + point_2[1]) // 2, pointInfo[0], pointInfo[1]]
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

## Adjust door corner locations to align with each other after optimization
def adjustDoorPoints(doorPoints, doorLines, wallPoints, wallLines, doorWallMap):
  for doorLineIndex, doorLine in enumerate(doorLines):
    lineDim = calcLineDim(doorPoints, doorLine)
    wallLine = wallLines[doorWallMap[doorLineIndex]]
    wallPoint_1 = wallPoints[wallLine[0]]
    wallPoint_2 = wallPoints[wallLine[1]]
    fixedValue = (wallPoint_1[1 - lineDim] + wallPoint_2[1 - lineDim]) // 2
    for endPointIndex in range(2):
      doorPoints[doorLine[endPointIndex]][1 - lineDim] = fixedValue
      continue
    continue

## Generate icon candidates
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

  for pointIndex, orientationNeighborMap in pointOrientationNeighborsMap.items():
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

          x_1 = int((point_1[0] + point_3[0]) // 2)
          x_2 = int((point_2[0] + point_4[0]) // 2)
          y_1 = int((point_1[1] + point_2[1]) // 2)
          y_2 = int((point_3[1] + point_4[1]) // 2)

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


## Find two wall lines facing each other and accumuate semantic information in between
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
      for neighbor_1, region_1 in neighbors[1].items():
        for neighbor_2, _ in neighbors[0].items():
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
      for neighbor, region in neighbors.items():
        labelVotes = labelVotesMap[:, region[1][1], region[1][0]] + labelVotesMap[:, region[0][1], region[0][0]] - labelVotesMap[:, region[0][1], region[1][0]] - labelVotesMap[:, region[1][1], region[0][0]]
        neighbors[neighbor] = labelVotes
        continue
      continue
    continue
  return lineNeighbors


## Find neighboring wall line/icon pairs
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

      rectangleFixedValue_1 = (rectanglePoints[rectangle[0]][1 - lineDim] + rectanglePoints[rectangle[1 + lineDim]][1 - lineDim]) // 2
      rectangleFixedValue_2 = (rectanglePoints[rectangle[2 - lineDim]][1 - lineDim] + rectanglePoints[rectangle[3]][1 - lineDim]) // 2
      lineFixedValue = (linePoints[line[0]][1 - lineDim] + linePoints[line[1]][1 - lineDim]) // 2

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
      for index, lineNeighbor in minDistanceLineNeighbors.items():
        rectangleLineNeighbors[rectangleIndex][lineNeighbor[0]] = lineNeighbor[2]
        continue
      pass
    continue

  return rectangleLineNeighbors

## Find the door line to wall line map
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
      fixedValue_1 = (points[line[0]][1 - lineDim] + points[line[1]][1 - lineDim]) // 2
      fixedValue_2 = (points_2[neighborLine[0]][1 - lineDim] + points_2[neighborLine[1]][1 - lineDim]) // 2

      if abs(fixedValue_2 - fixedValue_1) > gap:
        continue

      lineMinValue = points[line[0]][lineDim]
      lineMaxValue = points[line[1]][lineDim]
      ratio = float(maxValue - minValue + 1) / (lineMaxValue - lineMinValue + 1)

      lineMap[lineIndex][neighborLineIndex] = ratio
      continue
    continue

  return lineMap


## Find the one-to-one door line to wall line map after optimization
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
      fixedValue_1 = (points[line[0]][1 - lineDim] + points[line[1]][1 - lineDim]) // 2
      fixedValue_2 = (points_2[neighborLine[0]][1 - lineDim] + points_2[neighborLine[1]][1 - lineDim]) // 2

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


## Find conflicting line pairs
def findConflictLinePairs(points, lines, gap, distanceThreshold, considerEndPoints=False):
  conflictLinePairs = []
  for lineIndex_1, line_1 in enumerate(lines):
    lineDim_1 = calcLineDim(points, line_1)
    point_1 = points[line_1[0]]
    point_2 = points[line_1[1]]
    fixedValue_1 = int(round((point_1[1 - lineDim_1] + point_2[1 - lineDim_1]) // 2))
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

      fixedValue_2 = int(round((point_1[1 - lineDim_2] + point_2[1 - lineDim_2]) // 2))
      minValue_2 = int(min(point_1[lineDim_2], point_2[lineDim_2]))
      maxValue_2 = int(max(point_1[lineDim_2], point_2[lineDim_2]))

      if lineDim_1 == lineDim_2:
        if abs(fixedValue_2 - fixedValue_1) >= distanceThreshold or minValue_1 > maxValue_2 - gap or minValue_2 > maxValue_1 - gap:
          continue

        conflictLinePairs.append((lineIndex_1, lineIndex_2))
        #drawLines(output_prefix + 'lines_' + str(lineIndex_1) + "_" + str(lineIndex_2) + '.png', width, height, points, [line_1, line_2])
      else:
        if minValue_1 > fixedValue_2 - gap or maxValue_1 < fixedValue_2 + gap or minValue_2 > fixedValue_1 - gap or maxValue_2 < fixedValue_1 + gap:
          continue

        conflictLinePairs.append((lineIndex_1, lineIndex_2))
        pass
      continue
    continue

  return conflictLinePairs


## Find conflicting line/icon pairs
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

      minX = max((points[rectangle_1[0]][0] + points[rectangle_1[2]][0]) // 2, (points[rectangle_2[0]][0] + points[rectangle_2[2]][0]) // 2)
      maxX = min((points[rectangle_1[1]][0] + points[rectangle_1[3]][0]) // 2, (points[rectangle_2[1]][0] + points[rectangle_2[3]][0]) // 2)
      if minX > maxX - gap:
        continue
      minY = max((points[rectangle_1[0]][1] + points[rectangle_1[1]][1]) // 2, (points[rectangle_2[0]][1] + points[rectangle_2[1]][1]) // 2)
      maxY = min((points[rectangle_1[2]][1] + points[rectangle_1[3]][1]) // 2, (points[rectangle_2[2]][1] + points[rectangle_2[3]][1]) // 2)
      if minY > maxY - gap:
        continue
      conflictRectanglePairs.append((rectangleIndex_1, rectangleIndex_2))
      continue
    continue

  return conflictRectanglePairs


## Find conflicting icon pairs
def findConflictRectangleLinePairs(rectanglePoints, rectangles, linePoints, lines, gap):
  conflictRectangleLinePairs = []
  for rectangleIndex, rectangle in enumerate(rectangles):
    for lineIndex, line in enumerate(lines):
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

## Find point to line map
def findLinePointMap(points, lines, points_2, gap):
  lineMap = [[] for lineIndex in range(len(lines))]
  for lineIndex, line in enumerate(lines):
    lineDim = calcLineDim(points, line)
    fixedValue = (points[line[0]][1 - lineDim] + points[line[1]][1 - lineDim]) // 2
    for neighborPointIndex, neighborPoint in enumerate(points_2):
      if neighborPoint[lineDim] < points[line[0]][lineDim] + gap or neighborPoint[lineDim] > points[line[1]][lineDim] - gap:
        continue

      if abs((neighborPoint[1 - lineDim] + neighborPoint[1 - lineDim]) // 2 - fixedValue) > gap:
        continue

      lineMap[lineIndex].append(neighborPointIndex)
      continue
    continue
  return lineMap

## Generate primitive candidates from heatmaps
def findCandidatesFromHeatmaps(iconHeatmaps, iconPointOffset, doorPointOffset):
  newIcons = []
  newIconPoints = []
  newDoorLines = []
  newDoorPoints = []
  for iconIndex in range(1, NUM_ICONS + 2):
    heatmap = iconHeatmaps[:, :, iconIndex] > 0.5
    kernel = np.ones((3, 3), dtype=np.uint8)
    heatmap = cv2.dilate(cv2.erode(heatmap.astype(np.uint8), kernel), kernel)
    regions = measure.label(heatmap, background=0)
    for regionIndex in range(regions.min() + 1, regions.max() + 1):
      regionMask = regions == regionIndex
      ys, xs = regionMask.nonzero()
      minX, maxX = xs.min(), xs.max()
      minY, maxY = ys.min(), ys.max()
      if iconIndex <= NUM_ICONS:
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
          newDoorPoints += [[minX, (minY + maxY) // 2, 0, 1], [maxX, (minY + maxY) // 2, 0, 3]]
          newDoorLines.append((doorPointOffset, doorPointOffset + 1))
          doorPointOffset += 2
        elif sizeY >= LENGTH_THRESHOLDS['door'] and sizeX * 2 <= sizeY:
          newDoorPoints += [[(minX + maxX) // 2, minY, 0, 2], [(minX + maxX) // 2, maxY, 0, 0]]
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
            newDoorPoints += [[(minX + minOffset + maxX - maxOffset) // 2, minY, 0, 2], [(minX + minOffset + maxX - maxOffset) // 2, maxY, 0, 0]]
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
            newDoorPoints += [[minX, (minY + minOffset + maxY - maxOffset) // 2, 0, 1], [maxX, (minY + minOffset + maxY - maxOffset) // 2, 0, 3]]
            newDoorLines.append((doorPointOffset, doorPointOffset + 1))
            doorPointOffset += 2
            pass
          pass
        pass
      continue
    continue
  return newIcons, newIconPoints, newDoorLines, newDoorPoints

## Sort lines so that the first point always has smaller x or y
def sortLines(points, lines):
  for lineIndex, line in enumerate(lines):
    lineDim = calcLineDim(points, line)
    if points[line[0]][lineDim] > points[line[1]][lineDim]:
      lines[lineIndex] = (line[1], line[0])
      pass
    continue

## Reconstruct a floorplan via IP optimization
def reconstructFloorplan(wallCornerHeatmaps, doorCornerHeatmaps, iconCornerHeatmaps, iconHeatmaps, roomHeatmaps, output_prefix='test/', densityImage=None, gt_dict=None, gt=False, gap=-1, distanceThreshold=-1, lengthThreshold=-1, debug_prefix='test', heatmapValueThresholdWall=None, heatmapValueThresholdDoor=None, heatmapValueThresholdIcon=None, enableAugmentation=False):
  print('reconstruct')

  wallPoints = []
  iconPoints = []
  doorPoints = []
  
  numWallPoints = 100
  numDoorPoints = 100
  numIconPoints = 100
  if heatmapValueThresholdWall is None:
    heatmapValueThresholdWall = 0.5
    pass
  heatmapValueThresholdDoor = 0.5
  heatmapValueThresholdIcon = 0.5

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

  wallPoints, wallLines, wallPointOrientationLinesMap, wallPointNeighbors, augmentedPointMask = extractCorners(wallCornerHeatmaps, heatmapValueThresholdWall, gap=GAPS['wall_extraction'], augment=enableAugmentation, gt=gt)
  doorPoints, doorLines, doorPointOrientationLinesMap, doorPointNeighbors, _ = extractCorners(doorCornerHeatmaps, heatmapValueThresholdDoor, gap=GAPS['door_extraction'], cornerType='door', gt=gt)
  iconPoints, iconLines, iconPointOrientationLinesMap, iconPointNeighbors, _ = extractCorners(iconCornerHeatmaps, heatmapValueThresholdIcon, gap=GAPS['icon_extraction'], cornerType='icon', gt=gt)

  if not gt:
    for pointIndex, point in enumerate(wallPoints):
      #print((pointIndex, np.array(point[:2]).astype(np.int32).tolist(), point[2], point[3]))
      continue

    wallPoints, wallLines, wallPointOrientationLinesMap, wallPointNeighbors = filterWalls(wallPoints, wallLines)
    pass


  sortLines(doorPoints, doorLines)
  sortLines(wallPoints, wallLines)

  print('the number of points', len(wallPoints), len(doorPoints), len(iconPoints))
  print('the number of lines', len(wallLines), len(doorLines), len(iconLines))


  drawPoints(os.path.join(debug_prefix, "points.png"), width, height, wallPoints, densityImage, pointSize=3)
  drawPointsSeparately(os.path.join(debug_prefix, 'points'), width, height, wallPoints, densityImage, pointSize=3)
  drawLines(os.path.join(debug_prefix, 'lines.png'), width, height, wallPoints, wallLines, [], None, 1, lineColor=255)

  wallMask = drawLineMask(width, height, wallPoints, wallLines)

  labelVotesMap = np.zeros((NUM_ROOMS, height, width))
  #labelMap = np.zeros((NUM_LABELS, height, width))
  #semanticHeatmaps = np.concatenate([iconHeatmaps, roomHeatmaps], axis=2)
  for segmentIndex in range(NUM_ROOMS):
    segmentation_img = roomHeatmaps[:, :, segmentIndex]
    #segmentation_img = (segmentation_img > 0.5).astype(np.float)
    labelVotesMap[segmentIndex] = segmentation_img
    #labelMap[segmentIndex] = segmentation_img
    continue

  labelVotesMap = np.cumsum(np.cumsum(labelVotesMap, axis=1), axis=2)

  icons = findIconsFromLines(iconPoints, iconLines)

  if not gt:
    newIcons, newIconPoints, newDoorLines, newDoorPoints = findCandidatesFromHeatmaps(iconHeatmaps, len(iconPoints), len(doorPoints))

    icons += newIcons
    iconPoints += newIconPoints
    doorLines += newDoorLines
    doorPoints += newDoorPoints
    pass

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


  conflictWallLinePairs = findConflictLinePairs(wallPoints, wallLines, gap=GAPS['wall_conflict'], distanceThreshold=DISTANCES['wall'], considerEndPoints=True)

  conflictDoorLinePairs = findConflictLinePairs(doorPoints, doorLines, gap=GAPS['door_conflict'], distanceThreshold=DISTANCES['door'])
  conflictIconPairs = findConflictRectanglePairs(iconPoints, icons, gap=GAPS['icon_conflict'])

  if False:
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


  if False:
    print(conflictWallLinePairs)
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

  if False:
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

  if True:
    #model = Model("JunctionFilter")
    model = LpProblem("JunctionFilter", LpMinimize)

    #add variables
    w_p = [LpVariable(cat=LpBinary, name="point_" + str(pointIndex)) for pointIndex in range(len(wallPoints))]
    w_l = [LpVariable(cat=LpBinary, name="line_" + str(lineIndex)) for lineIndex in range(len(wallLines))]

    d_l = [LpVariable(cat=LpBinary, name="door_line_" + str(lineIndex)) for lineIndex in range(len(doorLines))]

    i_r = [LpVariable(cat=LpBinary, name="icon_rectangle_" + str(lineIndex)) for lineIndex in range(len(icons))]

    i_types = []
    for iconIndex in range(len(icons)):
      i_types.append([LpVariable(cat=LpBinary, name="icon_type_" + str(iconIndex) + "_" + str(typeIndex)) for typeIndex in range(NUM_ICONS)])
      continue

    l_dir_labels = []
    for lineIndex in range(len(wallLines)):
      dir_labels = []
      for direction in range(2):
        labels = []
        for label in range(NUM_ROOMS):
          labels.append(LpVariable(cat=LpBinary, name="line_" + str(lineIndex) + "_" + str(direction) + "_" + str(label)))
        dir_labels.append(labels)
      l_dir_labels.append(dir_labels)



    #model.update()
    #obj = QuadExpr()
    obj = LpAffineExpression()
    
    if gt:
      for pointIndex in range(len(wallPoints)):
        model += (w_p[pointIndex] == 1, 'gt_point_active_' + str(pointIndex))
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
      for pointIndex, iconIndices in pointIconMap.items():
        break
        iconSum = LpAffineExpression()
        for iconIndex in iconIndices:
          iconSum += i_r[iconIndex]
          continue
        model += (iconSum == 1)
        continue
      pass

    ## Semantic label one hot constraints
    for lineIndex in range(len(wallLines)):
      for direction in range(2):
        labelSum = LpAffineExpression()
        for label in range(NUM_ROOMS):
          labelSum += l_dir_labels[lineIndex][direction][label]
          continue
        model += (labelSum == w_l[lineIndex], 'label_sum_' + str(lineIndex) + '_' + str(direction))
        continue
      continue

    ## Opposite room constraints
    if False:
      oppositeRoomPairs = [(1, 1), (2, 2), (4, 4), (5, 5), (7, 7), (9, 9)]
      for lineIndex in range(len(wallLines)):
        for oppositeRoomPair in oppositeRoomPairs:
          model += (l_dir_labels[lineIndex][0][oppositeRoomPair[0]] + l_dir_labels[lineIndex][0][oppositeRoomPair[1]] <= 1)
          if oppositeRoomPair[0] != oppositeRoomPair[1]:
            model += (l_dir_labels[lineIndex][0][oppositeRoomPair[1]] + l_dir_labels[lineIndex][0][oppositeRoomPair[0]] <= 1)
            pass
          continue
        continue
      pass

    ## Loop constraints
    closeRooms = {}
    for label in range(NUM_ROOMS):
      closeRooms[label] = True
      continue
    closeRooms[1] = False
    closeRooms[2] = False
    #closeRooms[3] = False
    closeRooms[8] = False
    closeRooms[9] = False

    for label in range(NUM_ROOMS):
      if not closeRooms[label]:
        continue
      for pointIndex, orientationLinesMap in enumerate(wallPointOrientationLinesMap):
        for orientation, lines in orientationLinesMap.items():
          direction = int(orientation in [1, 2])
          lineSum = LpAffineExpression()
          for lineIndex in lines:
            lineSum += l_dir_labels[lineIndex][direction][label]
            continue
          for nextOrientation in range(orientation + 1, 8):
            if not (nextOrientation % 4) in orientationLinesMap:
              continue
            nextLines = orientationLinesMap[nextOrientation % 4]
            nextDirection = int((nextOrientation % 4) in [0, 3])
            nextLineSum = LpAffineExpression()
            for nextLineIndex in nextLines:
              nextLineSum += l_dir_labels[nextLineIndex][nextDirection][label]
              continue
            model += (lineSum == nextLineSum)
            break
          continue
        continue
      continue


    ## Exterior constraints
    exteriorLineSum = LpAffineExpression()
    for lineIndex in range(len(wallLines)):
      if lineIndex not in exteriorLines:
        continue
      #direction = exteriorLines[lineIndex]
      label = 0
      model += (l_dir_labels[lineIndex][0][label] + l_dir_labels[lineIndex][1][label] == w_l[lineIndex], 'exterior_wall_' + str(lineIndex))
      exteriorLineSum += w_l[lineIndex]
      continue
    model += (exteriorLineSum >= 1, 'exterior_wall_sum')


    ## Wall line room semantic objectives
    for lineIndex, directionNeighbors in enumerate(wallLineNeighbors):
      for direction, neighbors in enumerate(directionNeighbors):
        labelVotesSum = np.zeros(NUM_ROOMS)
        for neighbor, labelVotes in neighbors.items():
          labelVotesSum += labelVotes
          continue

        votesSum = labelVotesSum.sum()
        if votesSum == 0:
          continue
        labelVotesSum /= votesSum

        for label in range(NUM_ROOMS):
          obj += (l_dir_labels[lineIndex][direction][label] * (0.0 - labelVotesSum[label]) * labelWeight)
          continue
        continue
      continue

    ## Icon corner constraints (one icon corner belongs to at most one icon)
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

    for pointIndex, iconIndices in pointIconsMap.items():
      iconSum = LpAffineExpression()
      for iconIndex in iconIndices:
        iconSum += i_r[iconIndex]
        continue
      model += (iconSum <= 1)
      continue

    ## Wall confidence objective
    wallLineConfidenceMap = roomHeatmaps[:, :, WALL_LABEL_OFFSET]
    #cv2.imwrite(output_prefix + 'confidence.png', (wallLineConfidenceMap * 255).astype(np.uint8))
    wallConfidences = []
    for lineIndex, line in enumerate(wallLines):
      point_1 = np.array(wallPoints[line[0]][:2])
      point_2 = np.array(wallPoints[line[1]][:2])
      lineDim = calcLineDim(wallPoints, line)

      fixedValue = int(round((point_1[1 - lineDim] + point_2[1 - lineDim]) // 2))
      point_1[lineDim], point_2[lineDim] = min(point_1[lineDim], point_2[lineDim]), max(point_1[lineDim], point_2[lineDim])

      point_1[1 - lineDim] = fixedValue - wallLineWidth
      point_2[1 - lineDim] = fixedValue + wallLineWidth

      point_1 = np.maximum(point_1, 0).astype(np.int32)
      point_2 = np.minimum(point_2, sizes - 1).astype(np.int32)

      wallLineConfidence = np.sum(wallLineConfidenceMap[point_1[1]:point_2[1] + 1, point_1[0]:point_2[0] + 1]) / ((point_2[1] + 1 - point_1[1]) * (point_2[0] + 1 - point_1[0])) - 0.5

      obj += (-wallLineConfidence * w_l[lineIndex] * wallWeight)

      wallConfidences.append(wallLineConfidence)
      continue

    if not gt:
      for wallIndex, wallLine in enumerate(wallLines):
        #print('wall confidence', wallIndex, [np.array(wallPoints[pointIndex][:2]).astype(np.int32).tolist() for pointIndex in wallLine], wallConfidences[wallIndex])
        continue
      pass


    ## Door confidence objective
    doorLineConfidenceMap = iconHeatmaps[:, :, DOOR_LABEL_OFFSET]
    #cv2.imwrite(output_prefix + 'confidence.png', (doorLineConfidenceMap * 255).astype(np.uint8))
    #cv2.imwrite(output_prefix + 'segmentation.png', drawSegmentationImage(doorCornerHeatmaps))

    for lineIndex, line in enumerate(doorLines):
      point_1 = np.array(doorPoints[line[0]][:2])
      point_2 = np.array(doorPoints[line[1]][:2])
      lineDim = calcLineDim(doorPoints, line)

      fixedValue = int(round((point_1[1 - lineDim] + point_2[1 - lineDim]) // 2))

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
        doorConfidence = (doorLineConfidence + doorPointConfidence) * 0.5 - 0.5
        #print('door confidence', doorConfidence)
        obj += (-doorConfidence * d_l[lineIndex] * doorWeight)
      else:
        obj += (-0.5 * d_l[lineIndex] * doorWeight)
        pass
      continue

    ## Icon confidence objective  
    for iconIndex, icon in enumerate(icons):
      point_1 = iconPoints[icon[0]]
      point_2 = iconPoints[icon[1]]
      point_3 = iconPoints[icon[2]]
      point_4 = iconPoints[icon[3]]

      x_1 = int((point_1[0] + point_3[0]) // 2)
      x_2 = int((point_2[0] + point_4[0]) // 2)
      y_1 = int((point_1[1] + point_2[1]) // 2)
      y_2 = int((point_3[1] + point_4[1]) // 2)

      iconArea = (x_2 - x_1 + 1) * (y_2 - y_1 + 1)

      if iconArea <= 1e-4:
        print(icon)
        print([iconPoints[pointIndex] for pointIndex in icon])
        print('zero size icon')
        exit(1)
        pass

      iconTypeConfidence = iconHeatmaps[y_1:y_2 + 1, x_1:x_2 + 1, :NUM_ICONS + 1].sum(axis=(0, 1)) / iconArea
      iconTypeConfidence = iconTypeConfidence[1:] - iconTypeConfidence[0]

      if not gt:
        iconPointConfidence = (iconCornerHeatmaps[int(round(point_1[1])), int(round(point_1[0])), 2] + iconCornerHeatmaps[int(round(point_2[1])), int(round(point_2[0])), 3] + iconCornerHeatmaps[int(round(point_3[1])), int(round(point_3[0])), 1] + iconCornerHeatmaps[int(round(point_4[1])), int(round(point_4[0])), 0]) // 4 - 0.5
        iconConfidence = (iconTypeConfidence + iconPointConfidence) * 0.5
      else:
        iconConfidence = iconTypeConfidence
        pass

      #print('icon confidence', iconConfidence)
      for typeIndex in range(NUM_ICONS):
        obj += (-i_types[iconIndex][typeIndex] * (iconConfidence[typeIndex]) * iconTypeWeight)
        continue
      continue

    ## Icon type one hot constraints
    for iconIndex in range(len(icons)):
      typeSum = LpAffineExpression()
      for typeIndex in range(NUM_ICONS - 1):
        typeSum += i_types[iconIndex][typeIndex]
        continue
      model += (typeSum == i_r[iconIndex])
      continue


    ## Line sum constraints (each orientation has at most one wall line)
    for pointIndex, orientationLinesMap in enumerate(wallPointOrientationLinesMap):
      for orientation, lines in orientationLinesMap.items():
        #if len(lines) > 1:
        #print(lines)
        lineSum = LpAffineExpression()
        for lineIndex in lines:
          lineSum += w_l[lineIndex]
          continue

        model += (lineSum == w_p[pointIndex], "line_sum_" + str(pointIndex) + "_" + str(orientation))
        continue
      continue

    ## Conflict constraints
    for index, conflictLinePair in enumerate(conflictWallLinePairs):
      model += (w_l[conflictLinePair[0]] + w_l[conflictLinePair[1]] <= 1, 'conflict_wall_line_pair_' + str(index))
      continue

    for index, conflictLinePair in enumerate(conflictDoorLinePairs):
      model += (d_l[conflictLinePair[0]] + d_l[conflictLinePair[1]] <= 1, 'conflict_door_line_pair_' + str(index))
      continue

    for index, conflictIconPair in enumerate(conflictIconPairs):
      model += (i_r[conflictIconPair[0]] + i_r[conflictIconPair[1]] <= 1, 'conflict_icon_pair_' + str(index))
      continue

    for index, conflictLinePair in enumerate(conflictIconWallPairs):
      model += (i_r[conflictLinePair[0]] + w_l[conflictLinePair[1]] <= 1, 'conflict_icon_wall_pair_' + str(index))
      continue


    ## Door wall constraints (a door must sit on one and only one wall)
    for doorIndex, lines in enumerate(doorWallLineMap):
      if len(lines) == 0:
        model += (d_l[doorIndex] == 0, 'door_not_on_walls_' + str(doorIndex))
        continue
      lineSum = LpAffineExpression()
      for lineIndex in lines:
        lineSum += w_l[lineIndex]
        continue
      model += (d_l[doorIndex] <= lineSum, 'd_wall_line_sum_' + str(doorIndex))
      continue

    doorWallPointMap = findLinePointMap(doorPoints, doorLines, wallPoints, gap=GAPS['door_point_conflict'])
    for doorIndex, points in enumerate(doorWallPointMap):
      if len(points) == 0:
        continue
      pointSum = LpAffineExpression()
      for pointIndex in points:
        model += (d_l[doorIndex] + w_p[pointIndex] <= 1, 'door_on_two_walls_' + str(doorIndex) + '_' + str(pointIndex))
        continue
      continue

    if False:
      #model += (w_l[6] == 1)
      pass

    model += obj
    model.solve()

    #model.writeLP(debug_prefix + '/model.lp')
    print('Optimization information', LpStatus[model.status], value(model.objective))

    if LpStatus[model.status] == 'Optimal':
      filteredWallLines = []
      filteredWallLabels = []
      filteredWallTypes = []
      wallPointLabels = [[-1, -1, -1, -1] for pointIndex in range(len(wallPoints))]

      for lineIndex, lineVar in enumerate(w_l):
        if lineVar.varValue < 0.5:
          continue
        filteredWallLines.append(wallLines[lineIndex])

        filteredWallTypes.append(0)

        labels = [11, 11]
        for direction in range(2):
          for label in range(NUM_ROOMS):
            if l_dir_labels[lineIndex][direction][label].varValue > 0.5:
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

      if not gt:
        adjustPoints(wallPoints, filteredWallLines)
        mergePoints(wallPoints, filteredWallLines)
        adjustPoints(wallPoints, filteredWallLines)
        filteredWallLabels = [filteredWallLabels[lineIndex] for lineIndex in range(len(filteredWallLines)) if filteredWallLines[lineIndex][0] != filteredWallLines[lineIndex][1]]
        filteredWallLines = [line for line in filteredWallLines if line[0] != line[1]]
        pass


      drawLines(output_prefix + 'result_line.png', width, height, wallPoints, filteredWallLines, filteredWallLabels, lineColor=255)
      #resultImage = drawLines('', width, height, wallPoints, filteredWallLines, filteredWallLabels, None, lineWidth=5, lineColor=255)

      filteredDoorLines = []
      filteredDoorTypes = []
      for lineIndex, lineVar in enumerate(d_l):
        if lineVar.varValue < 0.5:
          continue
        print(('door', lineIndex, [doorPoints[pointIndex][:2] for pointIndex in doorLines[lineIndex]]))
        filteredDoorLines.append(doorLines[lineIndex])

        filteredDoorTypes.append(0)
        continue

      filteredDoorWallMap = findLineMapSingle(doorPoints, filteredDoorLines, wallPoints, filteredWallLines, gap=GAPS['wall_door_neighbor'])
      adjustDoorPoints(doorPoints, filteredDoorLines, wallPoints, filteredWallLines, filteredDoorWallMap)
      drawLines(output_prefix + 'result_door.png', width, height, doorPoints, filteredDoorLines, lineColor=255)

      filteredIcons = []
      filteredIconTypes = []
      for iconIndex, iconVar in enumerate(i_r):
        if iconVar.varValue < 0.5:
          continue

        filteredIcons.append(icons[iconIndex])
        iconType = -1
        for typeIndex in range(NUM_ICONS):
          if i_types[iconIndex][typeIndex].varValue > 0.5:
            iconType = typeIndex
            break
          continue

        print(('icon', iconIndex, iconType, [iconPoints[pointIndex][:2] for pointIndex in icons[iconIndex]]))

        filteredIconTypes.append(iconType)
        continue

      #adjustPoints(iconPoints, filteredIconLines)
      #drawLines(output_prefix + 'lines_results_icon.png', width, height, iconPoints, filteredIconLines)
      drawRectangles(output_prefix + 'result_icon.png', width, height, iconPoints, filteredIcons, filteredIconTypes)

      #resultImage = drawLines('', width, height, doorPoints, filteredDoorLines, [], resultImage, lineWidth=3, lineColor=0)
      #resultImage = drawRectangles('', width, height, iconPoints, filteredIcons, filteredIconTypes, 2, resultImage)
      #cv2.imwrite(output_prefix + 'result.png', resultImage)

      filteredWallPoints = []
      filteredWallPointLabels = []
      orientationMap = {}
      for pointType, orientationOrientations in enumerate(POINT_ORIENTATIONS):
        for orientation, orientations in enumerate(orientationOrientations):
          orientationMap[orientations] = orientation

      for pointIndex, point in enumerate(wallPoints):
        orientations = []
        orientationLines = {}
        for orientation, lines in wallPointOrientationLinesMap[pointIndex].items():
          orientationLine = -1
          for lineIndex in lines:
            if w_l[lineIndex].varValue > 0.5:
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


      with open(output_prefix + 'floorplan.txt', 'w') as result_file:
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

          x_1 = int((point_1[0] + point_3[0]) // 2)
          x_2 = int((point_2[0] + point_4[0]) // 2)
          y_1 = int((point_1[1] + point_2[1]) // 2)
          y_2 = int((point_3[1] + point_4[1]) // 2)

          result_file.write(str(x_1) + '\t' + str(y_1) + '\t')
          result_file.write(str(x_2) + '\t' + str(y_2) + '\t')
          result_file.write(iconNumberNameMap[filteredIconTypes[iconIndex]] + '\t')
          #result_file.write(str(iconNumberStyleMap[filteredIconTypes[iconIndex]]) + '\t')
          result_file.write('1\t')
          result_file.write('1\n')

        result_file.close()


      # writePoints(filteredWallPoints, filteredWallPointLabels, output_prefix=output_prefix)
        
      # if len(filteredDoorLines) > 0:
      #   writeDoors(doorPoints, filteredDoorLines, filteredDoorTypes, output_prefix=output_prefix)
      #   pass
      # else:
      #   try:
      #     os.remove(output_prefix + 'doors_out.txt')
      #   except OSError:
      #     pass

      # if len(filteredIcons) > 0:
      #   writeIcons(iconPoints, filteredIcons, filteredIconTypes, output_prefix=output_prefix)
      #   pass
      # else:
      #   try:
      #     os.remove(output_prefix + 'icons_out.txt')
      #   except OSError:
      #     pass
      #   pass

    else:
      print('infeasible')
      #model.ComputeIIS()
      #model.write("test/model.ilp")
      return {}
      pass

  result_dict = {'wall': [wallPoints, filteredWallLines, filteredWallLabels], 'door': [doorPoints, filteredDoorLines, []], 'icon': [iconPoints, filteredIcons, filteredIconTypes]}
  return result_dict
