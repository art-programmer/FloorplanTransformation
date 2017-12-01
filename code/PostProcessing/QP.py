from gurobipy import *
import cv2
import numpy as np
import sys
import csv
import copy

if len(sys.argv) == 2 and int(sys.argv[1]) == 1:
  withoutQP = True
else:
  withoutQP = False
  pass


gap = 10

pointWeight = 10000
junctionWeight = 100
augmentedJunctionWeight = 50
labelWeight = 10

wallWeight = 10
doorWeight = 10
iconWeight = 10

#wallTypeWeight = 10
#doorTypeWeight = 10
iconTypeWeight = 10

#doorExposureWeight = 0


numWallTypes = 2
numDoorTypes = 6
numIconTypes = 10
numRoomTypes = 11
numLabels = numWallTypes + numDoorTypes + numIconTypes + numRoomTypes + 1

iconOffset = 13
wallOffset = 11
doorOffset = 23


colorMap = [
  [128, 128, 128],
  [0, 0, 255],
  [64, 128, 192],
  [0, 128, 0],
  [192, 0, 0],
  [128, 0, 128],
  [128, 128, 192],
  [128, 192, 192],
  [0, 128, 0],
  [0, 0, 128],
  [128, 128, 0],
  [0, 128, 128]
  #[0, 128, 128],
  #[128, 0, 128],
]

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



floorplan = cv2.imread('test/floorplan.png')



width = floorplan.shape[1]
height = floorplan.shape[0]
maxDim = max(width, height)

pointOrientations = [[(2, ), (3, ), (0, ), (1, )], [(0, 3), (0, 1), (1, 2), (2, 3)], [(1, 2, 3), (0, 2, 3), (0, 1, 3), (0, 1, 2)], [(0, 1, 2, 3)]]
orientationRanges = [[width, 0, 0, 0], [width, height, width, 0], [width, height, 0, height], [0, height, 0, 0]]



iconNames = ['bathtub', 'cooking_counter', 'toilet', 'entrance', 'washing_basin', 'washing_basin', 'washing_basin', 'special', 'special', 'stairs']
iconStyles = [1, 1, 1, 1, 1, 2, 1, 1, 3, 1]
iconNameNumberMap = dict(zip(iconNames, xrange(len(iconNames))))
iconNumberNameMap = dict(zip(xrange(len(iconNames)), iconNames))
iconNumberStyleMap = dict(zip(xrange(len(iconStyles)), iconStyles))

def calcLineDim(points, line):
  point_1 = points[line[0]]
  point_2 = points[line[1]]
  if point_2[0] - point_1[0] > point_2[1] - point_1[1]:
    lineDim = 0
  else:
    lineDim = 1
  return lineDim

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
      icons_file.write(str(iconNumberStyleMap[iconTypes[iconIndex]]) + '\t')
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
      if point_2[0] - point_1[0] > point_2[1] - point_1[1]:
        lineDimNeighbor = 0
      else:
        lineDimNeighbor = 1
        pass
      
      if lineDimNeighbor != lineDim:
        continue
      if neighborLine[0] != line[0] and neighborLine[0] != line[1] and neighborLine[1] != line[0] and neighborLine[1] != line[1]:
        continue
      neighbors.append(neighborLineIndex)
      continue
    lineNeighbors.append(neighbors)
    continue

  visitedLines = {}
  for lineIndex in xrange(len(lines)):
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
    
    pointGroup = []
    for line in lineGroup:
      for index in xrange(2):
        pointIndex = lines[line][index]
        if pointIndex not in pointGroup:
          pointGroup.append(pointIndex)
          pass
        continue
      continue
          
    lineDim = calcLineDim(points, lines[lineGroup[0]])
    fixedValue = 0
    for point in pointGroup:
      fixedValue += points[point][1 - lineDim]
      continue
    fixedValue /= len(pointGroup)
    
    for point in pointGroup:
      points[point][1 - lineDim] = fixedValue
      continue
    continue
  

def adjustDoorPoints(doorPoints, doorLines, wallPoints, wallLines, doorWallMap):
  for doorLineIndex, doorLine in enumerate(doorLines):
    lineDim = calcLineDim(doorPoints, doorLine)
    wallLine = wallLines[doorWallMap[doorLineIndex]]
    wallPoint_1 = wallPoints[wallLine[0]]
    wallPoint_2 = wallPoints[wallLine[1]]
    fixedValue = (wallPoint_1[1 - lineDim] + wallPoint_2[1 - lineDim]) / 2
    for endPointIndex in xrange(2):
      doorPoints[doorLine[endPointIndex]][1 - lineDim] = fixedValue
      continue
    continue
  
  
def drawLineMask(points, lines, lineWidth = 5, backgroundImage = None):
  lineMask = np.zeros((height, width))
  
  for lineIndex, line in enumerate(lines):
    point_1 = points[line[0]]
    point_2 = points[line[1]]
    lineDim = calcLineDim(points, line)


    fixedValue = int(round((point_1[1 - lineDim] + point_2[1 - lineDim]) / 2))
    minValue = int(min(point_1[lineDim], point_2[lineDim]))
    maxValue = int(max(point_1[lineDim], point_2[lineDim]))
    if lineDim == 0:
      lineMask[max(fixedValue - lineWidth, 0):min(fixedValue + lineWidth, height), minValue:maxValue + 1] = 1
    else:
      lineMask[minValue:maxValue + 1, max(fixedValue - lineWidth, 0):min(fixedValue + lineWidth, width)] = 1
      pass
    continue
  return lineMask


def drawLinesToyExample(filename, width, height, points, lines, lineLabels = [], backgroundImage = None, lineWidth = 5, lineColor = 0):
  if backgroundImage is None:
    image = np.ones((height, width, 4), np.uint8) * 255
    image[:, :, 3] = 0
  else:
    image = backgroundImage
    pass
  
  for lineIndex, line in enumerate(lines):
    point_1 = points[line[0]]
    point_2 = points[line[1]]
    lineDim = calcLineDim(points, line)


    fixedValue = int(round((point_1[1 - lineDim] + point_2[1 - lineDim]) / 2))
    minValue = int(round(min(point_1[lineDim], point_2[lineDim])))
    maxValue = int(round(max(point_1[lineDim], point_2[lineDim])))
    if len(lineLabels) == 0:
      #lineColor = np.random.rand(3) * 255
      if lineDim == 0:
        image[max(fixedValue - lineWidth, 0):min(fixedValue + lineWidth, height), minValue:maxValue + 1, :] = lineColor
      else:
        image[minValue:maxValue + 1, max(fixedValue - lineWidth, 0):min(fixedValue + lineWidth, width), :] = lineColor
    else:
      labels = lineLabels[lineIndex]
      isExterior = False
      if lineDim == 0:
        for c in xrange(3):
          if labels[0] == 0 and lineIndex not in [15, 12]:
            image[max(fixedValue - lineWidth, 0):min(fixedValue, height), minValue - lineWidth:maxValue + lineWidth, c] = colorMap[labels[0]][c]
            isExterior = True
          else:
            image[max(fixedValue - lineWidth, 0):min(fixedValue, height), minValue:maxValue, c] = colorMap[labels[0]][c]
            pass
          if labels[1] == 0 and lineIndex not in [15, 12]:
            image[max(fixedValue, 0):min(fixedValue + lineWidth, height), minValue - lineWidth:maxValue + lineWidth, c] = colorMap[labels[1]][c]
            isExterior = True
          else:
            image[max(fixedValue, 0):min(fixedValue + lineWidth, height), minValue:maxValue, c] = colorMap[labels[1]][c]
            pass
          continue
        if isExterior:
          image[max(fixedValue - lineWidth, 0):min(fixedValue + lineWidth, height), minValue - lineWidth:maxValue + lineWidth, 3] = 255
        else:
          image[max(fixedValue - lineWidth, 0):min(fixedValue + lineWidth, height), minValue:maxValue, 3] = 255
      else:
        for c in xrange(3):
          if labels[1] == 0 and lineIndex not in [15, 12]:
            image[minValue - lineWidth:maxValue + lineWidth, max(fixedValue - lineWidth, 0):min(fixedValue, width), c] = colorMap[labels[1]][c]
            isExterior = True
          else:
            image[minValue:maxValue, max(fixedValue - lineWidth, 0):min(fixedValue, width), c] = colorMap[labels[1]][c]
            pass
          if labels[0] == 0 and lineIndex not in [15, 12]:
            image[minValue - lineWidth:maxValue + lineWidth, max(fixedValue, 0):min(fixedValue + lineWidth, width), c] = colorMap[labels[0]][c]
            isExterior = True
          else:
            image[minValue:maxValue, max(fixedValue, 0):min(fixedValue + lineWidth, width), c] = colorMap[labels[0]][c]
            pass
          continue
        if isExterior:
          image[minValue - lineWidth:maxValue + lineWidth, max(fixedValue - lineWidth, 0):min(fixedValue + lineWidth, width), 3] = 255
        else:
          image[minValue:maxValue, max(fixedValue - lineWidth, 0):min(fixedValue + lineWidth, width), 3] = 255
        
  if filename == '':
    return image
  else:
    cv2.imwrite(filename, image)



