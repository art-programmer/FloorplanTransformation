# Raster-to-Vector: Revisiting Floorplan Transformation
By Chen Liu, Jiajun Wu, Pushmeet Kohli, and Yasutaka Furukawa

### Introduction

This paper addresses the problem of converting a rasterized
floorplan image into a vector-graphics representation.
Our algorithm significantly outperforms
existing methods and achieves around 90% precision and
recall, getting to the range of production-ready performance. 
To learn more, please see our ICCV 2017 [paper](https://www.cse.wustl.edu/~chenliu/floorplan-transformation/paper.pdf) or visit our [project website](https://www.cse.wustl.edu/~chenliu/floorplan-transformation.html).

This code implements the algorithm described in our paper in C++.

### Requirements

0. OpenCV
1. PCL
2. gflags

### Instruction

To compile the program:

0. mkdir build
1. cd build
2. cmake ..
3. make

To run the program on your own data:

./LayeredSceneDecomposition --image_path=*"your image path"* --point_cloud_path=*"your point cloud path"* --result_folder=*"where you want to save results"* --cache_folder=*"where you want to save cache"*

To run the program on the demo data:

./LayeredSceneDecomposition --image_path=../Input/image_01.txt --point_cloud_path=../Input/point_cloud_01.txt --result_folder=../Result --cache_folder=../Cache

Point cloud file format:

The point cloud file stores a 3D point cloud, each of which corresponds to one image pixel.
The number in the first row equals to image_width * image_height.
Then, each row stores 3D coordinates for a point which corresponds to a pixel (indexed by y * image_width + x).

### Contact

If you have any questions, please contact me at chenliu@wustl.edu.
