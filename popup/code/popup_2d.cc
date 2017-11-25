#include <fstream>
#include <iostream>
#include <limits>
#include <list>
#include <string>
#include <vector>
#include <Eigen/Dense>

#include "popup_2d.h"

using namespace Eigen;
using namespace std;

namespace {

bool SetSearchBox(const int width, const int height, const Annotation& annotation, 
                  const int object_front_search_distance, 
                  Vector2i search_xs[4], Vector2i search_ys[4]) {
  const int kBottom = 2;
  const int kRight  = 1;
  const int kTop    = 0;
  const int kLeft   = 3;
  search_xs[kBottom] = 
    Vector2i(annotation.xs[0], annotation.xs[1]);
  search_ys[kBottom] = 
    Vector2i(annotation.ys[1] + 1, annotation.ys[1] + object_front_search_distance);
  
  search_xs[kLeft] =
    Vector2i(annotation.xs[0] - object_front_search_distance, annotation.xs[0] - 1);
  search_ys[kLeft] =
    Vector2i(annotation.ys[0], annotation.ys[1]);
  
  search_xs[kTop] = 
    Vector2i(annotation.xs[0], annotation.xs[1]);
  search_ys[kTop] = 
    Vector2i(annotation.ys[0] - object_front_search_distance, annotation.ys[0] - 1);
  
  search_xs[kRight] =
    Vector2i(annotation.xs[1] + 1, annotation.xs[1] + object_front_search_distance);
  search_ys[kRight] =
    Vector2i(annotation.ys[0], annotation.ys[1]);
  
  // Out-of-bounds check.
  for (int i = 0; i < 4; ++i) {
    search_xs[i][0] = max(0, search_xs[i][0]);
    search_xs[i][1] = min(width - 1, search_xs[i][1]);
    
    search_ys[i][0] = max(0, search_ys[i][0]);
    search_ys[i][1] = min(height - 1, search_ys[i][1]);
  }
  
  return true;
}

}  // namespace

bool GetWallTypes(const int attributes[2],
                  RasterArchitectureFloorplan::WallType wall_types[2]) {
  for (int i = 0; i < 2; ++i) {
    switch (attributes[i]) {
      case 2: {
        wall_types[i] = RasterArchitectureFloorplan::kKitchenWall;
        break;
      }
      case 3: {
        wall_types[i] = RasterArchitectureFloorplan::kBedroomWall;
        break;
      }
      case 4:
      case 5:
      case 9: {
        wall_types[i] = RasterArchitectureFloorplan::kBathroomWall;
        break;
      }
      case 1: {
        wall_types[i] = RasterArchitectureFloorplan::kDiningWall;
        break;
      }
      case 6:
      case 7:
      case 8:
      case 10:
      case 11: {
        wall_types[i] = RasterArchitectureFloorplan::kWall;
        break;
      }
    }
  }
  return true;
}