def drawLines(filename, width, height, points, lines, lineLabels = [], backgroundImage = None, lineWidth = 5, lineColor = 255):
  if backgroundImage is None:
    image = np.ones((height, width, 3), np.uint8) * 0
  else:
    image = backgroundImage
    pass
  
  for lineIndex, line in enumerate(lines):
    point_1 = points[line[0]]
    point_2 = points[line[1]]
    lineDim = calcLineDim(points, line)


    fixedValue = int(round((point_1[1 - lineDim] + point_2[1 - lineDim]) / 2))
    minValue = int(round(min(point_1[lineDim], point_2[lineDim])))
    maxValue = int(round(max(point_1[lineDim], point_2[lineDim])))
    if len(lineLabels) == 0:
      lineColor = np.random.rand(3) * 255
      if lineDim == 0:
        image[max(fixedValue - lineWidth, 0):min(fixedValue + lineWidth, height), minValue:maxValue + 1, :] = lineColor
      else:
        image[minValue:maxValue + 1, max(fixedValue - lineWidth, 0):min(fixedValue + lineWidth, width), :] = lineColor
    else:
      labels = lineLabels[lineIndex]
      isExterior = False
      if lineDim == 0:
        for c in xrange(3):
          image[max(fixedValue - lineWidth, 0):min(fixedValue, height), minValue:maxValue, c] = colorMap[labels[0]][c]
          image[max(fixedValue, 0):min(fixedValue + lineWidth, height), minValue:maxValue, c] = colorMap[labels[1]][c]
          continue
      else:
        for c in xrange(3):
          image[minValue:maxValue, max(fixedValue - lineWidth, 0):min(fixedValue, width), c] = colorMap[labels[1]][c]
          image[minValue:maxValue, max(fixedValue, 0):min(fixedValue + lineWidth, width), c] = colorMap[labels[0]][c]
          continue
        pass
      pass
    continue
          
  if filename == '':
    return image
  else:
    cv2.imwrite(filename, image)


def drawRectangles(filename, width, height, points, rectangles, labels, lineWidth = 2, backgroundImage = None, rectangleColor = None):
  if backgroundImage is None:
    image = np.ones((height, width, 3), np.uint8) * 0
  else:
    image = backgroundImage
    pass
  
  for rectangleIndex, rectangle in enumerate(rectangles):
    point_1 = points[rectangle[0]]
    point_2 = points[rectangle[1]]
    point_3 = points[rectangle[2]]
    point_4 = points[rectangle[3]]

    point_1 = (int(point_1[0]), int(point_1[1]))
    point_2 = (int(point_2[0]), int(point_2[1]))
    point_3 = (int(point_3[0]), int(point_3[1]))
    point_4 = (int(point_4[0]), int(point_4[1]))


    if len(labels) == 0:
      if rectangleColor is None:
        color = np.random.rand(3) * 255
      else:
        color = rectangleColor
    else:
      color = colorMap[labels[rectangleIndex]]
                       
    image[max(point_1[1] - lineWidth, 0):min(point_1[1] + lineWidth, height), point_1[0]:point_2[0] + 1, :] = color
    image[max(point_3[1] - lineWidth, 0):min(point_3[1] + lineWidth, height), point_3[0]:point_4[0] + 1, :] = color
    image[point_1[1]:point_3[1] + 1, max(point_1[0] - lineWidth, 0):min(point_1[0] + lineWidth, width), :] = color
    image[point_2[1]:point_4[1] + 1, max(point_2[0] - lineWidth, 0):min(point_2[0] + lineWidth, width), :] = color

    continue
  
  if filename == '':
    return image
  else:
    cv2.imwrite(filename, image)


def calcPointInfo(points, gap, minDistanceOnly = False, doubleDirection = False):
  lines = []  
  pointOrientationLinesMap = []
  pointNeighbors = [[] for point in points]
  
  for pointIndex, point in enumerate(points):
    pointType = point[2]
    orientations = pointOrientations[pointType][point[3]]
    orientationLines = {}
    for orientation in orientations:
      orientationLines[orientation] = []
      continue
    pointOrientationLinesMap.append(orientationLines)
    continue


  for pointIndex, point in enumerate(points):
    pointType = point[2]
    orientations = pointOrientations[pointType][point[3]]
    for orientation in orientations:
      oppositeOrientation = (orientation + 2) % 4
      ranges = copy.deepcopy(orientationRanges[orientation])
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

      for c in xrange(2):
        ranges[c] = min(ranges[c], point[c] - deltas[c])
        ranges[c + 2] = max(ranges[c + 2], point[c] + deltas[c])
        continue
        
      neighborPoints = []
      minDistance = max(width, height)
      minDistanceNeighborPoint = -1
        
      for neighborPointIndex, neighborPoint in enumerate(points):
        if (neighborPointIndex <= pointIndex and not doubleDirection) or neighborPointIndex == pointIndex:
          continue

        neighborOrientations = pointOrientations[neighborPoint[2]][neighborPoint[3]]
        if oppositeOrientation not in neighborOrientations:
          continue

            
        inRange = True
        for c in xrange(2):
          if neighborPoint[c] < ranges[c] or neighborPoint[c] > ranges[c + 2]:
            inRange = False
            break
          continue

        if not inRange or abs(neighborPoint[lineDim] - point[lineDim]) < max(abs(neighborPoint[1 - lineDim] - point[1 - lineDim]), 1):
          continue

        if minDistanceOnly:
          distance = abs(neighborPoint[lineDim] - point[lineDim])
          if distance < minDistance:
            minDistance = distance
            minDistanceNeighborPoint = neighborPointIndex
            pass
        else:
          neighborPoints.append(neighborPointIndex)
          pass
        continue


      if minDistanceOnly and minDistanceNeighborPoint >= 0:
        neighborPoints.append(minDistanceNeighborPoint)
        pass
        

      for neighborPointIndex in neighborPoints:
        neighborPoint = points[neighborPointIndex]

        if doubleDirection and ((pointIndex, neighborPointIndex) in lines or (neighborPointIndex, pointIndex) in lines):
          continue
          
        lineIndex = len(lines)
        pointOrientationLinesMap[pointIndex][orientation].append(lineIndex)
        #print(str(neighborPointIndex) + ' ' + str(oppositeOrientation))
        #if neighborPoint[2] == 0:
        #pointOrientationLinesMap[neighborPointIndex][pointOrientationLinesMap[neighborPointIndex].keys()[0]].append(lineIndex)
        #else:
        pointOrientationLinesMap[neighborPointIndex][oppositeOrientation].append(lineIndex)
        pointNeighbors[pointIndex].append(neighborPointIndex)
        pointNeighbors[neighborPointIndex].append(pointIndex)

        if points[pointIndex][0] + points[pointIndex][1] < points[neighborPointIndex][0] + points[neighborPointIndex][1]:
          #lines.append([pointIndex, neighborPointIndex, cost, point[4]])
          lines.append((pointIndex, neighborPointIndex))
        else:
          #lines.append([neighborPointIndex, pointIndex, cost, point[4]])
          lines.append((neighborPointIndex, pointIndex))
          pass
        continue
      continue
    continue

  
  return lines, pointOrientationLinesMap, pointNeighbors


