import argparse

def parse_args():
    """
    Parse input arguments
    """
    parser = argparse.ArgumentParser(description='PlaneFlow')
    
    parser.add_argument('--task', dest='task',
                        help='task type: [train, test, predict]',
                        default='train', type=str)
    parser.add_argument('--restore', dest='restore',
                        help='how to restore the model',
                        default=1, type=int)
    parser.add_argument('--batchSize', dest='batchSize',
                        help='batch size',
                        default=16, type=int)
    parser.add_argument('--dataset', dest='dataset',
                        help='dataset name for training',
                        default='scannet', type=str)
    parser.add_argument('--testingDataset', dest='testingDataset',
                        help='dataset name for test/predict',
                        default='scannet', type=str)
    parser.add_argument('--numTrainingImages', dest='numTrainingImages',
                        help='the number of images to train',
                        default=10000, type=int)
    parser.add_argument('--numTestingImages', dest='numTestingImages',
                        help='the number of images to test/predict',
                        default=100, type=int)
    parser.add_argument('--LR', dest='LR',
                        help='learning rate',
                        default=2.5e-4, type=float)
    parser.add_argument('--numEpochs', dest='numEpochs',
                        help='the number of epochs',
                        default=1000, type=int)
    parser.add_argument('--startEpoch', dest='startEpoch',
                        help='starting epoch index',
                        default=0, type=int)
    parser.add_argument('--modelType', dest='modelType',
                        help='model type',
                        default='', type=str)
    parser.add_argument('--heatmapThreshold', dest='heatmapThreshold',
                        help='heatmap threshold for positive predictions',
                        default=0.5, type=float)
    parser.add_argument('--distanceThreshold3D', dest='distanceThreshold3D',
                        help='distance threshold 3D',
                        default=0.2, type=float)
    parser.add_argument('--distanceThreshold2D', dest='distanceThreshold2D',
                        help='distance threshold 2D',
                        default=20, type=float)
    parser.add_argument('--numInputPlanes', dest='numInputPlanes',
                        help='the number of input planes',
                        default=1024, type=int)
    parser.add_argument('--numOutputPlanes', dest='numOutputPlanes',
                        help='the number of output planes',
                        default=10, type=int)
    parser.add_argument('--numInputClasses', dest='numInputClasses',
                        help='the number of input classes',
                        default=0, type=int)
    parser.add_argument('--numOutputClasses', dest='numOutputClasses',
                        help='the number of output classes',
                        default=0, type=int)    
    parser.add_argument('--width', dest='width',
                        help='input width',
                        default=256, type=int)
    parser.add_argument('--height', dest='height',
                        help='input height',
                        default=256, type=int)
    parser.add_argument('--outputWidth', dest='outputWidth',
                        help='output width',
                        default=256, type=int)
    parser.add_argument('--outputHeight', dest='outputHeight',
                        help='output height',
                        default=192, type=int)
    ## Flags
    parser.add_argument('--visualizeMode', dest='visualizeMode',
                        help='visualization mode',
                        default='', type=str)    
    parser.add_argument('--suffix', dest='suffix',
                        help='suffix to distinguish experiments',
                        default='', type=str)    
    
    args = parser.parse_args()
    return args