bool SetWall(const ArchitectureFloorplan& architecture_floorplan,
             const int width, const int height, const Options& options,
             RasterArchitectureFloorplan& raster_architecture_floorplan){
  auto& wall        = raster_architecture_floorplan.wall;

  const int radius = options.wall_radius;
  wall.resize(width * height,        RasterArchitectureFloorplan::kNotWall);

  for (const auto& wall_annotation : architecture_floorplan.walls) {
    // Overwrite.
    RasterArchitectureFloorplan::WallType wall_types[2];
    if (!GetWallTypes(wall_annotation.attributes, wall_types))
      return false;

    // Centerline only.
    if (wall_annotation.ys[0] == wall_annotation.ys[1]) {  // Horizontal.
      for (int x = wall_annotation.xs[0] - radius; x <= wall_annotation.xs[1] + radius; ++x) {
        wall[wall_annotation.ys[0] * width + x] = wall_types[0];
      }
    } else {                                               // Vertical.
      for (int y = wall_annotation.ys[0] - radius; y <= wall_annotation.ys[1] + radius; ++y) {
        wall[y * width + wall_annotation.xs[0]] = wall_types[0];
      }
    }
  }

  for (const auto& wall_annotation : architecture_floorplan.walls) {
    // Overwrite.
    RasterArchitectureFloorplan::WallType wall_types[2];
    if (!GetWallTypes(wall_annotation.attributes, wall_types))
      return false;

    // Sides.
    if (wall_annotation.ys[0] == wall_annotation.ys[1]) {  // Horizontal.
      for (int y = wall_annotation.ys[0] - radius; y < wall_annotation.ys[1]; ++y) {
        for (int x = wall_annotation.xs[0] - radius; x <= wall_annotation.xs[1] + radius; ++x) {
          if (wall_annotation.xs[0] <= x && x <= wall_annotation.xs[1])
            continue;
          wall[y * width + x] = wall_types[1];
        }
      }

      for (int y = wall_annotation.ys[0] + 1; y <= wall_annotation.ys[1] + radius; ++y) {
        for (int x = wall_annotation.xs[0] - radius; x <= wall_annotation.xs[1] + radius; ++x) {
          if (wall_annotation.xs[0] <= x && x <= wall_annotation.xs[1])
            continue;
          wall[y * width + x] = wall_types[0];
        }
      }
    } else {                                               // Vertical.
      for (int y = wall_annotation.ys[0] - radius; y <= wall_annotation.ys[1] + radius; ++y) {
        for (int x = wall_annotation.xs[0] - radius; x < wall_annotation.xs[1]; ++x) {
          if (wall_annotation.ys[0] <= y && y <= wall_annotation.ys[1])
            continue;
          wall[y * width + x] = wall_types[1];
        }
      }

      for (int y = wall_annotation.ys[0] - radius; y <= wall_annotation.ys[1] + radius; ++y) {
        for (int x = wall_annotation.xs[0] + 1; x <= wall_annotation.xs[1] + radius; ++x) {
          if (wall_annotation.ys[0] <= y && y <= wall_annotation.ys[1])
            continue;
          wall[y * width + x] = wall_types[0];
        }
      }
    }
  }

  for (const auto& wall_annotation : architecture_floorplan.walls) {
    // Overwrite.
    RasterArchitectureFloorplan::WallType wall_types[2];
    if (!GetWallTypes(wall_annotation.attributes, wall_types))
      return false;

    // Sides.
    if (wall_annotation.ys[0] == wall_annotation.ys[1]) {  // Horizontal.
      for (int y = wall_annotation.ys[0] - radius; y < wall_annotation.ys[1]; ++y) {
        for (int x = wall_annotation.xs[0]; x <= wall_annotation.xs[1]; ++x) {
          wall[y * width + x] = wall_types[1];
        }
      }

      for (int y = wall_annotation.ys[0] + 1; y <= wall_annotation.ys[1] + radius; ++y) {
        for (int x = wall_annotation.xs[0]; x <= wall_annotation.xs[1]; ++x) {
          wall[y * width + x] = wall_types[0];
        }
      }
    } else {                                               // Vertical.
      for (int y = wall_annotation.ys[0]; y <= wall_annotation.ys[1]; ++y) {
        for (int x = wall_annotation.xs[0] - radius; x < wall_annotation.xs[1]; ++x) {
          wall[y * width + x] = wall_types[1];
        }
      }

      for (int y = wall_annotation.ys[0]; y <= wall_annotation.ys[1]; ++y) {
        for (int x = wall_annotation.xs[0] + 1; x <= wall_annotation.xs[1] + radius; ++x) {
          wall[y * width + x] = wall_types[0];
        }
      }
    }
  }

  return true;
}

bool SetFloor(const int width,
              const int height,
              const vector<RasterArchitectureFloorplan::WallType>& wall,
              vector<RasterArchitectureFloorplan::FloorType>& floor) {
  floor.clear();
  floor.resize(width * height, RasterArchitectureFloorplan::kFloor);

  list<Eigen::Vector2i> ltmp;
  ltmp.push_back(Vector2i(0, 0));
  floor[0] = RasterArchitectureFloorplan::kNotFloor;

  while (!ltmp.empty()) {
    const Vector2i position = ltmp.front();
    ltmp.pop_front();
    const int index = position[1] * width + position[0];

    const int right = index + 1;
    if (position[0] < width - 1 &&
        wall[right] == RasterArchitectureFloorplan::kNotWall &&
        floor[right] == RasterArchitectureFloorplan::kFloor) {
      floor[right] = RasterArchitectureFloorplan::kNotFloor;
      ltmp.push_back(position + Vector2i(1, 0));
    }

    const int left = index - 1;
    if (position[0] > 0 &&
        wall[left] == RasterArchitectureFloorplan::kNotWall &&
        floor[left] == RasterArchitectureFloorplan::kFloor) {
      floor[left] = RasterArchitectureFloorplan::kNotFloor;
      ltmp.push_back(position + Vector2i(-1, 0));
    }

    const int bottom = index + width;
    if (position[1] < height - 1 &&
        wall[bottom] == RasterArchitectureFloorplan::kNotWall &&
        floor[bottom] == RasterArchitectureFloorplan::kFloor) {
      floor[bottom] = RasterArchitectureFloorplan::kNotFloor;
      ltmp.push_back(position + Vector2i(0, 1));
    }

    const int up = index - width;
    if (position[1] > 0 &&
        wall[up] == RasterArchitectureFloorplan::kNotWall &&
        floor[up] == RasterArchitectureFloorplan::kFloor) {
      floor[up] = RasterArchitectureFloorplan::kNotFloor;
      ltmp.push_back(position + Vector2i(0, -1));
    }
  }

  return true;
}


