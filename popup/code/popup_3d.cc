#include <fstream>
#include <iostream>
#include <limits>
#include <list>
#include <string>
#include <vector>
#include <Eigen/Dense>

#include "asset.h"
#include "popup_3d.h"
#include "structs.h"

using namespace Eigen;
using namespace std;

namespace {

double ComputeRatio(const Vector2i& xs, const Vector2i& ys, const double x, const double y,
                    const Options::HeightAdjustment height_adjustment) {
  const double total = xs[1] - xs[0] + ys[1] - ys[0];
  switch (height_adjustment) {
  case Options::kNone: {
    return 1.0;
  }
  case Options::kTopLeft: {
    return (fabs(x - xs[0]) + fabs(y - ys[0])) / total;
  }
  case Options::kTopRight: {
    return (fabs(x - xs[1]) + fabs(y - ys[0])) / total;
  }
  case Options::kBottomLeft: {
    return (fabs(x - xs[0]) + fabs(y - ys[1])) / total;
  }
  case Options::kBottomRight: {
    return (fabs(x - xs[1]) + fabs(y - ys[1])) / total;
  }
  }
}
  
bool FilterHorizontalSurfaces(const Vector2i& xs, const Vector2i& ys, const int x, const int y,
                              const double wall_height,
                              const Options::HeightAdjustment height_adjustment,
                              const double lower_ratio,
                              const double upper_ratio,
                              vector<HorizontalSurface>& horizontal_surfaces) {
  const double ratio = ComputeRatio(xs, ys, x, y, height_adjustment);
  const double height_threshold = wall_height * (lower_ratio + (upper_ratio - lower_ratio) * ratio);

  const double kEpsilon = 0.00001;
  vector<HorizontalSurface> tmp;
  tmp.swap(horizontal_surfaces);
  for (const auto& horizontal_surface : tmp) {
    if (horizontal_surface.height <= height_threshold + kEpsilon)
      horizontal_surfaces.push_back(horizontal_surface);
  }
  return true;
}

bool FilterVerticalSurfaces(const Vector2i& xs, const Vector2i& ys, 
                            const double wall_height,
                            const Options::HeightAdjustment height_adjustment,
                            const double lower_ratio,
                            const double upper_ratio,
                            vector<VerticalSurface>& vertical_surfaces) {
  vector<VerticalSurface> tmp;
  tmp.swap(vertical_surfaces);

  const double kEpsilon = 0.00001;
  for (auto& vertical_surface : tmp) {
    const double x = (vertical_surface.point0[0] + vertical_surface.point1[0]) / 2.0;
    const double y = (vertical_surface.point0[1] + vertical_surface.point1[1]) / 2.0;
    const double ratio = ComputeRatio(xs, ys, x, y, height_adjustment);
    int height_threshold = 
      static_cast<int>(round(wall_height * (lower_ratio + (upper_ratio - lower_ratio) * ratio)));

    const int discretization = 20;
    height_threshold = height_threshold / discretization * discretization;
    
    if (vertical_surface.lower_height > height_threshold)
      continue;

    vertical_surface.upper_height = min(vertical_surface.upper_height, static_cast<double>(height_threshold));
    vertical_surfaces.push_back(vertical_surface);
  }

  return true;         
}

bool Rotate(const Annotation& annotation, const double rotation_degree, Triangle& triangle) {
  Vector2d pivot(annotation.xs[0], annotation.ys[0]);
  const double rotation_radian = rotation_degree * M_PI / 180.0;
  Matrix2d rotation;
  rotation <<
      cos(rotation_radian), -sin(rotation_radian),
      sin(rotation_radian), cos(rotation_radian);

  for (int i = 0; i < 3; ++i) {
    Vector2d point(triangle.vertices[i][0], triangle.vertices[i][1]);
    const Vector2d new_point = rotation * (point - pivot) + pivot;

    triangle.vertices[i][0] = new_point[0];
    triangle.vertices[i][1] = new_point[1];
  }

  return true;
}

bool AddHorizontalFace(const int x, const int y, const int z,
                         const bool flip,
                         const double floor_uv_scale,
                         Triangle& triangle0, Triangle& triangle1) {
  triangle0.vertices[0] = Vector3d(x, y, z);
  triangle0.vertices[1] = Vector3d(x + 1, y, z);
  triangle0.vertices[2] = Vector3d(x + 1, y + 1, z);

  triangle0.uvs[0][0] = x * floor_uv_scale;
  triangle0.uvs[0][1] = y * floor_uv_scale;

  triangle0.uvs[1][0] = (x + 1) * floor_uv_scale;
  triangle0.uvs[1][1] = y * floor_uv_scale;

  triangle0.uvs[2][0] = (x + 1) * floor_uv_scale;
  triangle0.uvs[2][1] = (y + 1) * floor_uv_scale;

  triangle1.vertices[0] = Vector3d(x, y, z);
  triangle1.vertices[1] = Vector3d(x + 1, y + 1, z);
  triangle1.vertices[2] = Vector3d(x, y + 1, z);

  triangle1.uvs[0][0] = x * floor_uv_scale;
  triangle1.uvs[0][1] = y * floor_uv_scale;

  triangle1.uvs[1][0] = (x + 1) * floor_uv_scale;
  triangle1.uvs[1][1] = (y + 1) * floor_uv_scale;

  triangle1.uvs[2][0] = x * floor_uv_scale;
  triangle1.uvs[2][1] = (y + 1) * floor_uv_scale;

  if (flip) {
    swap(triangle0.vertices[0], triangle0.vertices[2]);
    swap(triangle1.vertices[0], triangle1.vertices[2]);

    swap(triangle0.uvs[0], triangle0.uvs[2]);
    swap(triangle1.uvs[0], triangle1.uvs[2]);
  }

  return true;
}

bool AddHorizontalFace(const int x, const int y, const int z,
                       const bool flip,
                       const int width,
                       const int height,
                       Triangle& triangle0, Triangle& triangle1) {
  triangle0.vertices[0] = Vector3d(x, y, z);
  triangle0.vertices[1] = Vector3d(x + 1, y, z);
  triangle0.vertices[2] = Vector3d(x + 1, y + 1, z);

  triangle0.uvs[0][0] = x / static_cast<double>(width);
  triangle0.uvs[0][1] = y / static_cast<double>(height);

  triangle0.uvs[1][0] = (x + 1) / static_cast<double>(width);
  triangle0.uvs[1][1] = y / static_cast<double>(height);;

  triangle0.uvs[2][0] = (x + 1) / static_cast<double>(width);
  triangle0.uvs[2][1] = (y + 1) / static_cast<double>(height);

  triangle1.vertices[0] = Vector3d(x, y, z);
  triangle1.vertices[1] = Vector3d(x + 1, y + 1, z);
  triangle1.vertices[2] = Vector3d(x, y + 1, z);

  triangle1.uvs[0][0] = x / static_cast<double>(width);
  triangle1.uvs[0][1] = y / static_cast<double>(height);

  triangle1.uvs[1][0] = (x + 1) / static_cast<double>(width);
  triangle1.uvs[1][1] = (y + 1) / static_cast<double>(height);

  triangle1.uvs[2][0] = x / static_cast<double>(width);
  triangle1.uvs[2][1] = (y + 1) / static_cast<double>(height);

  if (flip) {
    swap(triangle0.vertices[0], triangle0.vertices[2]);
    swap(triangle1.vertices[0], triangle1.vertices[2]);

    swap(triangle0.uvs[0], triangle0.uvs[2]);
    swap(triangle1.uvs[0], triangle1.uvs[2]);
  }

  return true;
}

bool AddVerticalFace(const Vector2i& point0, const Vector2i& point1,
                     const int floor_up_z, const int floor_bottom_z,
                     const int x_or_y, const double wall_uv_scale,
                     Mesh& mesh) {
  Triangle triangle0;
  triangle0.vertices[0] = Vector3d(point0[0], point0[1], floor_up_z);
  triangle0.vertices[1] = Vector3d(point1[0], point1[1], floor_up_z);
  triangle0.vertices[2] = Vector3d(point1[0], point1[1], floor_bottom_z);

  if (x_or_y == 0) {
    triangle0.uvs[0][0] = point0[0] * wall_uv_scale;
    triangle0.uvs[0][1] = floor_up_z * wall_uv_scale;

    triangle0.uvs[1][0] = point1[0] * wall_uv_scale;
    triangle0.uvs[1][1] = floor_up_z * wall_uv_scale;

    triangle0.uvs[2][0] = point1[0] * wall_uv_scale;
    triangle0.uvs[2][1] = floor_bottom_z * wall_uv_scale;
  } else {
    triangle0.uvs[0][0] = point0[1] * wall_uv_scale;
    triangle0.uvs[0][1] = floor_up_z * wall_uv_scale;

    triangle0.uvs[1][0] = point1[1] * wall_uv_scale;
    triangle0.uvs[1][1] = floor_up_z * wall_uv_scale;

    triangle0.uvs[2][0] = point1[1] * wall_uv_scale;
    triangle0.uvs[2][1] = floor_bottom_z * wall_uv_scale;
  }

  Triangle triangle1;
  triangle1.vertices[0] = Vector3d(point1[0], point1[1], floor_bottom_z);
  triangle1.vertices[1] = Vector3d(point0[0], point0[1], floor_bottom_z);
  triangle1.vertices[2] = Vector3d(point0[0], point0[1], floor_up_z);

  if (x_or_y == 0) {
    triangle1.uvs[0][0] = point1[0] * wall_uv_scale;
    triangle1.uvs[0][1] = floor_bottom_z * wall_uv_scale;

    triangle1.uvs[1][0] = point0[0] * wall_uv_scale;
    triangle1.uvs[1][1] = floor_bottom_z * wall_uv_scale;

    triangle1.uvs[2][0] = point0[0] * wall_uv_scale;
    triangle1.uvs[2][1] = floor_up_z * wall_uv_scale;
  } else {
    triangle1.uvs[0][0] = point1[1] * wall_uv_scale;
    triangle1.uvs[0][1] = floor_bottom_z * wall_uv_scale;

    triangle1.uvs[1][0] = point0[1] * wall_uv_scale;
    triangle1.uvs[1][1] = floor_bottom_z * wall_uv_scale;

    triangle1.uvs[2][0] = point0[1] * wall_uv_scale;
    triangle1.uvs[2][1] = floor_up_z * wall_uv_scale;
  }

  mesh.triangles.push_back(triangle0);
  mesh.triangles.push_back(triangle1);

  return true;
}

bool AddHorizontalFaceDoorWindow(const int x, const int y, const int z,
                                 const bool flip,
                                 const double floor_uv_scale,
                                 const Annotation& annotation,
                                 const double rotation_degree,
                                 Triangle& triangle0, Triangle& triangle1) {
  triangle0.vertices[0] = Vector3d(x, y, z);
  triangle0.vertices[1] = Vector3d(x + 1, y, z);
  triangle0.vertices[2] = Vector3d(x + 1, y + 1, z);

  triangle0.uvs[0][0] = x * floor_uv_scale;
  triangle0.uvs[0][1] = y * floor_uv_scale;

  triangle0.uvs[1][0] = (x + 1) * floor_uv_scale;
  triangle0.uvs[1][1] = y * floor_uv_scale;

  triangle0.uvs[2][0] = (x + 1) * floor_uv_scale;
  triangle0.uvs[2][1] = (y + 1) * floor_uv_scale;

  triangle1.vertices[0] = Vector3d(x, y, z);
  triangle1.vertices[1] = Vector3d(x + 1, y + 1, z);
  triangle1.vertices[2] = Vector3d(x, y + 1, z);

  triangle1.uvs[0][0] = x * floor_uv_scale;
  triangle1.uvs[0][1] = y * floor_uv_scale;

  triangle1.uvs[1][0] = (x + 1) * floor_uv_scale;
  triangle1.uvs[1][1] = (y + 1) * floor_uv_scale;

  triangle1.uvs[2][0] = x * floor_uv_scale;
  triangle1.uvs[2][1] = (y + 1) * floor_uv_scale;

  if (flip) {
    swap(triangle0.vertices[0], triangle0.vertices[2]);
    swap(triangle1.vertices[0], triangle1.vertices[2]);

    swap(triangle0.uvs[0], triangle0.uvs[2]);
    swap(triangle1.uvs[0], triangle1.uvs[2]);
  }

  Rotate(annotation, rotation_degree, triangle0);
  Rotate(annotation, rotation_degree, triangle1);

  return true;
}

bool AddVerticalFaceDoorWindow(const Vector2i& point0, const Vector2i& point1,
                               const int floor_up_z, const int floor_bottom_z,
                               const int x_or_y, const double wall_uv_scale,
                               const Annotation& annotation,
                               const double rotation_degree,
                               Mesh& mesh) {
  const int min_value = (x_or_y == 0) ? annotation.xs[0] : annotation.ys[0];
  const int max_value = (x_or_y == 0) ? annotation.xs[1] : annotation.ys[1];
  const double range = max(1, max_value - min_value);

  Triangle triangle0;
  triangle0.vertices[0] = Vector3d(point0[0], point0[1], floor_up_z);
  triangle0.vertices[1] = Vector3d(point1[0], point1[1], floor_up_z);
  triangle0.vertices[2] = Vector3d(point1[0], point1[1], floor_bottom_z);

  if (x_or_y == 0) {
    triangle0.uvs[0][0] = (point0[0] - min_value) / range;
    triangle0.uvs[0][1] = 1.0;

    triangle0.uvs[1][0] = (point1[0] - min_value) / range;
    triangle0.uvs[1][1] = 1.0;

    triangle0.uvs[2][0] = (point1[0] - min_value) / range;
    triangle0.uvs[2][1] = 0.0;
  } else {
    triangle0.uvs[0][0] = (point0[1] - min_value) / range;
    triangle0.uvs[0][1] = 1.0;

    triangle0.uvs[1][0] = (point1[1] - min_value) / range;
    triangle0.uvs[1][1] = 1.0;

    triangle0.uvs[2][0] = (point1[1] - min_value) / range;
    triangle0.uvs[2][1] = 0.0;
  }

  Triangle triangle1;
  triangle1.vertices[0] = Vector3d(point1[0], point1[1], floor_bottom_z);
  triangle1.vertices[1] = Vector3d(point0[0], point0[1], floor_bottom_z);
  triangle1.vertices[2] = Vector3d(point0[0], point0[1], floor_up_z);

  if (x_or_y == 0) {
    triangle1.uvs[0][0] = (point1[0] - min_value) / range;
    triangle1.uvs[0][1] = 0.0;

    triangle1.uvs[1][0] = (point0[0] - min_value) / range;
    triangle1.uvs[1][1] = 0.0;

    triangle1.uvs[2][0] = (point0[0] - min_value) / range;
    triangle1.uvs[2][1] = 1.0;
  } else {
    triangle1.uvs[0][0] = (point1[1] - min_value) / range;
    triangle1.uvs[0][1] = 0.0;

    triangle1.uvs[1][0] = (point0[1] - min_value) / range;
    triangle1.uvs[1][1] = 0.0;

    triangle1.uvs[2][0] = (point0[1] - min_value) / range;
    triangle1.uvs[2][1] = 1.0;
  }

  Rotate(annotation, rotation_degree, triangle0);
  Rotate(annotation, rotation_degree, triangle1);

  mesh.triangles.push_back(triangle0);
  mesh.triangles.push_back(triangle1);

  return true;
}

}  // namespace