def findIcons(points, gap, minDistanceOnly = False, maxLengths = (10000, 10000)):
  pointOrientationNeighborsMap = []
    
  for pointIndex, point in enumerate(points):
    pointType = point[2]
    orientations = pointOrientations[pointType][point[3]]
    orientationNeighbors = {}
    for orientation in orientations:
      orientationNeighbors[orientation] = []
      continue
    pointOrientationNeighborsMap.append(orientationNeighbors)
    continue


  for pointIndex, point in enumerate(points):
    pointType = point[2]
    orientations = pointOrientations[pointType][point[3]]
    for orientation in orientations:
      oppositeOrientation = (orientation + 2) % 4
      ranges = copy.deepcopy(orientationRanges[orientation])
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

      for c in xrange(2):
        ranges[c] = min(ranges[c], point[c] - deltas[c])
        ranges[c + 2] = max(ranges[c + 2], point[c] + deltas[c])
        continue
        
      neighborPoints = []
      minDistance = max(width, height)
      minDistanceNeighborPoint = -1

      for neighborPointIndex, neighborPoint in enumerate(points):
        if neighborPointIndex <= pointIndex:
          continue
        neighborOrientations = pointOrientations[neighborPoint[2]][neighborPoint[3]]
        if oppositeOrientation not in neighborOrientations:
          continue
            
        inRange = True
        for c in xrange(2):
          if neighborPoint[c] < ranges[c] or neighborPoint[c] > ranges[c + 2]:
            inRange = False
            break
          continue

        if not inRange or abs(neighborPoint[lineDim] - point[lineDim]) < max(abs(neighborPoint[1 - lineDim] - point[1 - lineDim]), gap):
          continue

        distance = abs(neighborPoint[lineDim] - point[lineDim])
        if distance > maxLengths[lineDim]:
          continue
          
        if minDistanceOnly:
          if distance < minDistance:
            minDistance = distance
            minDistanceNeighborPoint = neighborPointIndex
            pass
          pass
        else:
          neighborPoints.append(neighborPointIndex)
          pass
        continue

      if minDistanceOnly and minDistanceNeighborPoint >= 0:
        neighborPoints.append(minDistanceNeighborPoint)
        pass
      
      for neighborPointIndex in neighborPoints:
        pointOrientationNeighborsMap[pointIndex][orientation].append(neighborPointIndex)
        pointOrientationNeighborsMap[neighborPointIndex][oppositeOrientation].append(pointIndex)
        continue
      continue
    continue

  
  icons = []
  orderedOrientations = (1, 2, 3, 0)
  for pointIndex_1, orientationNeighbors in enumerate(pointOrientationNeighborsMap):
    if orderedOrientations[0] not in orientationNeighbors or ((orderedOrientations[3] + 2) % 4) not in orientationNeighbors:
      continue
    pointIndices_4 = orientationNeighbors[(orderedOrientations[3] + 2) % 4]
    for pointIndex_2 in orientationNeighbors[orderedOrientations[0]]:
      if orderedOrientations[1] not in pointOrientationNeighborsMap[pointIndex_2]:
        continue
      for pointIndex_3 in pointOrientationNeighborsMap[pointIndex_2][orderedOrientations[1]]:
        if orderedOrientations[2] not in pointOrientationNeighborsMap[pointIndex_3]:
          continue
        for pointIndex_4 in pointOrientationNeighborsMap[pointIndex_3][orderedOrientations[2]]:
          if pointIndex_4 in pointIndices_4:
            icons.append((pointIndex_1, pointIndex_2, pointIndex_4, pointIndex_3, (points[pointIndex_1][4] + points[pointIndex_2][4] + points[pointIndex_3][4] + points[pointIndex_4][4]) / 4))
            pass
          continue
        continue
      continue
    continue

  return icons


def findLineNeighbors(points, lines, gap):
  lineNeighbors = [[{}, {}] for lineIndex in xrange(len(lines))]
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
          #labelVotes = (labelVotesMap[:, fixedValue_2, maxValue] + labelVotesMap[:, fixedValue_1, minValue] - labelVotesMap[:, fixedValue_2, minValue] - labelVotesMap[:, fixedValue_1, maxValue])
          region = ((minValue, fixedValue_1), (maxValue, fixedValue_2))
          lineNeighbors[lineIndex][1][neighborLineIndex] = region
          lineNeighbors[neighborLineIndex][0][lineIndex] = region
        else:
          #labelVotes = (labelVotesMap[:, fixedValue_1, maxValue] + labelVotesMap[:, fixedValue_2, minValue] - labelVotesMap[:, fixedValue_1, minValue] - labelVotesMap[:, fixedValue_2, maxValue])
          region = ((minValue, fixedValue_2), (maxValue, fixedValue_1))
          lineNeighbors[lineIndex][0][neighborLineIndex] = region
          lineNeighbors[neighborLineIndex][1][lineIndex] = region
      else:
        if fixedValue_1 < fixedValue_2:
          #labelVotes = (labelVotesMap[:, maxValue, fixedValue_2] + labelVotesMap[:, minValue, fixedValue_1] - labelVotesMap[:, minValue, fixedValue_2] - labelVotesMap[:, maxValue, fixedValue_1])
          region = ((fixedValue_1, minValue), (fixedValue_2, maxValue))
          lineNeighbors[lineIndex][0][neighborLineIndex] = region
          lineNeighbors[neighborLineIndex][1][lineIndex] = region
        else:
          #labelVotes = (labelVotesMap[:, maxValue, fixedValue_1] + labelVotesMap[:, minValue, fixedValue_2] - labelVotesMap[:, minValue, fixedValue_1] - labelVotesMap[:, maxValue, fixedValue_2])
          region = ((fixedValue_2, minValue), (fixedValue_1, maxValue))
          lineNeighbors[lineIndex][1][neighborLineIndex] = region
          lineNeighbors[neighborLineIndex][0][lineIndex] = region
          pass
        pass
      continue
    continue

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



def findLineNeighborsCross(points, lines, points_2, lines_2, lineNeighbors_2, gap):
  lineNeighbors = [[{}, {}] for lineIndex in xrange(len(lines))]
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
      fixedValue_1 = points[line[0]][1 - lineDim]
      fixedValue_2 = points_2[neighborLine[0]][1 - lineDim]
      
      if abs(fixedValue_2 - fixedValue_1) < gap:
        continue
      minValue = int(minValue)
      maxValue = int(maxValue)
      fixedValue_1 = int(fixedValue_1)
      fixedValue_2 = int(fixedValue_2)

      if lineDim == 0:
        if fixedValue_1 < fixedValue_2:
          #labelVotes = (labelVotesMap[:, fixedValue_2, maxValue] + labelVotesMap[:, fixedValue_1, minValue] - labelVotesMap[:, fixedValue_2, minValue] - labelVotesMap[:, fixedValue_1, maxValue])
          region = ((minValue, fixedValue_1), (maxValue, fixedValue_2))
          lineNeighbors[lineIndex][1][neighborLineIndex] = region
          #lineNeighbors[neighborLineIndex][0][lineIndex] = region
        else:
          #labelVotes = (labelVotesMap[:, fixedValue_1, maxValue] + labelVotesMap[:, fixedValue_2, minValue] - labelVotesMap[:, fixedValue_1, minValue] - labelVotesMap[:, fixedValue_2, maxValue])
          region = ((minValue, fixedValue_2), (maxValue, fixedValue_1))
          lineNeighbors[lineIndex][0][neighborLineIndex] = region
          #lineNeighbors[neighborLineIndex][1][lineIndex] = region
      else:
        if fixedValue_1 < fixedValue_2:
          #labelVotes = (labelVotesMap[:, maxValue, fixedValue_2] + labelVotesMap[:, minValue, fixedValue_1] - labelVotesMap[:, minValue, fixedValue_2] - labelVotesMap[:, maxValue, fixedValue_1])
          region = ((fixedValue_1, minValue), (fixedValue_2, maxValue))
          lineNeighbors[lineIndex][0][neighborLineIndex] = region
          #lineNeighbors[neighborLineIndex][1][lineIndex] = region
        else:
          #labelVotes = (labelVotesMap[:, maxValue, fixedValue_1] + labelVotesMap[:, minValue, fixedValue_2] - labelVotesMap[:, minValue, fixedValue_1] - labelVotesMap[:, maxValue, fixedValue_2])
          region = ((fixedValue_2, minValue), (fixedValue_1, maxValue))
          lineNeighbors[lineIndex][1][neighborLineIndex] = region
          #lineNeighbors[neighborLineIndex][0][lineIndex] = region
          pass
        pass
      continue
    continue


  newLineNeighbors = [[{}, {}] for lineIndex in xrange(len(lines))]
  for lineIndex, neighbors in enumerate(lineNeighbors):
    lineDim = calcLineDim(points, lines[lineIndex])
    for direction in xrange(2):
      for neighbor_1, region_1 in neighbors[direction].iteritems():
        neighborValid = True
        for neighbor_2, region_2 in neighbors[direction].iteritems():
          if neighbor_2 == neighbor_1:
            continue
          if neighbor_1 not in lineNeighbors_2[neighbor_2][direction]:
            continue
          if region_2[0][lineDim] < region_1[0][lineDim] + gap and region_2[1][lineDim] > region_1[1][lineDim] - gap:
            neighborValid = False
            break
          continue
        
        if neighborValid:
          newLineNeighbors[lineIndex][direction][neighbor_1] = region_1
          pass
        continue
      continue
    continue
  
  return newLineNeighbors


def findRectangleLineNeighbors(rectanglePoints, rectangles, linePoints, lines, lineNeighbors, gap, distanceThreshold):
  rectangleLineNeighbors = [{} for rectangleIndex in xrange(len(rectangles))]
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
  lineMap = [{} for lineIndex in xrange(len(lines))]
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