bool SetDoorOrWindow(const std::vector<Annotation>& annotations,
                     const int width, const int height, const Options& options,
                     std::vector<RasterArchitectureFloorplan::DirectionType>& directions,
                     std::vector<int>& annotation_ids) {
  directions.clear();
  annotation_ids.clear();
  directions.resize(width * height, RasterArchitectureFloorplan::kInvalid);
  annotation_ids.resize(width * height, -1);

  for (int a = 0; a < annotations.size(); ++a) {
    const auto& annotation = annotations[a];
    RasterArchitectureFloorplan::DirectionType direction_type;
    if (annotation.xs[0] == annotation.xs[1])
      direction_type = RasterArchitectureFloorplan::kVertical;
    else if (annotation.ys[0] == annotation.ys[1])
      direction_type = RasterArchitectureFloorplan::kHorizontal;
    else
      continue;

    const int radius = options.wall_radius;
    const int xradius = (direction_type == RasterArchitectureFloorplan::kVertical) ? radius : 0;
    const int yradius = (direction_type == RasterArchitectureFloorplan::kHorizontal) ? radius : 0;

    for (int y = annotation.ys[0] - yradius; y <= annotation.ys[1] + yradius; ++y) {
      if (y < 0 || height <= y)
        continue;
      for (int x = annotation.xs[0] - xradius; x <= annotation.xs[1] + xradius; ++x) {
        if (x < 0 || width <= x)
          continue;
        const int index = y * width + x;
        directions[index]     = direction_type;
        annotation_ids[index] = a;
      }
    }
  }

  return true;
}

bool SetRasterArchitectureFloorplan(const ArchitectureFloorplan& architecture_floorplan,
                                    const Options& options,
                                    const int width,
                                    const int height,
                                    RasterArchitectureFloorplan& raster_architecture_floorplan) {
  auto& rfloorplan = raster_architecture_floorplan;
  rfloorplan.width  = width;
  rfloorplan.height = height;

  if (!SetWall(architecture_floorplan, width, height, options, rfloorplan))
    return false;

  if (!SetFloor(width, height, rfloorplan.wall, rfloorplan.floor))
    return false;

  if (!SetDoorOrWindow(architecture_floorplan.doors, width, height, options,
                       rfloorplan.door, rfloorplan.door_annotation_id))
    return false;

  if (!SetDoorOrWindow(architecture_floorplan.windows, width, height, options,
                       rfloorplan.window, rfloorplan.window_annotation_id))
    return false;

  return true;
}

bool ComputeObjectFreeSpaceRatios(const Floorplan& floorplan,
                                  const ArchitectureFloorplan& architecture_floorplan,
                                  const RasterArchitectureFloorplan& raster_architecture_floorplan,
                                  const Options& options,
                                  std::vector<Vector4d>& free_space_ratios) {
  const int num_objects = floorplan.annotations.size();
  free_space_ratios.clear();
  free_space_ratios.resize(num_objects, Vector4d(0, 0, 0, 0));

  const int width  = raster_architecture_floorplan.width;
  const int height = raster_architecture_floorplan.height;
  const vector<RasterArchitectureFloorplan::WallType>& wall = 
    raster_architecture_floorplan.wall;

  for (int obj = 0; obj < num_objects; ++obj) {
    const auto& annotation = floorplan.annotations[obj];
    if (!(annotation.label == "bathtub" ||
          annotation.label == "washing_basin" ||
          annotation.label == "cooking_counter" ||
          annotation.label == "toilet" ||
          annotation.label == "stairs"))
      continue;

    // Find the most open space.
    Vector2i search_xs[4];
    Vector2i search_ys[4];

    if (!SetSearchBox(width, height, annotation, options.object_front_search_distance, 
                      search_xs, search_ys))
      return false;

    int free_counts[4] = {0, 0, 0, 0};
    int non_free_counts[4] = {0, 0, 0, 0};
    for (int d = 0; d < 4; ++d) {
      for (int y = search_ys[d][0]; y <= search_ys[d][1]; ++y) {
        for (int x = search_xs[d][0]; x <= search_xs[d][1]; ++x) {
          if (wall[y * width + x] == RasterArchitectureFloorplan::kNotWall)
            ++free_counts[d];
          else
            ++non_free_counts[d];
        }
      }
    }

    for (int d = 0; d < 4; ++d) {
      const int denom = max(1, free_counts[d] + non_free_counts[d]);
      free_space_ratios[obj][d] = free_counts[d] / static_cast<double>(denom);
    }
  }

  return true;
}