bool FloorToFloorMesh(const int width,
                      const int height,
                      const std::vector<RasterArchitectureFloorplan::FloorType>& floor,
                      const int wall_radius,
                      const double wall_uv_scale,
                      const double floor_uv_scale,
                      const bool use_floorplan_image,
                      const int image_width,
                      const int image_height,
                      ArchitectureMesh& architecture_mesh) {
  Mesh& floor_bottom_mesh = architecture_mesh.floor_bottom;

  const int floor_top_z = 0;
  const int floor_bottom_z = - 2 * wall_radius + 1;
  const bool kFlip   = true;
  const bool kNoFlip = false;
  // Bottom.
  for (int y = 0; y < height; ++y) {
    for (int x = 0; x < width; ++x) {
      if (floor[y * width + x] != RasterArchitectureFloorplan::kNotFloor) {
        Triangle triangle0, triangle1;
        if (!AddHorizontalFace(x, y, floor_bottom_z, kFlip, floor_uv_scale, triangle0, triangle1))
          return false;

        floor_bottom_mesh.triangles.push_back(triangle0);
        floor_bottom_mesh.triangles.push_back(triangle1);
      }
    }
  }

  // Vertical.
  const int kX = 0;
  const int kY = 1;
  for (int y = 0; y < height - 1; ++y) {
    for (int x = 0; x < width - 1; ++x) {
      const int index = y * width + x;
      const int right_index = index + 1;
      if (floor[index] != RasterArchitectureFloorplan::kNotFloor &&
          floor[right_index] == RasterArchitectureFloorplan::kNotFloor) {
        if (!AddVerticalFace(Vector2i(x + 1, y + 1), Vector2i(x + 1, y), floor_top_z, floor_bottom_z,
                             kY, wall_uv_scale, floor_bottom_mesh))
          return false;
      } else if (floor[index] == RasterArchitectureFloorplan::kNotFloor &&
                 floor[right_index] != RasterArchitectureFloorplan::kNotFloor) {
        if (!AddVerticalFace(Vector2i(x + 1, y), Vector2i(x + 1, y + 1), floor_top_z, floor_bottom_z,
                             kY, wall_uv_scale, floor_bottom_mesh))
          return false;
      }

      const int bottom_index = index + width;
      if (floor[index] != RasterArchitectureFloorplan::kNotFloor &&
          floor[bottom_index] == RasterArchitectureFloorplan::kNotFloor) {
        if (!AddVerticalFace(Vector2i(x, y + 1), Vector2i(x + 1, y + 1), floor_top_z, floor_bottom_z,
                             kX, wall_uv_scale, floor_bottom_mesh))
          return false;
      } else if (floor[index] == RasterArchitectureFloorplan::kNotFloor &&
                 floor[bottom_index] != RasterArchitectureFloorplan::kNotFloor) {
        if (!AddVerticalFace(Vector2i(x + 1, y + 1), Vector2i(x, y + 1), floor_top_z, floor_bottom_z,
                             kX, wall_uv_scale, floor_bottom_mesh))
          return false;
      }
    }
  }

  // Top.
  for (int y = 0; y < height; ++y) {
    for (int x = 0; x < width; ++x) {
      if (floor[y * width + x] == RasterArchitectureFloorplan::kNotFloor)
        continue;

      Triangle triangle0, triangle1;
      if (use_floorplan_image) {
        if (!AddHorizontalFace(x, y, floor_top_z, kNoFlip, image_width, image_height, triangle0, triangle1))
          return false;
      } else {
        if (!AddHorizontalFace(x, y, floor_top_z, kNoFlip, floor_uv_scale, triangle0, triangle1))
          return false;
      }
      auto& mesh = GetFloorMesh(floor[y * width + x], architecture_mesh);
      mesh.triangles.push_back(triangle0);
      mesh.triangles.push_back(triangle1);
    }
  }

  return true;
}