def findConflictLinePairs(points, lines, gap):
  conflictLinePairs = []
  for lineIndex_1, line_1 in enumerate(lines):
    point_1 = points[line_1[0]]
    point_2 = points[line_1[1]]
    if point_2[0] - point_1[0] > point_2[1] - point_1[1]:
      lineDim_1 = 0
    else:
      lineDim_1 = 1
      pass

    fixedValue_1 = int(round((point_1[1 - lineDim_1] + point_2[1 - lineDim_1]) / 2))
    minValue_1 = int(min(point_1[lineDim_1], point_2[lineDim_1]))
    maxValue_1 = int(max(point_1[lineDim_1], point_2[lineDim_1]))

    for lineIndex_2, line_2 in enumerate(lines):
      if lineIndex_2 <= lineIndex_1:
        continue
      
      point_1 = points[line_2[0]]
      point_2 = points[line_2[1]]
      if point_2[0] - point_1[0] > point_2[1] - point_1[1]:
        lineDim_2 = 0
      else:
        lineDim_2 = 1
        pass
      
      if (line_1[0] == line_2[0] or line_1[1] == line_2[1]) and lineDim_2 == lineDim_1:
        conflictLinePairs.append((lineIndex_1, lineIndex_2))
        continue

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
        if abs(fixedValue_2 - fixedValue_1) > gap / 2 or minValue_1 > maxValue_2 - gap or minValue_2 > maxValue_1 - gap:
          continue
        conflictLinePairs.append((lineIndex_1, lineIndex_2))
        #drawLines('test/lines_' + str(lineIndex_1) + "_" + str(lineIndex_2) + '.png', width, height, points, [line_1, line_2])
      else:
        if minValue_1 > fixedValue_2 - gap or maxValue_1 < fixedValue_2 + gap or minValue_2 > fixedValue_1 - gap or maxValue_2 < fixedValue_1 + gap:
          continue
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
      for cornerIndex in xrange(4):
        if rectangle_1[cornerIndex] == rectangle_2[cornerIndex]:
          conflictRectanglePairs.append((rectangleIndex_1, rectangleIndex_2))
          conflict = True
          break
        continue
      
      if conflict:
        continue
      
      minX = max(points[rectangle_1[0]][0], points[rectangle_1[2]][0], points[rectangle_2[0]][0], points[rectangle_2[2]][0])
      maxX = min(points[rectangle_1[1]][0], points[rectangle_1[3]][0], points[rectangle_2[1]][0], points[rectangle_2[3]][0])
      if minX > maxX - gap:
        continue
      minY = max(points[rectangle_1[0]][1], points[rectangle_1[1]][1], points[rectangle_2[0]][1], points[rectangle_2[1]][1])
      maxY = min(points[rectangle_1[2]][1], points[rectangle_1[3]][1], points[rectangle_2[2]][1], points[rectangle_2[3]][1])
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
      # for c in xrange(4):
      #   print(rectanglePoints[rectangle[c]])
      #   continue
      # for c in xrange(2):
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


def findConflictLinePairsCross(points_1, lines_1, points_2, lines_2, gap):
  conflictLinePairs = []
  for lineIndex_1, line_1 in enumerate(lines_1):
    point_1 = points_1[line_1[0]]
    point_2 = points_1[line_1[1]]
    if point_2[0] - point_1[0] > point_2[1] - point_1[1]:
      lineDim_1 = 0
    else:
      lineDim_1 = 1
      pass

    fixedValue_1 = int(round((point_1[1 - lineDim_1] + point_2[1 - lineDim_1]) / 2))
    minValue_1 = int(min(point_1[lineDim_1], point_2[lineDim_1]))
    maxValue_1 = int(max(point_1[lineDim_1], point_2[lineDim_1]))

    for lineIndex_2, line_2 in enumerate(lines_2):
      point_1 = points_2[line_2[0]]
      point_2 = points_2[line_2[1]]
      if point_2[0] - point_1[0] > point_2[1] - point_1[1]:
        lineDim_2 = 0
      else:
        lineDim_2 = 1
        pass

      fixedValue_2 = int(round((point_1[1 - lineDim_2] + point_2[1 - lineDim_2]) / 2))
      minValue_2 = int(min(point_1[lineDim_2], point_2[lineDim_2]))
      maxValue_2 = int(max(point_1[lineDim_2], point_2[lineDim_2]))

      if lineDim_1 == lineDim_2:
        continue
        
      if minValue_1 > fixedValue_2 - gap or maxValue_1 < fixedValue_2 + gap or minValue_2 > fixedValue_1 - gap or maxValue_2 < fixedValue_1 + gap:
        continue
      conflictLinePairs.append((lineIndex_1, lineIndex_2))
      continue
    continue
  
  return conflictLinePairs

def maximumSuppression(mask, x, y, heatmapValueThreshold):
  value = mask[y][x]
  mask[y][x] = -1
  deltas = [(-1, 0), (1, 0), (0, -1), (0, 1)]
  for delta in deltas:
    neighborX = x + delta[0]
    neighborY = y + delta[1]
    if neighborX < 0 or neighborY < 0 or neighborX >= width or neighborY >= height:
      continue
    neighborValue = mask[neighborY][neighborX]
    if neighborValue <= value and neighborValue > heatmapValueThreshold:
      maximumSuppression(mask, neighborX, neighborY, heatmapValueThreshold)
      pass
    continue



def extractLocalMaximum(maskImg, numPoints, info, heatmapValueThreshold = 0.5, closePointSuppression = False, lineWidth = 5, maskIndex = -1):
  mask = copy.deepcopy(maskImg)
  points = []
  #pointMask = np.zeros(maskImg.shape)
  pointMask = cv2.cvtColor(floorplan, cv2.COLOR_BGR2GRAY)
  for pointIndex in xrange(numPoints):
    index = np.argmax(mask)
    y, x = np.unravel_index(index, mask.shape)
    maxValue = mask[y, x]
    if maxValue <= heatmapValueThreshold:
      break

    pointMask[max(y - lineWidth, 0):min(y + lineWidth, height - 1), max(x - lineWidth, 0):min(x + lineWidth, width - 1)] = 1

    points.append([float(x), float(y)] + info + [maxValue, ])
    
    maximumSuppression(mask, x, y, heatmapValueThreshold)
    if closePointSuppression:
      mask[max(y - gap, 0):min(y + gap, height - 1), max(x - gap, 0):min(x + gap, width - 1)] = 0
    

    # print(suppressedPoints)
    # meanX = 0
    # meanY = 0
    # for point in suppressedPoints:
    #   meanX += point[0]
    #   meanY += point[1]
    #   continue
    # meanX = float(meanX) / len(suppressedPoints)
    # meanY = float(meanY) / len(suppressedPoints)
    # points.append([meanX, meanY] + info + [maxValue, ])

    
    #cv2.imwrite('test/mask_' + str(pointIndex) + '.png', (mask * 255).astype(np.uint8))
    continue
  if maskIndex >= 0:
    cv2.imwrite('test/mask_' + str(maskIndex) + '.png', (pointMask * 255).astype(np.uint8))

  #points = scalePoints(points, 256)
  return points


def scalePoints(points, sampleDim):
  for point in points:
    point[0] *= width / sampleDim
    point[1] *= height / sampleDim
    continue
  return points


def augmentPoints(points):
  orientationMap = {}
  for pointType, orientationOrientations in enumerate(pointOrientations):
    for orientation, orientations in enumerate(orientationOrientations):
      orientationMap[orientations] = orientation
      continue
    continue

  newPoints = []
  for pointIndex, point in enumerate(points):
    if point[2] not in [2, 3]:
      continue
    orientations = pointOrientations[point[2]][point[3]]
    for i in xrange(len(orientations)):
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
    if point[2] not in [1, 2]:
      continue
    orientations = pointOrientations[point[2]][point[3]]
    for orientation in xrange(4):
      if orientation in orientations:
        continue

      oppositeOrientation = (orientation + 2) % 4
      ranges = copy.deepcopy(orientationRanges[orientation])
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

      for c in xrange(2):
        ranges[c] = min(ranges[c], point[c] - deltas[c])
        ranges[c + 2] = max(ranges[c + 2], point[c] + deltas[c])
        continue

      hasNeighbor = False
      for neighborPointIndex, neighborPoint in enumerate(points):
        if neighborPointIndex == pointIndex:
          continue

        neighborOrientations = pointOrientations[neighborPoint[2]][neighborPoint[3]]
        if oppositeOrientation not in neighborOrientations:
          continue
            
        inRange = True
        for c in xrange(2):
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



wallPoints = []
iconPoints = []
doorPoints = []



if withoutQP:
  numWallPoints = 30
  numDoorPoints = 30
  numIconPoints = 30
  heatmapValueThresholdWall = 0.4
  heatmapValueThresholdDoor = 0.4
  heatmapValueThresholdIcon = 0.4
else:
  numWallPoints = 100
  numDoorPoints = 100
  numIconPoints = 100
  heatmapValueThresholdWall = 0.4
  heatmapValueThresholdDoor = 0.4
  heatmapValueThresholdIcon = 0.4
  pass


heatmaps = np.zeros((13, height, width))
for junctionType in xrange(13):
  heatmap = cv2.imread('test/heatmaps/junction_heatmap_' + str(junctionType + 1) + '.png', 0)
  #heatmap = cv2.blur(heatmap, (5, 5))
  heatmap = heatmap.astype(np.float32) / 255
  heatmaps[junctionType] = heatmap
  continue
  
wallPoints = []
for junctionType in xrange(13):
  #cv2.imwrite('test/heatmap_' + str(junctionType) + '.png', (heatmaps[junctionType] * 255).astype(np.uint8))
  points = extractLocalMaximum(heatmaps[junctionType], numWallPoints, [junctionType / 4, junctionType % 4], heatmapValueThresholdWall)
  wallPoints += points
  continue

augmentedPointOffset = len(wallPoints)
if not withoutQP:
  wallPoints = augmentPoints(wallPoints)
#print(wallPoints)



