#ifndef POPUP_3D_H_
#define POPUP_3D_H_

#include <vector>
#include "asset.h"
#include "structs.h"

bool FloorToFloorMesh(const int width,
                      const int height,
                      const std::vector<RasterArchitectureFloorplan::FloorType>& floor,
                      const int wall_radius,
                      const double wall_uv_scale,
                      const double floor_uv_scale,
                      const bool use_floorplan_image,
                      const int image_width,
                      const int image_height,
                      ArchitectureMesh& architecture_mesh);

bool FloorToWallDoorWindowMesh(const ArchitectureFloorplan& architecture_floorplan,
                               const RasterArchitectureFloorplan& raster_architecture_floorplan,
                               const Options& options,
                               ArchitectureMesh& architecture_mesh);

bool GetVerticalSurfaceRightBottom(
    const RasterArchitectureFloorplan& raster_architecture_floorplan,
    const Options& options,
    const int x, const int y,
    const int right_or_bottom,
    std::vector<VerticalSurface>& surfaces);

#endif  // POPUP_3D_H_
