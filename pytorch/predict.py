import imutils
import torch
import cv2
import numpy as np
from torch.utils.data import DataLoader

from utils import NUM_WALL_CORNERS
from options import parse_args
from models.model import Model
from IP import reconstructFloorplan
import matplotlib.pyplot as plt


def load_image(img_path):
    image = cv2.imread(img_path, 0)
    # image = imutils.resize(image, 256, 256)
    image = cv2.resize(image, (256, 256), interpolation=cv2.INTER_AREA)
    image = np.stack((image,) * 3, axis=-1)
    image = (image.astype(np.float32) / 255 - 0.5).transpose((2, 0, 1))
    image = image[np.newaxis, ...]
    np_print({'image': image})
    return image


def np_print(arrays):
    for name, array in arrays.items():
        print('*** ', name, array.shape, (array.min(), array.max()), np.unique(array).size)


def plot_images(images):
    subx, suby = {
        1: (1, 1),
        2: (1, 2),
        3: (1, 3),
        4: (2, 2),
        5: (2, 3),
        6: (2, 3),
        7: (3, 3),
        8: (3, 3),
        9: (3, 3),
        10: (3, 4),
        11: (3, 4),
        12: (3, 4),
        13: (3, 5),
        14: (3, 5),
        15: (3, 5),
        16: (4, 4),
    }[len(images)]

    fig = plt.figure()
    count = 0
    for title, image in images.items():
        count += 1
        ax = fig.add_subplot(subx, suby, count)
        ax.set_title(title)
        mappable = ax.imshow(image, cmap='jet')
        fig.colorbar(mappable, ax=ax)
    plt.show()


def main(img_path):
    options = parse_args()
    model = Model(options)
    model.load_state_dict(torch.load('checkpoint.pth', map_location=torch.device('cpu')))

    corner_pred, icon_pred, room_pred = model(torch.tensor(load_image(img_path)))

    corner_heatmaps = corner_pred[0].detach().cpu().numpy()
    icon_heatmaps = torch.nn.functional.softmax(icon_pred[0], dim=-1).detach().cpu().numpy()
    room_heatmaps = torch.nn.functional.softmax(room_pred[0], dim=-1).detach().cpu().numpy()

    wallCornerHeatmaps = corner_heatmaps[:, :, :NUM_WALL_CORNERS]
    doorCornerHeatmaps = corner_heatmaps[:, :, NUM_WALL_CORNERS:NUM_WALL_CORNERS + 4]
    iconCornerHeatmaps = corner_heatmaps[:, :, -4:]

    maps = {
        'original': cv2.imread(img_path),
        'corner_heatmaps': corner_heatmaps.max(-1),
        'icon_heatmaps': icon_heatmaps.max(-1),
        'room_heatmaps': room_heatmaps.max(-1),
        'corner_pred': np.squeeze(corner_pred.max(-1)[1].detach().cpu().numpy()),
        'icon_pred': np.squeeze(icon_pred.max(-1)[1].detach().cpu().numpy()),
        'room_pred': np.squeeze(room_pred.max(-1)[1].detach().cpu().numpy()),
        'wallCornerHeatmaps': wallCornerHeatmaps.max(-1),
        'doorCornerHeatmaps': doorCornerHeatmaps.max(-1),
        'iconCornerHeatmaps': iconCornerHeatmaps.max(-1),
    }
    np_print(maps)
    plot_images(maps)

    reconstructFloorplan(wallCornerHeatmaps, doorCornerHeatmaps, iconCornerHeatmaps,
                         icon_heatmaps, room_heatmaps,
                         output_prefix='output-', densityImage=None,
                         gt_dict=None, gt=False, gap=-1, distanceThreshold=-1, lengthThreshold=-1,
                         debug_prefix='test', heatmapValueThresholdWall=None,
                         heatmapValueThresholdDoor=None, heatmapValueThresholdIcon=None,
                         enableAugmentation=True)

if __name__ == '__main__':
    if len(sys.argv) > 1:
        img_path = sys.argv[1]
    else:
        img_path = 'input.jpg'
    main(img_path)