wallLines, wallPointOrientationLinesMap, wallPointNeighbors = calcPointInfo(wallPoints, gap)
#print('original number of walls: ' + str(len(wallLines)))
if len(wallLines) > 150 and False:
  wallPoints = []
  for junctionType in xrange(13):
    points = extractLocalMaximum(heatmaps[junctionType], numWallPoints, [junctionType / 4, junctionType % 4], heatmapValueThresholdWall)
    wallPoints += points
    continue
  wallLines, wallPointOrientationLinesMap, wallPointNeighbors = calcPointInfo(wallPoints, gap)

wallMask = drawLineMask(wallPoints, wallLines)


for orientation in xrange(4):
  heatmap = cv2.imread('test/heatmaps/door_heatmap_' + str(orientation + 1) + '.png', 0)
  #heatmap = cv2.blur(heatmap, (5, 5))
  heatmap = heatmap.astype(np.float32) / 255

  heatmap *= wallMask
  points = extractLocalMaximum(heatmap, numDoorPoints, [0, orientation], heatmapValueThresholdDoor)
  doorPoints += points
  continue

for orientation in xrange(4):
  heatmap = cv2.imread('test/heatmaps/icon_heatmap_' + str(orientation + 1) + '.png', 0)
  #heatmap = cv2.blur(heatmap, (5, 5))
  heatmap = heatmap.astype(np.float32) / 255

  points = extractLocalMaximum(heatmap, numIconPoints, [1, orientation], heatmapValueThresholdIcon, True, 5, orientation)
  iconPoints += points
  continue

#doorPoints = []
#iconPoints = []


labelVotesMap = np.zeros((numLabels, height, width))
labelMap = np.zeros((numLabels, height, width))
for segmentIndex in xrange(numLabels):
  segmentation_img = cv2.imread('test/segmentation/segment_' + str(segmentIndex + 1) + '.png', 0)
  #_, segmentation_img = cv2.threshold(segmentation_img, 127, 255, cv2.THRESH_BINARY)
  #kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
  #segmentation_img = cv2.morphologyEx(segmentation_img, cv2.MORPH_CLOSE, kernel)
  
  segmentation_img = segmentation_img.astype(np.float32) / 255
  #segmentation_img = (segmentation_img > 0.5).astype(np.float)
  labelVotesMap[segmentIndex] = segmentation_img
  labelMap[segmentIndex] = segmentation_img
  continue

for y in xrange(height):
  for x in xrange(width):
    if y == 0 and x > 0:
      labelVotesMap[:, y, x] += labelVotesMap[:, y, x - 1]
    elif x == 0 and y > 0:
      labelVotesMap[:, y, x] += labelVotesMap[:, y - 1, x]
    elif x > 0 and y > 0:
      labelVotesMap[:, y, x] += labelVotesMap[:, y - 1, x] + labelVotesMap[:, y, x - 1] - labelVotesMap[:, y - 1, x - 1]
      pass
    continue
  continue



doorLines, doorPointOrientationLinesMap, doorPointNeighbors = calcPointInfo(doorPoints, gap, True)
icons = findIcons(iconPoints, gap, False)
#icons = [icons[0]]
#iconLines, iconPointOrientationLinesMap, iconPointNeighbors = calcPointInfo(iconPoints, gap, True)

conflictWallLinePairs = findConflictLinePairs(wallPoints, wallLines, gap)
conflictDoorLinePairs = findConflictLinePairs(doorPoints, doorLines, gap)
conflictIconPairs = findConflictRectanglePairs(iconPoints, icons, gap)


if withoutQP:

  # wallEvidences = []
  # for lineIndex, line in enumerate(wallLines):
  #   point = wallPoints[line[0]]
  #   neighborPoint = wallPoints[line[1]]
  #   lineDim = calcLineDim(wallPoints, line)
  #   fixedValue = int(round((neighborPoint[1 - lineDim] + point[1 - lineDim]) / 2))
  #   wallEvidence = 0
  #   for delta in xrange(int(abs(neighborPoint[lineDim] - point[lineDim]) + 1)):
  #     intermediatePoint = [0, 0]
  #     intermediatePoint[lineDim] = int(min(neighborPoint[lineDim], point[lineDim]) + delta)
  #     intermediatePoint[1 - lineDim] = fixedValue
  #     for typeIndex in xrange(numWallTypes):
  #       wallEvidenceSum += labelMap[wallOffset + typeIndex][min(max(intermediatePoint[1], 0), height - 1)][min(max(intermediatePoint[0], 0), width - 1)]
  #       continue
  #     continue
  #   wallEvidences.append(wallEvidenceSum)
  #   continue

  # invalidWalls = {}
  # for pointIndex, orientationLinesMap in enumerate(wallPointOrientationLinesMap):
  #   for orientation, lines in orientationLinesMap.iteritems():
  #     maxEvidence = 0
  #     maxEvidenceLineIndex = -1
  #     for lineIndex in lines:
  #       if wallEvidences[lineIndex] > maxEvidence:
  #         maxEvidence = wallEvidences[lineIndex]
  #         maxEvidenceLineIndex = lineIndex
  #         pass
  #       continue
  #     for lineIndex in lines:
  #       if lineIndex != maxEvidenceLineIndex:
  #         invalidWalls[lineIndex] = True
  #     continue
  #   continue
    # numValidOrientations = 0
    # for orientation, lines in orientationLinesMap.iteritems():
    #   for lineIndex in lines:
    #     if lineIndex not in invalidWalls:
    #       numValidOrientation += 1
    #       break
    #     continue
    #   continue
  

  filteredWallPoints = []
  validPointMask = {}
  for pointIndex, orientationLinesMap in enumerate(wallPointOrientationLinesMap):
    if len(orientationLinesMap) == wallPoints[pointIndex][2] + 1:
      filteredWallPoints.append(wallPoints[pointIndex])
      validPointMask[pointIndex] = True
      pass
    continue
  
  filteredWallLines= []
  for wallLine in wallLines:
    if wallLine[0] in validPointMask and wallLine[1] in validPointMask:
      filteredWallLines.append(wallLine)
      pass
    continue
  
  #adjustPoints(wallPoints, filteredWallLines)
  writePoints(filteredWallPoints, [])

  doorTypes = []
  for lineIndex, line in enumerate(doorLines):
    point = doorPoints[line[0]]
    neighborPoint = doorPoints[line[1]]
    lineDim = calcLineDim(doorPoints, line)
    fixedValue = int(round((neighborPoint[1 - lineDim] + point[1 - lineDim]) / 2))
    doorEvidenceSums = [0 for typeIndex in xrange(numDoorTypes)]
    for delta in xrange(int(abs(neighborPoint[lineDim] - point[lineDim]) + 1)):
      intermediatePoint = [0, 0]
      intermediatePoint[lineDim] = int(min(neighborPoint[lineDim], point[lineDim]) + delta)
      intermediatePoint[1 - lineDim] = fixedValue
      for typeIndex in xrange(numDoorTypes):
        doorEvidenceSums[typeIndex] += labelMap[doorOffset + typeIndex][min(max(intermediatePoint[1], 0), height - 1)][min(max(intermediatePoint[0], 0), width - 1)]
        continue
      continue
    doorTypes.append((lineIndex, np.argmax(doorEvidenceSums), np.max(doorEvidenceSums)))
    continue


  doorTypesOri = copy.deepcopy(doorTypes)
  doorTypes.sort(key=lambda doorType: doorType[2], reverse=True)
  

  invalidDoors = {}
  doorConflictMap = {}
  for conflictPair in conflictDoorLinePairs:
    if conflictPair[0] not in doorConflictMap:
      doorConflictMap[conflictPair[0]] = []
      pass
    doorConflictMap[conflictPair[0]].append(conflictPair[1])
    
    if conflictPair[1] not in doorConflictMap:
      doorConflictMap[conflictPair[1]] = []
      pass
    doorConflictMap[conflictPair[1]].append(conflictPair[0])
    continue


  for index, doorType in enumerate(doorTypes):
    break
    doorIndex = doorType[0]
    if doorIndex in invalidDoors:
      continue
    if doorIndex not in doorConflictMap:
      continue
    for otherIndex, otherDoorType in enumerate(doorTypes):
      if otherIndex <= index:
        continue
      otherDoorIndex = otherDoorType[0]
      if otherDoorIndex in doorConflictMap[doorIndex]:
        invalidDoors[otherDoorIndex] = True
        pass
      continue
    continue

  filteredDoorLines = []
  filteredDoorTypes = []
  for doorIndex, door in enumerate(doorLines):
    if doorIndex not in invalidDoors:
      filteredDoorLines.append(door)
      filteredDoorTypes.append(doorTypesOri[doorIndex][1])
      pass
    continue

  filteredDoorWallMap = findLineMapSingle(doorPoints, filteredDoorLines, wallPoints, filteredWallLines, gap / 2)
  adjustDoorPoints(doorPoints, filteredDoorLines, wallPoints, filteredWallLines, filteredDoorWallMap)
  writeDoors(doorPoints, filteredDoorLines, filteredDoorTypes)


  iconTypes = []
  for iconIndex, icon in enumerate(icons):
    iconEvidenceSums = []
    point_1 = iconPoints[icon[0]]
    point_2 = iconPoints[icon[1]]
    point_3 = iconPoints[icon[2]]
    point_4 = iconPoints[icon[3]]

    x_1 = int((point_1[0] + point_3[0]) / 2)
    x_2 = int((point_2[0] + point_4[0]) / 2)
    y_1 = int((point_1[1] + point_2[1]) / 2)
    y_2 = int((point_3[1] + point_4[1]) / 2)
    
    iconArea = (x_2 - x_1) * (y_2 - y_1)
    iconEvidenceSums = labelVotesMap[iconOffset:iconOffset + numIconTypes, y_2, x_2] + labelVotesMap[iconOffset:iconOffset + numIconTypes, y_1, x_1] - labelVotesMap[iconOffset:iconOffset + numIconTypes, y_2, x_1] - labelVotesMap[iconOffset:iconOffset + numIconTypes, y_1, x_2]
    iconTypes.append((iconIndex, np.argmax(iconEvidenceSums), np.max(iconEvidenceSums) / iconArea))
    continue

  iconTypesOri = copy.deepcopy(iconTypes)
  iconTypes.sort(key=lambda iconType: iconType[2], reverse=True)

  invalidIcons = {}
  iconConflictMap = {}
  for conflictPair in conflictIconPairs:
    if conflictPair[0] not in iconConflictMap:
      iconConflictMap[conflictPair[0]] = []
      pass
    iconConflictMap[conflictPair[0]].append(conflictPair[1])
    
    if conflictPair[1] not in iconConflictMap:
      iconConflictMap[conflictPair[1]] = []
      pass
    iconConflictMap[conflictPair[1]].append(conflictPair[0])
    continue


  for index, iconType in enumerate(iconTypes):
    break
    iconIndex = iconType[0]
    if iconIndex in invalidIcons:
      continue
    if iconIndex not in iconConflictMap:
      continue
    for otherIndex, otherIconType in enumerate(iconTypes):
      if otherIndex <= index:
        continue
      otherIconIndex = otherIconType[0]
      if otherIconIndex in iconConflictMap[iconIndex]:
        invalidIcons[otherIconIndex] = True
        pass
      continue
    continue
  

  
  filteredIcons = []
  filteredIconTypes = []
  for iconIndex, icon in enumerate(icons):
    if iconIndex not in invalidIcons:
      filteredIcons.append(icon)
      filteredIconTypes.append(iconTypesOri[iconIndex][1])
      pass
    continue



  #conflictIconPairs = findConflictRectanglePairs(iconPoints, filteredIcons, gap)
  writeIcons(iconPoints, filteredIcons, filteredIconTypes)

  drawLines('test/lines.png', width, height, wallPoints, wallLines)
  drawLines('test/doors.png', width, height, doorPoints, doorLines)
  drawRectangles('test/icons.png', width, height, iconPoints, icons, {}, 2, floorplan)
  print('number of walls: ' + str(len(wallLines)))
  print('number of doors: ' + str(len(doorLines)))
  print('number of icons: ' + str(len(icons)))
  exit(1)
    