bool FloorToWallDoorWindowMesh(const ArchitectureFloorplan& architecture_floorplan,
                               const RasterArchitectureFloorplan& raster_architecture_floorplan,
                               const Options& options,
                               ArchitectureMesh& architecture_mesh) {
  const auto& wall                 = raster_architecture_floorplan.wall;
  const auto& door                 = raster_architecture_floorplan.door;
  const auto& window               = raster_architecture_floorplan.window;
  const auto& door_annotation_id   = raster_architecture_floorplan.door_annotation_id;
  const auto& window_annotation_id = raster_architecture_floorplan.window_annotation_id;

  const int kBottomZ = 0;
  const int kX = 0;
  const int kY = 1;
  const bool kFlip   = true;
  const bool kNoFlip = false;
  const int kIrrelevant = -1;

  Vector2i xs, ys;
  if (!GetMinMaxXY(architecture_floorplan, xs[0], xs[1], ys[0], ys[1]))
    return false;

  for (int y = 0; y < raster_architecture_floorplan.height - 1; ++y) {
    for (int x = 0; x < raster_architecture_floorplan.width - 1; ++x) {
      const int index = y * raster_architecture_floorplan.width + x;

      { // Horizontal surface.
        if (wall[index] != RasterArchitectureFloorplan::kNotWall) {
          Triangle triangle0, triangle1;
          vector<HorizontalSurface> surfaces;

          if (door[index] != RasterArchitectureFloorplan::kInvalid) {
            // Door in a wall.
            surfaces.push_back(HorizontalSurface(options.wall_height, kNoFlip,
                                                 HorizontalSurface::kWall, kIrrelevant));
            surfaces.push_back(HorizontalSurface(options.door_height, kFlip,
                                                 HorizontalSurface::kWall, kIrrelevant));

            surfaces.push_back(HorizontalSurface(options.door_height, kNoFlip,
                                                 HorizontalSurface::kDoor, door_annotation_id[index]));
            surfaces.push_back(HorizontalSurface(kBottomZ,            kFlip,
                                                 HorizontalSurface::kDoor, door_annotation_id[index]));
          } else if (window[index] != RasterArchitectureFloorplan::kInvalid) {
            // Window in a wall.
            surfaces.push_back(HorizontalSurface(options.wall_height,         kNoFlip,
                                                 HorizontalSurface::kWall, kIrrelevant));
            surfaces.push_back(HorizontalSurface(options.window_upper_height, kFlip,
                                                 HorizontalSurface::kWall, kIrrelevant));
            surfaces.push_back(HorizontalSurface(options.window_lower_height, kNoFlip,
                                                 HorizontalSurface::kWall, kIrrelevant));
            surfaces.push_back(HorizontalSurface(kBottomZ,                    kFlip,
                                                 HorizontalSurface::kWall, kIrrelevant));

            surfaces.push_back(HorizontalSurface(options.window_upper_height, kNoFlip,
                                                 HorizontalSurface::kWindow, window_annotation_id[index]));
            surfaces.push_back(HorizontalSurface(options.window_lower_height, kFlip,
                                                 HorizontalSurface::kWindow, window_annotation_id[index]));
          } else {
            // Just a wall.
            surfaces.push_back(HorizontalSurface(options.wall_height, kNoFlip,
                                                 HorizontalSurface::kWall, kIrrelevant));
            surfaces.push_back(HorizontalSurface(kBottomZ,            kFlip,
                                                 HorizontalSurface::kWall, kIrrelevant));
          }
          if (!FilterHorizontalSurfaces(xs, ys, x, y, options.wall_height, options.height_adjustment, 
                                        options.lower_ratio, options.upper_ratio, surfaces))
            return false;

          for (const auto& surface : surfaces) {
            Mesh& mesh = GetHorizontalSurfaceMesh(architecture_floorplan,
                                                  surface.mesh_type,
                                                  surface.annotation_id,
                                                  architecture_mesh);
            if (surface.mesh_type == HorizontalSurface::kWall) {
              if (!AddHorizontalFace(x, y, surface.height, surface.flip, options.wall_uv_scale,
                                     triangle0, triangle1))
                return false;
            } else if (surface.mesh_type == HorizontalSurface::kDoor) {
              if (!AddHorizontalFaceDoorWindow(x, y, surface.height, surface.flip, options.wall_uv_scale,
                                               architecture_floorplan.doors[surface.annotation_id],
                                               options.door_rotation_degree, triangle0, triangle1))
                return false;
            } else {
              if (!AddHorizontalFaceDoorWindow(x, y, surface.height, surface.flip, options.wall_uv_scale,
                                               architecture_floorplan.windows[surface.annotation_id],
                                               options.window_rotation_degree, triangle0, triangle1))
                return false;
            }

            mesh.triangles.push_back(triangle0);
            mesh.triangles.push_back(triangle1);
          }
        }
      }
      {  // Vertical surface.
        const int kRight = 0;
        const int kBottom = 1;
        vector<VerticalSurface> surfaces;
        if (!GetVerticalSurfaceRightBottom(raster_architecture_floorplan,
                                           options, x, y, kRight, surfaces))
          return false;
        if (!GetVerticalSurfaceRightBottom(raster_architecture_floorplan,
                                           options, x, y, kBottom, surfaces))
          return false;

        if (!FilterVerticalSurfaces(xs, ys, options.wall_height, options.height_adjustment,
                                    options.lower_ratio, options.upper_ratio, surfaces))
          return false;

        for (const auto& surface : surfaces) {
          if (surface.mesh_type == VerticalSurface::kWall) {
            AddVerticalFace(surface.point0, surface.point1,
                            surface.upper_height, surface.lower_height, surface.x_or_y,
                            options.wall_uv_scale,
                            GetVerticalSurfaceMesh(architecture_floorplan,
                                                   surface.mesh_type,
                                                   surface.wall_type,
                                                   surface.annotation_id,
                                                   architecture_mesh));
          } else if (surface.mesh_type == VerticalSurface::kDoor) {
            AddVerticalFaceDoorWindow(surface.point0, surface.point1,
                                      surface.upper_height, surface.lower_height, surface.x_or_y,
                                      options.door_uv_scale,
                                      architecture_floorplan.doors[surface.annotation_id],
                                      options.door_rotation_degree,
                                      GetVerticalSurfaceMesh(architecture_floorplan,
                                                             surface.mesh_type,
                                                             surface.wall_type,
                                                             surface.annotation_id,
                                                             architecture_mesh));
          } else {
            AddVerticalFaceDoorWindow(surface.point0, surface.point1,
                                      surface.upper_height, surface.lower_height, surface.x_or_y,
                                      options.window_uv_scale,
                                      architecture_floorplan.windows[surface.annotation_id],
                                      options.window_rotation_degree,
                                      GetVerticalSurfaceMesh(architecture_floorplan,
                                                             surface.mesh_type,
                                                             surface.wall_type,
                                                             surface.annotation_id,
                                                             architecture_mesh));
          }
        }
      }
    }
  }

  return true;
}

