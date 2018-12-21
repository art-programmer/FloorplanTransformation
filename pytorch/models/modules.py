import torch
from torch import nn
import numpy as np
from utils import *

## Conv + bn + relu
class ConvBlock(nn.Module):
    def __init__(self, in_planes, out_planes, kernel_size=3, stride=1, padding=None, mode='conv', use_bn=True):
        super(ConvBlock, self).__init__()

        self.use_bn = use_bn
        
        if padding == None:
            padding = (kernel_size - 1) // 2
            pass
        if mode == 'conv':
            self.conv = nn.Conv2d(in_planes, out_planes, kernel_size=kernel_size, stride=stride, padding=padding, bias=False)
        elif mode == 'deconv':
            self.conv = nn.ConvTranspose2d(in_planes, out_planes, kernel_size=kernel_size, stride=stride, padding=padding, bias=False)
        elif mode == 'conv_3d':
            self.conv = nn.Conv3d(in_planes, out_planes, kernel_size=kernel_size, stride=stride, padding=padding, bias=False)
        elif mode == 'deconv_3d':
            self.conv = nn.ConvTranspose3d(in_planes, out_planes, kernel_size=kernel_size, stride=stride, padding=padding, bias=False)
        else:
            print('conv mode not supported', mode)
            exit(1)
            pass
        if self.use_bn:
            if '3d' not in mode:
                self.bn = nn.BatchNorm2d(out_planes)
            else:
                self.bn = nn.BatchNorm3d(out_planes)
                pass
            pass
        self.relu = nn.ReLU(inplace=True)
        return
   
    def forward(self, inp):
        #return self.relu(self.conv(inp))
        if self.use_bn:
            return self.relu(self.bn(self.conv(inp)))
        else:
            return self.relu(self.conv(inp))

## The pyramid module from pyramid scene parsing
class PyramidModule(nn.Module):
    def __init__(self, options, in_planes, middle_planes, scales=[32, 16, 8, 4]):
        super(PyramidModule, self).__init__()
        
        self.pool_1 = torch.nn.AvgPool2d((scales[0] * options.height // options.width, scales[0]))
        self.pool_2 = torch.nn.AvgPool2d((scales[1] * options.height // options.width, scales[1]))        
        self.pool_3 = torch.nn.AvgPool2d((scales[2] * options.height // options.width, scales[2]))
        self.pool_4 = torch.nn.AvgPool2d((scales[3] * options.height // options.width, scales[3]))        
        self.conv_1 = ConvBlock(in_planes, middle_planes, kernel_size=1, use_bn=False)
        self.conv_2 = ConvBlock(in_planes, middle_planes, kernel_size=1)
        self.conv_3 = ConvBlock(in_planes, middle_planes, kernel_size=1)
        self.conv_4 = ConvBlock(in_planes, middle_planes, kernel_size=1)
        self.upsample = torch.nn.Upsample(size=(scales[0] * options.height // options.width, scales[0]), mode='bilinear')
        return
    
    def forward(self, inp):
        x_1 = self.upsample(self.conv_1(self.pool_1(inp)))
        x_2 = self.upsample(self.conv_2(self.pool_2(inp)))
        x_3 = self.upsample(self.conv_3(self.pool_3(inp)))
        x_4 = self.upsample(self.conv_4(self.pool_4(inp)))
        out = torch.cat([inp, x_1, x_2, x_3, x_4], dim=1)
        return out


## The module to compute plane depths from plane parameters
def calcPlaneDepthsModule(width, height, planes, metadata, return_ranges=False):
    urange = (torch.arange(width, dtype=torch.float32).cuda().view((1, -1)).repeat(height, 1) / (float(width) + 1) * (metadata[4] + 1) - metadata[2]) / metadata[0]
    vrange = (torch.arange(height, dtype=torch.float32).cuda().view((-1, 1)).repeat(1, width) / (float(height) + 1) * (metadata[5] + 1) - metadata[3]) / metadata[1]
    ranges = torch.stack([urange, torch.ones(urange.shape).cuda(), -vrange], dim=-1)
    
    planeOffsets = torch.norm(planes, dim=-1, keepdim=True)
    planeNormals = planes / torch.clamp(planeOffsets, min=1e-4)

    normalXYZ = torch.sum(ranges.unsqueeze(-2) * planeNormals.unsqueeze(-3).unsqueeze(-3), dim=-1)
    normalXYZ[normalXYZ == 0] = 1e-4
    planeDepths = planeOffsets.squeeze(-1).unsqueeze(-2).unsqueeze(-2) / normalXYZ
    planeDepths = torch.clamp(planeDepths, min=0, max=MAX_DEPTH)
    if return_ranges:
        return planeDepths, ranges
    return planeDepths


## The module to compute depth from plane information
def calcDepthModule(width, height, planes, segmentation, non_plane_depth, metadata):
    planeDepths = calcPlaneDepthsModule(width, height, planes, metadata)
    allDepths = torch.cat([planeDepths.transpose(-1, -2).transpose(-2, -3), non_plane_depth], dim=1)
    return torch.sum(allDepths * segmentation, dim=1)


## Compute matching with the auction-based approximation algorithm
def assignmentModule(W):
    O = calcAssignment(W.detach().cpu().numpy())
    return torch.from_numpy(O).cuda()

def calcAssignment(W):
    numOwners = int(W.shape[0])
    numGoods = int(W.shape[1])    
    P = np.zeros(numGoods)
    O = np.full(shape=(numGoods, ), fill_value=-1)
    delta = 1.0 / (numGoods + 1)
    queue = list(range(numOwners))
    while len(queue) > 0:
        ownerIndex = queue[0]
        queue = queue[1:]
        weights = W[ownerIndex]
        goodIndex = (weights - P).argmax()
        if weights[goodIndex] >= P[goodIndex]:
            if O[goodIndex] >= 0:
                queue.append(O[goodIndex])
                pass
            O[goodIndex] = ownerIndex
            P[goodIndex] += delta
            pass
        continue
    return O

## Get one-hot tensor
def oneHotModule(inp, depth):
    inpShape = [int(size) for size in inp.shape]
    inp = inp.view(-1)
    out = torch.zeros(int(inp.shape[0]), depth).cuda()
    out.scatter_(1, inp.unsqueeze(-1), 1)
    out = out.view(inpShape + [depth])
    return out

## Warp image
def warpImages(options, planes, images, transformations, metadata):
    planeDepths, ranges = calcPlaneDepthsModule(options.width, options.height, planes, metadata, return_ranges=True)
    print(planeDepths.shape, ranges.shape, transformations.shape)
    exit(1)
    XYZ = planeDepths.unsqueeze(-1) * ranges.unsqueeze(-2)
    XYZ = torch.cat([XYZ, torch.ones([int(size) for size in XYZ.shape[:-1]] + [1]).cuda()], dim=-1)
    XYZ = torch.matmul(XYZ.unsqueeze(-3), transformations.unsqueeze(-4).unsqueeze(-4))
    UVs = XYZ[:, :, :, :, :, :2] / XYZ[:, :, :, :, :, 2:3]
    UVs = (UVs * metadata[:2] + metadata[2:4]) / metadata[4:6] * 2 - 1
    warpedImages = []
    for imageIndex in range(options.numNeighborImages):
        warpedImage = []
        image = images[:, imageIndex]
        for planeIndex in range(options.numOutputPlanes):
            warpedImage.append(F.grid_sample(image, UVs[:, :, :, imageIndex, planeIndex]))
            continue
        warpedImages.append(torch.stack(warpedImage, 1))
        continue
    warpedImages = torch.stack(warpedImages, 2)
    return warpedImages