if False:
  #lines = [51]
  #filteredWallLines = []

  for lineIndex, line in enumerate(doorLines):
    #print(wallLines[lineIndex])
    #filteredWallLines.append(wallLines[lineIndex])
    #continue
    drawLines('test/doors/line_' + str(lineIndex) + '.png', width, height, doorPoints, [line])
    continue

  for lineIndex, line in enumerate(wallLines):
    #print(wallLines[lineIndex])
    #filteredWallLines.append(wallLines[lineIndex])
    #continue
    drawLines('test/lines/line_' + str(lineIndex) + '.png', width, height, wallPoints, [line], [])
    continue
  exit(1)
  pass


wallLineNeighbors = findLineNeighbors(wallPoints, wallLines, gap)
#iconWallLineNeighbors = findLineNeighborsCross(iconPoints, iconLines, wallPoints, wallLines, wallLineNeighbors, gap)
iconWallLineNeighbors = findRectangleLineNeighbors(iconPoints, icons, wallPoints, wallLines, wallLineNeighbors, gap, gap * 2)

doorWallLineMap = findLineMap(doorPoints, doorLines, wallPoints, wallLines, gap / 2)


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
conflictDoorLinePairs = findConflictLinePairs(doorPoints, doorLines, gap)

conflictIconWallPairs = findConflictRectangleLinePairs(iconPoints, icons, wallPoints, wallLines, gap)

exteriorLines = {}
for lineIndex, neighbors in enumerate(wallLineNeighbors):
  if len(neighbors[0]) == 0 and len(neighbors[1]) > 0:
    exteriorLines[lineIndex] = 0
  elif len(neighbors[0]) > 0 and len(neighbors[1]) == 0:
    exteriorLines[lineIndex] = 1
    pass
  continue



if True:
  drawLines('test/lines.png', width, height, wallPoints, wallLines, [], None, 2)
  drawLines('test/doors.png', width, height, doorPoints, doorLines, [], None, 2)
  drawRectangles('test/icons.png', width, height, iconPoints, icons, {}, 2)
  print('number of walls: ' + str(len(wallLines)))
  print('number of doors: ' + str(len(doorLines)))
  print('number of icons: ' + str(len(icons)))
  #exit(1)
  pass


if False:
  for i in xrange(2):
    print(wallLineNeighbors[43][i].keys())
    print(wallLineNeighbors[81][i].keys())
    print(wallLineNeighbors[84][i].keys())
  exit(1)
  filteredWallLines = []
  for lineIndex, neighbors in enumerate(wallLineNeighbors):
    if len(neighbors[0]) == 0 and len(neighbors[1]) > 0:
      print(lineIndex)
      filteredWallLines.append(wallLines[lineIndex])
      pass
    continue
  drawLines('test/exterior_1.png', width, height, wallPoints, filteredWallLines)

  filteredWallLines = []
  for lineIndex, neighbors in enumerate(wallLineNeighbors):
    if len(neighbors[0]) > 0 and len(neighbors[1]) == 0:
      print(lineIndex)
      filteredWallLines.append(wallLines[lineIndex])
      pass
    continue
  drawLines('test/exterior_2.png', width, height, wallPoints, filteredWallLines)
  exit(1)
  pass



