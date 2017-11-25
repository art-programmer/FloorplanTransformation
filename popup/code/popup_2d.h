#ifndef POPUP_2D_H_
#define POPUP_2D_H_

#include <vector>
#include "structs.h"

bool SetWall(const ArchitectureFloorplan& architecture_floorplan,
             const int width, const int height, const Options& options,
             std::vector<RasterArchitectureFloorplan::WallType>& wall);

bool SetFloor(const int width,
              const int height,
              const std::vector<RasterArchitectureFloorplan::WallType>& wall,
              std::vector<RasterArchitectureFloorplan::FloorType>& floor);

bool SetDoorOrWindow(const std::vector<Annotation>& annotations,
                     const int width, const int height, const Options& options,
                     std::vector<RasterArchitectureFloorplan::DirectionType>& directions,
                     std::vector<int>& annotation_ids);

bool SetRasterArchitectureFloorplan(const ArchitectureFloorplan& architecture_floorplan,
                                    const Options& options,
                                    const int width,
                                    const int height,
                                    RasterArchitectureFloorplan& raster_architecture_floorplan);

bool ComputeObjectFreeSpaceRatios(const Floorplan& floorplan,
                                  const ArchitectureFloorplan& architecture_floorplan,
                                  const RasterArchitectureFloorplan& raster_architecture_floorplan,
                                  const Options& options,
                                  std::vector<Eigen::Vector4d>& free_space_ratios);

#endif  // POPUP_2D_H_