bool GetVerticalSurfaceRightBottom(
    const RasterArchitectureFloorplan& raster_architecture_floorplan,
    const Options& options,
    const int x, const int y,
    const int right_or_bottom,
    std::vector<VerticalSurface>& surfaces) {
  const int width  = raster_architecture_floorplan.width;
  const int height = raster_architecture_floorplan.height;

  const vector<RasterArchitectureFloorplan::WallType>& wall        = raster_architecture_floorplan.wall;
  const vector<RasterArchitectureFloorplan::DirectionType>& door   = raster_architecture_floorplan.door;
  const vector<RasterArchitectureFloorplan::DirectionType>& window = raster_architecture_floorplan.window;
  const vector<int>& door_annotation_id   = raster_architecture_floorplan.door_annotation_id;
  const vector<int>& window_annotation_id = raster_architecture_floorplan.window_annotation_id;

  const RasterArchitectureFloorplan::WallType kBathroomWall = RasterArchitectureFloorplan::kBathroomWall;
  const RasterArchitectureFloorplan::WallType kKitchenWall  = RasterArchitectureFloorplan::kKitchenWall;
  const RasterArchitectureFloorplan::WallType kDiningWall   = RasterArchitectureFloorplan::kDiningWall;
  const RasterArchitectureFloorplan::WallType kBedroomWall  = RasterArchitectureFloorplan::kBedroomWall;
  const RasterArchitectureFloorplan::WallType kWall         = RasterArchitectureFloorplan::kWall;
  const RasterArchitectureFloorplan::WallType kNotWall      = RasterArchitectureFloorplan::kNotWall;

  const RasterArchitectureFloorplan::DirectionType kVertical   = RasterArchitectureFloorplan::kVertical;
  const RasterArchitectureFloorplan::DirectionType kHorizontal = RasterArchitectureFloorplan::kHorizontal;
  const RasterArchitectureFloorplan::DirectionType kInvalid    = RasterArchitectureFloorplan::kInvalid;

  const int index = y * width + x;
  const int next_index = (right_or_bottom == 0) ? index + 1 : index + width;

  const double kBottomZ = 0.0;
  const int uv_x_or_y = (right_or_bottom == 0) ? 1 : 0;
  const Vector2i point0 = (right_or_bottom == 0) ? Vector2i(x + 1, y + 1) : Vector2i(x, y + 1);
  const Vector2i point1 = (right_or_bottom == 0) ? Vector2i(x + 1, y) : Vector2i(x + 1, y + 1);
  const int kIrrelevant = -1;
  //----------------------------------------------------------------------
  if (wall[index] != kNotWall && wall[next_index] == kNotWall) {
    if (door[index] != kInvalid) {           // door.
      const int x_or_y = (door[index] == kHorizontal) ? 0 : 1;
      surfaces.push_back(VerticalSurface(VerticalSurface::kDoor, wall[index], point0, point1,
                                         options.door_height, kBottomZ, x_or_y,
                                         door_annotation_id[index]));
      surfaces.push_back(VerticalSurface(VerticalSurface::kWall, wall[index], point0, point1,
                                         options.wall_height, options.door_height, uv_x_or_y,
                                         kIrrelevant));
    } else if (window[index] != kInvalid) {  // window.
      const int x_or_y = (window[index] == kHorizontal) ? 0 : 1;
      surfaces.push_back(VerticalSurface(VerticalSurface::kWall, wall[index], point0, point1,
                                         options.wall_height, options.window_upper_height, uv_x_or_y,
                                         kIrrelevant));
      surfaces.push_back(VerticalSurface(VerticalSurface::kWindow, wall[index], point0, point1,
                                         options.window_upper_height, options.window_lower_height, x_or_y,
                                         window_annotation_id[index]));
      surfaces.push_back(VerticalSurface(VerticalSurface::kWall, wall[index], point0, point1,
                                         options.window_lower_height, kBottomZ, uv_x_or_y,
                                         kIrrelevant));
    } else {                                 // wall.
      surfaces.push_back(VerticalSurface(VerticalSurface::kWall, wall[index], point0, point1,
                                         options.wall_height, kBottomZ, uv_x_or_y,
                                         kIrrelevant));
    }
  } else if (wall[index] == kNotWall && wall[next_index] != kNotWall) {
    if (door[next_index] != kInvalid) {           // door.
      const int x_or_y = (door[next_index] == kHorizontal) ? 0 : 1;
      surfaces.push_back(VerticalSurface(VerticalSurface::kDoor, wall[next_index], point1, point0,
                                         options.door_height, kBottomZ, x_or_y,
                                         door_annotation_id[next_index]));
      surfaces.push_back(VerticalSurface(VerticalSurface::kWall, wall[next_index], point1, point0,
                                         options.wall_height, options.door_height, uv_x_or_y,
                                         kIrrelevant));
    } else if (window[next_index] != kInvalid) {  // window.
      const int x_or_y = (window[next_index] == kHorizontal) ? 0 : 1;
      surfaces.push_back(VerticalSurface(VerticalSurface::kWall, wall[next_index], point1, point0,
                                         options.wall_height, options.window_upper_height, uv_x_or_y,
                                         kIrrelevant));
      surfaces.push_back(VerticalSurface(VerticalSurface::kWindow, wall[next_index], point1, point0,
                                         options.window_upper_height, options.window_lower_height, x_or_y,
                                         window_annotation_id[next_index]));
      surfaces.push_back(VerticalSurface(VerticalSurface::kWall, wall[next_index], point1, point0,
                                         options.window_lower_height, kBottomZ, uv_x_or_y,
                                         kIrrelevant));
    } else {                                 // wall.
      surfaces.push_back(VerticalSurface(VerticalSurface::kWall, wall[next_index], point1, point0,
                                         options.wall_height, kBottomZ, uv_x_or_y,
                                         kIrrelevant));
    }
  } else if (wall[index] != kNotWall && wall[next_index] != kNotWall) {
    if (door[index] != kInvalid && door[next_index] == kInvalid) {
      const int x_or_y = (door[index] == kHorizontal) ? 0 : 1;
      surfaces.push_back(VerticalSurface(VerticalSurface::kDoor, wall[index], point0, point1,
                                         options.door_height, kBottomZ, x_or_y,
                                         door_annotation_id[index]));
      surfaces.push_back(VerticalSurface(VerticalSurface::kWall, wall[index], point1, point0,
                                         options.door_height, kBottomZ, uv_x_or_y,
                                         kIrrelevant));
    } else if (door[index] == kInvalid && door[next_index] != kInvalid) {
      const int x_or_y = (door[next_index] == kHorizontal) ? 0 : 1;
      surfaces.push_back(VerticalSurface(VerticalSurface::kDoor, wall[next_index], point1, point0,
                                         options.door_height, kBottomZ, x_or_y,
                                         door_annotation_id[next_index]));
      surfaces.push_back(VerticalSurface(VerticalSurface::kWall, wall[next_index], point0, point1,
                                         options.door_height, kBottomZ, uv_x_or_y,
                                         kIrrelevant));
    } else if (window[index] != kInvalid && window[next_index] == kInvalid) {
      const int x_or_y = (window[index] == kHorizontal) ? 0 : 1;
      surfaces.push_back(VerticalSurface(VerticalSurface::kWindow, wall[index], point0, point1,
                                         options.window_upper_height, options.window_lower_height, x_or_y,
                                         window_annotation_id[index]));
      surfaces.push_back(VerticalSurface(VerticalSurface::kWall, wall[index], point1, point0,
                                         options.window_upper_height, options.window_lower_height, uv_x_or_y,
                                         kIrrelevant));
    } else if (window[index] == kInvalid && window[next_index] != kInvalid) {
      const int x_or_y = (window[next_index] == kHorizontal) ? 0 : 1;
      surfaces.push_back(VerticalSurface(VerticalSurface::kWindow, wall[next_index], point1, point0,
                                         options.window_upper_height, options.window_lower_height, x_or_y,
                                         window_annotation_id[next_index]));
      surfaces.push_back(VerticalSurface(VerticalSurface::kWall, wall[next_index], point0, point1,
                                         options.window_upper_height, options.window_lower_height, uv_x_or_y,
                                         kIrrelevant));
    }
  } else {
    // None.
  }

  return true;
}
