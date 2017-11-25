from math import pi, sin, cos
from panda3d.core import *
from direct.showbase.ShowBase import ShowBase
from direct.task import Task
from floorplan import Floorplan
import numpy as np
import random
import copy

class Viewer(ShowBase):
  def __init__(self):

    ShowBase.__init__(self)
    #self.scene = self.loader.loadModel("floorplan_1.txt-floor.obj")
    #self.scene = base.loader.loadModel("floorplan_1.txt-floor.egg")
    #self.scene = base.loader.loadModel("panda.egg")

    #self.scene = base.loader.loadModel("environment")

    base.setBackgroundColor(0, 0, 0)
    self.angle = 0.0
    lens = PerspectiveLens()
    lens.setFov(60)
    lens.setNear(0.01)
    lens.setFar(100000)
    base.cam.node().setLens(lens)
    floorplan = Floorplan('test/floorplan_7')
    #floorplan.setFilename('test/floorplan_2')
    floorplan.read()
    self.scene = floorplan.generateEggModel()
    self.scene.reparentTo(self.render)
    #self.scene.setScale(0.01, 0.01, 0.01)
    #self.scene.setTwoSided(True)
    self.scene.setTwoSided(True)
    #self.scene.setPos(0, 0, 3)
    #texture = loader.loadTexture("floorplan_1.png")
    #self.scene.setTexture(texture)
    #self.scene.setHpr(0, 0, 0)
    
    # angleDegrees = 0
    # angleRadians = angleDegrees * (pi / 180.0)
    # self.camera.setPos(20 * sin(angleRadians), -20 * cos(angleRadians), 3)
    # self.camera.setHpr(angleDegrees, 0, 0)
    #self.camera.lookAt(0, 0, 0)
    
    self.alight = AmbientLight('alight')
    self.alight.setColor(VBase4(0.2, 0.2, 0.2, 1))
    self.alnp = self.render.attachNewNode(self.alight)
    self.render.setLight(self.alnp)

    dlight = DirectionalLight('dlight')
    dlight.setColor(VBase4(1, 1, 1, 1))
    dlnp = self.render.attachNewNode(dlight)
    #dlnp.setHpr(0, -90, 0)
    dlnp.setPos(0.5, 0.5, 3)
    dlnp.lookAt(0.5, 0.5, 2)
    self.render.setLight(dlnp)
    
    for i in xrange(10):
      plight = PointLight('plight')
      plight.setAttenuation((1, 0, 1))
      color = random.randint(10, 15)
      plight.setColor(VBase4(color, color, color, 1))
      plnp = self.render.attachNewNode(plight)
      if i == 0:
        plnp.setPos(0.5, 0.5, 3)
      else:
        plnp.setPos(1 * random.random(), 1 * random.random(), 0.3)
        pass
      self.render.setLight(plnp)



    #base.useTrackball()
    #base.trackball.node().setPos(2.0, 0, 3)
    #base.trackball.node().setHpr(0, 0, 3)
    #base.enableMouse()
    #base.useDrive()
    base.disableMouse()
    self.taskMgr.add(self.spinCameraTask, "SpinCameraTask")
    #self.accept('arrow_up', self.moveForward)
    #self.accept('arrow_up_-repeat', self.moveForward)
    self.topDownCameraPos = [0.5, 0.5, 1.5]
    self.topDownTarget = [0.5, 0.499, 0.5]
    self.topDownH = 0
    self.startCameraPos = floorplan.startCameraPos
    self.startTarget = floorplan.startTarget
    self.startH = 0
    
    self.cameraPos = self.topDownCameraPos
    self.target = self.topDownTarget
    self.H = self.topDownH

    self.accept('space', self.openDoor)
    self.accept('enter', self.startChangingView)

    self.viewMode = 'T'
    self.viewChangingProgress = 1.02

    ceiling = self.scene.find("**/ceiling")
    ceiling.hide()
    
    return

  def moveForward(self):
    self.cameraPos[0] -= 0.1

  def openDoor(self):
    minDistance = 10000
    doors = self.scene.find("**/doors")
    for door in doors.getChildren():
      mins, maxs = door.getTightBounds()

      vec_1 = (mins + maxs) / 2 - Vec3(self.target[0], self.target[1], (mins[2] + maxs[2]) / 2)
      vec_2 = (mins + maxs) / 2 - Vec3(self.cameraPos[0], self.cameraPos[1], (mins[2] + maxs[2]) / 2)
      if (vec_1.dot(vec_2) > 0 and vec_1.length() > vec_2.length()) or np.arccos(abs(vec_1.dot(vec_2)) / (vec_1.length() * vec_2.length())) > np.pi / 4:
        continue

      distance = pow(pow(self.cameraPos[0] - (mins[0] + maxs[0]) / 2, 2) + pow(self.cameraPos[1] - (mins[1] + maxs[1]) / 2, 2) + pow(self.cameraPos[2] - (mins[2] + maxs[2]) / 2, 2), 0.5)
      if distance < minDistance:
        minDistanceDoor = door
        minDistance = distance
        pass
      continue

    if minDistance > 1:
      return
    mins, maxs = minDistanceDoor.getTightBounds()
    if abs(maxs[0] - mins[0]) > abs(maxs[1] - mins[1]):
      minsExpected = Vec3(mins[0] - (maxs[1] - mins[1]), mins[1], mins[2])
      maxsExpected = Vec3(mins[0], mins[1] + (maxs[0] - mins[0]), maxs[2])
    else:
      minsExpected = Vec3(mins[0] - (maxs[1] - mins[1]) + (maxs[0] - mins[0]), mins[1] - (maxs[0] - mins[0]), mins[2])
      maxsExpected = Vec3(mins[0] + (maxs[0] - mins[0]), mins[1] + (maxs[0] - mins[0]) - (maxs[0] - mins[0]), maxs[2])
      pass
    minDistanceDoor.setH(minDistanceDoor, 90)
    mins, maxs = minDistanceDoor.getTightBounds()
    minDistanceDoor.setPos(minDistanceDoor, minsExpected[1] - mins[1], -minsExpected[0] + mins[0], 0)
    #print(scene.findAllMatches('doors'))
    return

  def startChangingView(self):
    self.viewChangingProgress = 0
    self.prevCameraPos = copy.deepcopy(self.cameraPos)
    self.prevTarget = copy.deepcopy(self.target)
    self.prevH = self.camera.getR()
    if self.viewMode == 'T':
      self.newCameraPos = self.startCameraPos
      self.newTarget = self.startTarget
      self.newH = self.startH
      self.viewMode = 'C'
    else:
      self.newCameraPos = self.topDownCameraPos
      self.newTarget = self.topDownTarget
      self.newH = self.topDownH
      self.startCameraPos = copy.deepcopy(self.cameraPos)
      self.startTarget = copy.deepcopy(self.target)
      self.startH = self.camera.getR()
      self.viewMode = 'T'
      pass
    return


  def changeView(self):
    self.cameraPos = []
    self.target = []
    for c in xrange(3):
      self.cameraPos.append(self.prevCameraPos[c] + (self.newCameraPos[c] - self.prevCameraPos[c]) * self.viewChangingProgress)
      self.target.append(self.prevTarget[c] + (self.newTarget[c] - self.prevTarget[c]) * self.viewChangingProgress)
      continue
    self.H = self.prevH + (self.newH - self.prevH) * self.viewChangingProgress

    if self.viewChangingProgress + 0.02 >= 1 and self.viewMode == 'C':
      ceiling = self.scene.find("**/ceiling")
      ceiling.show()
      pass

    if self.viewChangingProgress <= 0.02 and self.viewMode == 'T':
      ceiling = self.scene.find("**/ceiling")
      ceiling.hide()
      pass
    return
  
  def spinCameraTask(self, task):
    #print(task.time)
    #angleDegrees = task.time * 6.0
    movementStep = 0.003
    if self.viewChangingProgress <= 1.01:
      self.changeView()
      self.viewChangingProgress += 0.02
      pass
    
    if base.mouseWatcherNode.is_button_down('w'):
      for c in xrange(2):
        step = movementStep * (self.target[c] - self.cameraPos[c])
        self.cameraPos[c] += step
        self.target[c] += step
        continue
      pass
    if base.mouseWatcherNode.is_button_down('s'):
      for c in xrange(2):
        step = movementStep * (self.target[c] - self.cameraPos[c])
        self.cameraPos[c] -= step
        self.target[c] -= step
        continue
      pass
    if base.mouseWatcherNode.is_button_down('a'):
      step = movementStep * (self.target[0] - self.cameraPos[0])
      self.cameraPos[1] += step
      self.target[1] += step
      step = movementStep * (self.target[1] - self.cameraPos[1])
      self.cameraPos[0] -= step
      self.target[0] -= step
      pass
    if base.mouseWatcherNode.is_button_down('d'):
      step = movementStep * (self.target[0] - self.cameraPos[0])
      self.cameraPos[1] -= step
      self.target[1] -= step
      step = movementStep * (self.target[1] - self.cameraPos[1])
      self.cameraPos[0] += step
      self.target[0] += step
      pass
    
    rotationStep = 0.02
    if base.mouseWatcherNode.is_button_down('arrow_left'):
      angle = np.angle(complex(self.target[0] - self.cameraPos[0], self.target[1] - self.cameraPos[1]))
      angle += rotationStep
      self.target[0] = self.cameraPos[0] + np.cos(angle)
      self.target[1] = self.cameraPos[1] + np.sin(angle)
      pass
    if base.mouseWatcherNode.is_button_down('arrow_right'):
      angle = np.angle(complex(self.target[0] - self.cameraPos[0], self.target[1] - self.cameraPos[1]))
      angle -= rotationStep
      self.target[0] = self.cameraPos[0] + np.cos(angle)
      self.target[1] = self.cameraPos[1] + np.sin(angle)
      pass

    if base.mouseWatcherNode.is_button_down('arrow_up'):
      angle = np.arcsin(self.target[2] - self.cameraPos[2])
      angle += rotationStep
      self.target[2] = self.cameraPos[2] + np.sin(angle)
      pass
    if base.mouseWatcherNode.is_button_down('arrow_down'):
      angle = np.arcsin(self.target[2] - self.cameraPos[2])
      angle -= rotationStep
      self.target[2] = self.cameraPos[2] + np.sin(angle)
      pass

    angleDegrees = self.angle
    angleRadians = angleDegrees * (pi / 180.0)
    #self.camera.setPos(2.0 * sin(angleRadians), -2.0 * cos(angleRadians), 3)
    self.camera.setPos(self.cameraPos[0], self.cameraPos[1], self.cameraPos[2])
    #self.camera.setHpr(angleDegrees, 0, 0)
    #self.camera.lookAt(0, 0, 0)
    self.camera.lookAt(self.target[0], self.target[1], self.target[2])
    self.camera.setR(self.H)
    #if base.mouseWatcherNode.hasMouse()
    return Task.cont
  
app = Viewer()
app.run()