try:
  model = Model("JunctionFilter")

  #add variables
  w_p = [model.addVar(vtype = GRB.BINARY, name="point_" + str(pointIndex)) for pointIndex in xrange(len(wallPoints))]
  w_l = [model.addVar(vtype = GRB.BINARY, name="line_" + str(lineIndex)) for lineIndex in xrange(len(wallLines))]

  d_l = [model.addVar(vtype = GRB.BINARY, name="door_line_" + str(lineIndex)) for lineIndex in xrange(len(doorLines))]  

  i_r = [model.addVar(vtype = GRB.BINARY, name="icon_rectangle_" + str(lineIndex)) for lineIndex in xrange(len(icons))]

  i_types = []
  for iconIndex in xrange(len(icons)):
    i_types.append([model.addVar(vtype = GRB.BINARY, name="icon_type_" + str(iconIndex) + "_" + str(typeIndex)) for typeIndex in xrange(numIconTypes)])
    continue
  
  l_dir_labels = []
  for lineIndex in xrange(len(wallLines)):
    dir_labels = []
    for direction in xrange(2):
      labels = []
      for label in xrange(numRoomTypes):
        labels.append(model.addVar(vtype = GRB.BINARY, name="line_" + str(lineIndex) + "_" + str(direction) + "_" + str(label)))
      dir_labels.append(labels)
    l_dir_labels.append(dir_labels)



  #model.update()
  obj = QuadExpr()


  #label sum constraints
  for lineIndex in xrange(len(wallLines)):
    for direction in xrange(2):
      labelSum = LinExpr()
      for label in xrange(numRoomTypes):
        labelSum += l_dir_labels[lineIndex][direction][label]
        continue
      model.addConstr(labelSum == w_l[lineIndex], 'label sum')
      continue
    continue


  # #opposite label constraints
  # singleRooms = {}
  # for label in xrange(numRoomTypes):
  #   singleRooms[label] = True
  #   continue
  # singleRooms[1] = False
  # singleRooms[2] = False
  # singleRooms[3] = False
  # singleRooms[7] = False
  # singleRooms[9] = False
  
  # for label in xrange(numRoomTypes):
  #   if not singleRooms[label]:
  #     continue
  #   for lineIndex in xrange(len(wallLines)):
  #     model.addConstr(l_dir_labels[lineIndex][0][label] + l_dir_labels[lineIndex][1][label] <= 1, 'single room')
  #     continue

    

  #loop constraints
  closeRooms = {}
  for label in xrange(numRoomTypes):
    closeRooms[label] = True
  closeRooms[1] = False
  closeRooms[2] = False
  #closeRooms[3] = False
  closeRooms[8] = False
  closeRooms[9] = False

  for label in xrange(numRoomTypes):
    if not closeRooms[label]:
      continue
    for pointIndex, orientationLinesMap in enumerate(wallPointOrientationLinesMap):
      for orientation, lines in orientationLinesMap.iteritems():
        direction = int(orientation in [1, 2])
        lineSum = LinExpr()
        for lineIndex in lines:
          lineSum += l_dir_labels[lineIndex][direction][label]
          continue
        for nextOrientation in xrange(orientation + 1, 8):
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

         
 
  #exteriorConstraints
  exteriorLineSum = LinExpr()
  for lineIndex in xrange(len(wallLines)):
    if lineIndex not in exteriorLines:
      continue
    #direction = exteriorLines[lineIndex]
    label = 0
    model.addConstr(l_dir_labels[lineIndex][0][label] + l_dir_labels[lineIndex][1][label] == w_l[lineIndex], 'exterior wall')
    exteriorLineSum += w_l[lineIndex]
    continue
  model.addConstr(exteriorLineSum >= 1, 'exterior wall sum')

  
  #line label constraints and objectives
  for lineIndex, directionNeighbors in enumerate(wallLineNeighbors):
    for direction, neighbors in enumerate(directionNeighbors):
      labelVotesSum = np.zeros(numRoomTypes)
      for neighbor, labelVotes in neighbors.iteritems():
        labelVotesSum[1:numRoomTypes] += labelVotes[:numRoomTypes - 1]
        continue

      votesSum = labelVotesSum.sum()
      if votesSum == 0:
        continue
      labelVotesSum /= votesSum
      
 
      for label in xrange(numRoomTypes):
        obj += l_dir_labels[lineIndex][direction][label] * (0.0 - labelVotesSum[label]) * labelWeight
        continue
      continue
    continue  



  #data terms
  #print(augmentedPointOffset)
  #print(len(wallPoints))
  
  for pointIndex in xrange(len(wallPoints)):
    if pointIndex < augmentedPointOffset:
      obj += (1 - w_p[pointIndex]) * junctionWeight #* len(wallPointOrientationLinesMap[pointIndex])
    else:
      obj += w_p[pointIndex] * augmentedJunctionWeight #* len(wallPointOrientationLinesMap[pointIndex])
    continue    

  #door endpoint constraints
  pointDoorsMap = {}
  for doorIndex, line in enumerate(doorLines):
    for endpointIndex in xrange(2):
      pointIndex = line[endpointIndex]
      if pointIndex not in pointDoorsMap:
        pointDoorsMap[pointIndex] = []
        pass
      pointDoorsMap[pointIndex].append(doorIndex)
      continue
    continue


  for pointIndex, doorIndices in pointDoorsMap.iteritems():
    doorSum = LinExpr(0)
    for doorIndex in doorIndices:
      doorSum += d_l[doorIndex]
      continue
    obj += (1 - doorSum) * junctionWeight
    #model.addConstr(doorSum <= 1, "door_line_sum_" + str(pointIndex) + "_" + str(orientation))
    continue


  
  #icon corner constraints
  pointIconsMap = {}
  for iconIndex, icon in enumerate(icons):
    for cornerIndex in xrange(4):
      pointIndex = icon[cornerIndex]
      if pointIndex not in pointIconsMap:
        pointIconsMap[pointIndex] = []
        pass
      pointIconsMap[pointIndex].append(iconIndex)
      continue
    continue
  #print(pointIconsMap)

  for pointIndex, iconIndices in pointIconsMap.iteritems():
    iconSum = LinExpr(0)
    for iconIndex in iconIndices:
      iconSum += i_r[iconIndex]
      continue
    obj += (1 - iconSum) * junctionWeight
    continue



  gapWeight = 1
  pixelEvidenceWeight = 1
  
  for lineIndex, line in enumerate(wallLines):
    point = wallPoints[line[0]]
    neighborPoint = wallPoints[line[1]]
    lineDim = calcLineDim(wallPoints, line)
    wallCost = (abs(neighborPoint[1 - lineDim] - point[1 - lineDim]) / gap - 0.5) * gapWeight
    #obj += w_l[lineIndex] * wallCost * wallWeight
    
    fixedValue = int(round((neighborPoint[1 - lineDim] + point[1 - lineDim]) / 2))
    wallEvidenceSums = [0, 0]
    for delta in xrange(int(abs(neighborPoint[lineDim] - point[lineDim]) + 1)):
      intermediatePoint = [0, 0]
      intermediatePoint[lineDim] = int(min(neighborPoint[lineDim], point[lineDim]) + delta)
      intermediatePoint[1 - lineDim] = fixedValue
      for typeIndex in xrange(numWallTypes):
        wallEvidenceSums[typeIndex] += labelMap[wallOffset + typeIndex][min(max(intermediatePoint[1], 0), height - 1)][min(max(intermediatePoint[0], 0), width - 1)]
        continue
      continue
    wallEvidenceSum = wallEvidenceSums[0] + wallEvidenceSums[1]

    wallEvidenceSum /= maxDim
    obj += -wallEvidenceSum * w_l[lineIndex] * wallWeight


  
  for lineIndex, line in enumerate(doorLines):
    #obj += -d_l[lineIndex] * doorWeight * abs(neighborPoint[lineDim] - point[lineDim] + 1) / maxDim
    #continue
  
    point = doorPoints[line[0]]
    neighborPoint = doorPoints[line[1]]
    lineDim = calcLineDim(doorPoints, line)
    #doorCost = (abs(neighborPoint[1 - lineDim] - point[1 - lineDim]) / gap - 1) * gapWeight
    #obj += d_l[lineIndex] * doorCost * doorWeight
    
    fixedValue = int(round((neighborPoint[1 - lineDim] + point[1 - lineDim]) / 2))
    #doorEvidenceSums = [0 for typeIndex in xrange(numDoorTypes)]
    doorEvidenceSum = 0

    for delta in xrange(int(abs(neighborPoint[lineDim] - point[lineDim]) + 1)):
      intermediatePoint = [0, 0]
      intermediatePoint[lineDim] = int(min(neighborPoint[lineDim], point[lineDim]) + delta)
      intermediatePoint[1 - lineDim] = fixedValue

      doorEvidenceSum += np.sum(labelMap[doorOffset:doorOffset + numDoorTypes, min(max(intermediatePoint[1], 0), height - 1), min(max(intermediatePoint[0], 0), width - 1)])
      #doorEvidenceSum += float(np.sum(labelMap[doorOffset:doorOffset + numDoorTypes, min(max(intermediatePoint[1], 0), height - 1), min(max(intermediatePoint[0], 0), width - 1)]) > 0.5) * 2 - 1
      continue
    
    doorEvidenceSum /= maxDim
    obj += -doorEvidenceSum * d_l[lineIndex] * doorWeight
    
  
  for iconIndex, icon in enumerate(icons):
    point_1 = iconPoints[icon[0]]
    point_2 = iconPoints[icon[1]]
    point_3 = iconPoints[icon[2]]
    point_4 = iconPoints[icon[3]]

    x_1 = int((point_1[0] + point_3[0]) / 2)
    x_2 = int((point_2[0] + point_4[0]) / 2)
    y_1 = int((point_1[1] + point_2[1]) / 2)
    y_2 = int((point_3[1] + point_4[1]) / 2)

    iconArea = (x_2 - x_1) * (y_2 - y_1)
    iconEvidenceSums = labelVotesMap[iconOffset:iconOffset + numIconTypes, y_2, x_2] + labelVotesMap[iconOffset:iconOffset + numIconTypes, y_1, x_1] - labelVotesMap[iconOffset:iconOffset + numIconTypes, y_2, x_1] - labelVotesMap[iconOffset:iconOffset + numIconTypes, y_1, x_2]


    for typeIndex in xrange(numIconTypes):
      iconRatio = iconEvidenceSums[typeIndex] / iconArea
      if iconRatio < 0.5 and False:
        model.addConstr(i_types[iconIndex][typeIndex] == 0)
      else:
        obj += i_types[iconIndex][typeIndex] * (0 - iconEvidenceSums[typeIndex] / iconArea) * iconTypeWeight
      continue
    continue
  
  
  for iconIndex in xrange(len(icons)):
    typeSum = LinExpr(0)
    for typeIndex in xrange(numIconTypes):
      typeSum += i_types[iconIndex][typeIndex]
      continue
    model.addConstr(typeSum == i_r[iconIndex])
    continue
    

 
  # #icon wall constraints
  # iconWallTypesMap = {}
  # iconWallTypesMap[0] = (4, )
  # iconWallTypesMap[1] = (1, 2, 3)
  # iconWallTypesMap[2] = (4, 5)
  # iconWallTypesMap[3] = (1, 2, 3, 8)
  # iconWallTypesMap[4] = (4, 5, 8, 9)
  # iconWallTypesMap[5] = (1, 2, 3, 4, 5, 6, 8, 9)
  # iconWallTypesMap[6] = (1, 2, 3, 4, 5, 6, 8, 9)
  # #iconWallTypesMap[7] = (1, 2, 6, 10)
  # iconWallTypesMap[9] = (1, 2, 3, 8)
  
  # #print(iconWallLineNeighbors[8])
  # for iconIndex, lines in enumerate(iconWallLineNeighbors):
  #   for typeIndex in xrange(numIconTypes):
  #     if typeIndex not in iconWallTypesMap:
  #       continue
  #     wallSum = LinExpr()
  #     for wallType in iconWallTypesMap[typeIndex]:
  #       for lineIndex, direction in lines.iteritems():
  #         wallSum += l_dir_labels[lineIndex][direction][wallType]
  #         continue
  #       continue
  #     model.addConstr(i_types[iconIndex][typeIndex] <= wallSum)
  #     continue
  #   continue
  

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


  #close points constraints
  for pointIndex, point in enumerate(wallPoints):
    for neighborPointIndex, neighborPoint in enumerate(wallPoints):
      if neighborPointIndex <= pointIndex:
        continue
      distance = pow(pow(point[0] - neighborPoint[0], 2) + pow(point[1] - neighborPoint[1], 2), 0.5)
      if distance < gap and neighborPointIndex not in wallPointNeighbors[pointIndex]:
        #obj += p[pointIndex] * p[neighborPointIndex] * closePointWeight
        model.addConstr(w_p[pointIndex] + w_p[neighborPointIndex] <= 1, 'close point')
        pass
      continue
    continue
  

  #conflict pair constraints
  for conflictLinePair in conflictWallLinePairs:
    model.addConstr(w_l[conflictLinePair[0]] + w_l[conflictLinePair[1]] <= 1, 'conflict wall line pair')

  for conflictLinePair in conflictDoorLinePairs:
    model.addConstr(d_l[conflictLinePair[0]] + d_l[conflictLinePair[1]] <= 1, 'conflict door line pair')

  for conflictIconPair in conflictIconPairs:
    model.addConstr(i_r[conflictIconPair[0]] + i_r[conflictIconPair[1]] <= 1, 'conflict icon pair')

  for conflictLinePair in conflictIconWallPairs:
    model.addConstr(i_r[conflictLinePair[0]] + w_l[conflictLinePair[1]] <= 1, 'conflict icon wall pair')


  #door wall line map constraints
  for doorIndex, lines in enumerate(doorWallLineMap):
    if len(lines) == 0:
      model.addConstr(d_l[doorIndex] == 0, 'door not on walls')
      continue
    lineSum = LinExpr(0)
    for lineIndex in lines:
      lineSum += w_l[lineIndex]
      continue
    model.addConstr(d_l[doorIndex] <= lineSum, 'd <= line sum')    
    continue

  


  if False:
    #print(conflictWallLinePairs)
    model.addConstr(w_l[1] == 1)
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

  model.setObjective(obj, GRB.MINIMIZE)
  #model.update()
  model.setParam('TimeLimit', 60)
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
    wallPointLabels = [[-1, -1, -1, -1] for pointIndex in xrange(len(wallPoints))]

    for lineIndex, lineVar in enumerate(w_l):
      if lineVar.x < 0.5:
        continue
      filteredWallLines.append(wallLines[lineIndex])

      filteredWallTypes.append(0)
      
      labels = [11, 11]
      for direction in xrange(2):
        for label in xrange(numRoomTypes):
          if l_dir_labels[lineIndex][direction][label].x > 0.5:
            labels[direction] = label
            break
          continue
        continue
      
      filteredWallLabels.append(labels)
      print('wall', lineIndex, labels)
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
    
    adjustPoints(wallPoints, filteredWallLines)
    drawLines('test/result_line.png', width, height, wallPoints, filteredWallLines, filteredWallLabels)
    resultImage = drawLines('', width, height, wallPoints, filteredWallLines, filteredWallLabels, None, 10)

    filteredDoorLines = []
    filteredDoorTypes = []
    for lineIndex, lineVar in enumerate(d_l):
      if lineVar.x < 0.5:
        continue
      print(('door', lineIndex))
      filteredDoorLines.append(doorLines[lineIndex])
      
      filteredDoorTypes.append(0)
      continue

    filteredDoorWallMap = findLineMapSingle(doorPoints, filteredDoorLines, wallPoints, filteredWallLines, gap / 2)
    adjustDoorPoints(doorPoints, filteredDoorLines, wallPoints, filteredWallLines, filteredDoorWallMap)
    drawLines('test/result_door.png', width, height, doorPoints, filteredDoorLines)
    
    filteredIcons = []
    filteredIconTypes = []
    for iconIndex, iconVar in enumerate(i_r):
      if iconVar.x < 0.5:
        continue


      filteredIcons.append(icons[iconIndex])
      iconType = -1
      for typeIndex in xrange(numIconTypes):
        if i_types[iconIndex][typeIndex].x > 0.5:
          iconType = typeIndex
          break
        continue

      print(('icon', iconIndex, iconType))
      
      filteredIconTypes.append(iconType)
      continue

    #adjustPoints(iconPoints, filteredIconLines)
    #drawLines('test/lines_results_icon.png', width, height, iconPoints, filteredIconLines)
    drawRectangles('test/result_icon.png', width, height, iconPoints, filteredIcons, filteredIconTypes)    


    #resultImage = drawLines('', width, height, doorPoints, filteredDoorLines, [], resultImage, 4, 255)
    #resultImage = drawRectangles('', width, height, iconPoints, filteredIcons, filteredIconTypes, 2, resultImage)
    cv2.imwrite('test/result.png', resultImage)


    filteredWallPoints = []
    filteredWallPointLabels = []
    orientationMap = {}
    for pointType, orientationOrientations in enumerate(pointOrientations):
      for orientation, orientations in enumerate(orientationOrientations):
        orientationMap[orientations] = orientation
        
    for pointIndex, point in enumerate(wallPoints):
      #if w_p[pointIndex].x < 0.5:
      #continue

      orientations = []
      for orientation, lines in wallPointOrientationLinesMap[pointIndex].iteritems():
        orientationLine = -1
        for lineIndex in lines:
          if w_l[lineIndex].x > 0.5:
            orientations.append(orientation)
            break
          continue
        continue

      if len(orientations) == 0:
        continue
      
      if len(orientations) < len(wallPointOrientationLinesMap[pointIndex]):
        print(pointIndex)
        print(wallPoints[pointIndex])
        wallPoints[pointIndex][2] = len(orientations) - 1
        orientations = tuple(orientations)
        if orientations not in orientationMap:
          continue
        wallPoints[pointIndex][3] = orientationMap[orientations]
        print(wallPoints[pointIndex])


      filteredWallPoints.append(wallPoints[pointIndex])
      filteredWallPointLabels.append(wallPointLabels[pointIndex])


    writePoints(filteredWallPoints, filteredWallPointLabels)


    with open('test/floorplan.txt', 'w') as result_file:
      result_file.write(str(width) + '\t' + str(height) + '\n')
      result_file.write(str(len(filteredWallLines)) + '\n')
      for wallIndex, wall in enumerate(filteredWallLines):
        point_1 = wallPoints[wall[0]]
        point_2 = wallPoints[wall[1]]

        result_file.write(str(torch.round(point_1[0])) + '\t' + str(torch.round(point_1[1])) + '\t')
        result_file.write(str(torch.round(point_2[0])) + '\t' + str(torch.round(point_2[1])) + '\t')
        result_file.write(str(filteredWallLabels[wallIndex][0]) + '\t' + str(filteredWallLabels[wallIndex][1]) + '\n')

      for doorIndex, door in enumerate(filteredDoorLines):
        point_1 = doorPoints[door[0]]
        point_2 = doorPoints[door[1]]
        
        result_file.write(str(torch.round(point_1[0])) + '\t' + str(torch.round(point_1[1])) + '\t')
        result_file.write(str(torch.round(point_2[0])) + '\t' + str(torch.round(point_2[1])) + '\t')
        result_file.write('door\t')
        result_file.write(str(filteredDoorTypes[doorIndex] + 1) + '\t1\n')

      for iconIndex, icon in enumerate(filteredIcons):
        point_1 = iconPoints[icon[0]]
        point_2 = iconPoints[icon[1]]
        point_3 = iconPoints[icon[2]]
        point_4 = iconPoints[icon[3]]

        x_1 = int(torch.round((point_1[0] + point_3[0]) / 2))
        x_2 = int(torch.round((point_2[0] + point_4[0]) / 2))
        y_1 = int(torch.round((point_1[1] + point_2[1]) / 2))
        y_2 = int(torch.round((point_3[1] + point_4[1]) / 2))

        result_file.write(str(x_1) + '\t' + str(y_1) + '\t')
        result_file.write(str(x_2) + '\t' + str(y_2) + '\t')
        result_file.write(iconNumberNameMap[filteredIconTypes[iconIndex]] + '\t')
        result_file.write(str(iconNumberStyleMap[filteredIconTypes[iconIndex]]) + '\t')
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
  else:
    print('infeasible')
    #model.ComputeIIS()
    #model.write("test/model.ilp")
    
except GurobiError as e:
  print('Error code ' + str(e.errno) + ": " + str(e))

except AttributeError:
  print('Encountered an attribute error')
