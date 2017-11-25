from panda3d.core import *
from direct.showbase.ShowBase import ShowBase
import cv2
from floorplan import Floorplan
import numpy as np
import random
import math

class Renderer(ShowBase):
  def __init__(self):
    #self.scene = self.loader.loadModel("floorplan_1.txt-floor.obj")
    loadPrcFileData("", "window-type offscreen")
    loadPrcFileData("", "win-size 128 128")
    ShowBase.__init__(self)
    
    self.scene = NodePath("Scene")
    self.scene.reparentTo(self.render)
    self.scene.setScale(1, 1, 1)
    self.scene.setTwoSided(True)
    self.scene.setPos(0, 0, 0)
    self.scene.setHpr(0, 0, 0)
    self.near_plane = 0.1
    self.far_plane = 5.0
    self.resolution = 128
    self.max_16bit_val = 65535
    self.light_sources = []
    self.light_nodes = []

    self.alight = AmbientLight('alight')
    self.alight.setColor(VBase4(0.2, 0.2, 0.2, 1))
    self.alnp = self.render.attachNewNode(self.alight)
    self.render.setLight(self.alnp)
    self.attenuation = False
    
    base.camLens.setNear(self.near_plane)
    base.camLens.setFar(self.far_plane)
    
    self.generate_depth = True
    if self.generate_depth is True:
      self.depth_tex = Texture()
      self.depth_tex.setFormat(Texture.FDepthComponent)
      self.depth_buffer = base.win.makeTextureBuffer('depthmap', self.resolution, self.resolution, self.depth_tex, to_ram=True)
      self.depth_cam = self.makeCamera(self.depth_buffer, lens = base.camLens)
      print(self.depth_cam.node().getLens().getFilmSize())
      self.depth_cam.reparentTo(base.render)
      pass

    self.models = []
    self.backgrounds = []
    self.model = None

    self.createLightSources()
    return
  
  def delete(self):
    self.alnp.removeNode()
    for n in self.light_nodes:
      n.removeNode()
      continue
    for m in self.models:
      self.loader.unloadModel(m)
      continue
    base.destroy()
    return

  def selectModel(self, model_ind):
    self.model = self.models[model_ind]
    self.model.reparentTo(self.scene)
    
  def unselectModel(self, model_ind):
    self.model.detachNode()
    self.model = None
    
  def loadModels(self, filenames):
    self.models = []
    for filename in filenames:
      floorplan = Floorplan(filename)
      floorplan.read()
      floorplan.segmentRooms()
      exit(1)
      self.models.append(floorplan.generateEggModel())
      continue
    return

  def createLightSources(self):
    for i in range(0, 7):
      plight = PointLight('plight')
      if self.attenuation is True:
        plight.setAttenuation((1, 0, 1))
        pass
      plight.setColor(VBase4(0, 0, 0, 0))
      self.light_sources.append(plight)
      plnp = self.render.attachNewNode(plight)
      plnp.setPos(3, 3, 3)
      render.setLight(plnp)
      self.light_nodes.append(plnp)
      continue
    return

  def activateLightSources(self, light_sources, spher=True):
    i = 0
    for lght in light_sources:
      lp_rad = lght[0]
      lp_el = lght[1]
      lp_az = lght[2]
      lp_int = lght[3]
      if spher:
        self.light_nodes[i].setPos(
          lp_rad*math.cos(lp_el)*math.cos(lp_az),
          lp_rad*math.cos(lp_el)*math.sin(lp_az),
          lp_rad*math.sin(lp_el))
      else:
        self.light_nodes[i].setPos(lp_rad, lp_el, lp_az)
        pass
      self.light_sources[i].setColor(VBase4(lp_int, lp_int, lp_int, 1))
      i += 1
      continue
    return
  
  def deactivateLightSources(self):
    for i in range(0, 7):
      self.light_sources[i].setColor(VBase4(0, 0, 0, 0))
      continue
    return

  def textureToImage(self, texture):
    im = texture.getRamImageAs("RGB")
    strim = im.getData()
    image = np.fromstring(strim, dtype='uint8')
    #image = image.reshape(1200, 1200)
    #cv2.imwrite('test/test.png', image.astype(np.uint8))
    image = image.reshape(self.resolution, self.resolution, 3)
    image = np.flipud(image)
    return image

  def setCameraPosition(self, pos, target):
    self.camera.setPos(pos[0], pos[1], pos[2])
    self.camera.lookAt(target[0], target[1], target[2])

    if self.generate_depth is True:
      self.depth_cam.setPos(pos[0], pos[1], pos[2])
      self.depth_cam.lookAt(target[0], target[1], target[2])
      pass
    return
  
  def renderView(self, camera_pos, light_sources):
    angle = math.radians(random.randint(0, 360))
    target = (camera_pos[0] + math.sin(angle), camera_pos[1] + math.cos(angle), camera_pos[2])
    self.setCameraPosition(camera_pos, target)

    self.activateLightSources(light_sources)

    base.graphicsEngine.renderFrame()
    tex = base.win.getScreenshot()
    im = self.textureToImage(tex)
    
    dm_uint = False
    
    if self.generate_depth is True:
      depth_im = PNMImage()
      self.depth_tex.store(depth_im)
      
      depth_map = np.zeros([self.resolution, self.resolution], dtype='float')
      for i in range(0, self.resolution):
        for j in range(0, self.resolution):
          depth_val = depth_im.getGray(j, i)
          depth_map[i, j] = self.far_plane * self.near_plane / (self.far_plane - depth_val * (self.far_plane - self.near_plane))
          depth_map[i, j] = depth_map[i, j] / self.far_plane
          continue
        continue
      dm_uint = np.round(depth_map * self.max_16bit_val).astype('uint16')
      pass
    
    
    im = im.astype(dtype=np.uint8)
    self.deactivateLightSources()
    return im, dm_uint


renderer = Renderer()
renderer.loadModels(['test/floorplan_2', ])
renderer.selectModel(0)

num_light = random.randint(2, 4)
lights = []
for nl in range(0, num_light):
  light_pos = [random.random()*2. + 2.5,
               random.randint(-90, 90),
               random.randint(0, 360),
               random.randint(10, 15)]
  lights.append(light_pos)
  continue

for im_num in range(0, 20):
  x = random.random()
  y = random.random()
  z = 0.15
  im, dm = renderer.renderView([x, y, z], lights)
  cv2.imwrite('test/rendering_' + str(im_num) + '.png', (np.asarray(im)).astype(np.uint8))
  cv2.imwrite('test/depth_' + str(im_num) + '.png', (np.asarray(1 / (dm / 65535.0) * 255)).astype(np.uint8))
  continue

exit(1)
