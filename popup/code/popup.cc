#include <fstream>
#include <iostream>
#include <limits>
#include <list>
#include <string>
#include <vector>
#include <Eigen/Dense>

#include "asset.h"
#include "popup.h"
#include "popup_2d.h"
#include "popup_3d.h"

using namespace Eigen;
using namespace std;

namespace {

bool RasterArchitectureFloorplanToArchitectureMesh(
    const Floorplan& floorplan,
    const ArchitectureFloorplan& architecture_floorplan,
    const RasterArchitectureFloorplan& raster_architecture_floorplan,
    const Options& options,
    ArchitectureMesh& architecture_mesh) {
  if (!FloorToFloorMesh(raster_architecture_floorplan.width,
                        raster_architecture_floorplan.height,
                        raster_architecture_floorplan.floor,
                        options.wall_radius,
                        options.wall_uv_scale,
                        options.floor_uv_scale,
                        options.use_floorplan_image,
                        floorplan.image_width,
                        floorplan.image_height,
                        architecture_mesh))
    return false;

  if (!FloorToWallDoorWindowMesh(architecture_floorplan,
                                 raster_architecture_floorplan,
                                 options,
                                 architecture_mesh))
    return false;

  return true;
}

bool WriteMesh(const Mesh& mesh,
               const std::string& prefix,
               const std::string& mtl_filename) {
  if (mesh.triangles.empty())
    return true;

  ofstream ofstr;
  ofstr.open(prefix + mesh.name + string(".obj"));

  ofstr << "mtllib " << mtl_filename << endl;

  for (const auto& triangle : mesh.triangles) {
    for (int i = 0; i < 3; ++i) {
      ofstr << "v "
            << triangle.vertices[i][0] << ' '
            << triangle.vertices[i][1] << ' '
            << triangle.vertices[i][2] << endl;
    }
  }

  if (mesh.material == "") {
    int vertex_index = 1;
    for (const auto& triangle : mesh.triangles) {
      ofstr << "f "
            << vertex_index << ' '
            << vertex_index + 1 << ' '
            << vertex_index + 2 << endl;

      vertex_index += 3;
    }
  } else {
    ofstr << "usemtl " << mesh.material << endl;

    int vertex_index = 1;
    for (const auto& triangle : mesh.triangles) {
      for (int i = 0; i < 3; ++i) {
        ofstr << "vt "
              << triangle.uvs[i][0] << ' '
              << triangle.uvs[i][1] << endl;
      }

      ofstr << "f "
            << vertex_index << '/' << vertex_index << ' '
            << vertex_index + 1 << '/' << vertex_index + 1 << ' '
            << vertex_index + 2 << '/' << vertex_index + 2 << endl;

      vertex_index += 3;
    }
  }

  ofstr.close();
  return true;
}

int RangeDistance(const Vector2i& range0, const Vector2i& range1) {
  if (range0[1] < range1[0])
    return range1[0] - range0[1];
  else if (range1[1] < range0[0])
    return range0[0] - range1[1];
  else
    return 0;
}

}  // namespace

bool ReadFloorplan(const string& filename, Floorplan& floorplan) {
  ifstream ifstr;
  ifstr.open(filename.c_str());
  if (!ifstr.is_open()) {
    cerr << "Failed in reading the file: " << filename << endl;
    return false;
  }

  int num_walls;
  ifstr >> floorplan.image_width >> floorplan.image_height >> num_walls;

  for (int w = 0; w < num_walls; ++w) {
    Annotation annotation;
    ifstr >> annotation.xs[0] >> annotation.ys[0]
          >> annotation.xs[1] >> annotation.ys[1]
          >> annotation.attributes[0]
          >> annotation.attributes[1];
    annotation.label = "wall";

    const int newy0 = floorplan.image_height - annotation.ys[1];
    const int newy1 = floorplan.image_height - annotation.ys[0];

    annotation.ys[0] = newy0;
    annotation.ys[1] = newy1;

    floorplan.annotations.push_back(annotation);
  }

  while (true) {
    Annotation annotation;
    ifstr >> annotation.xs[0] >> annotation.ys[0]
          >> annotation.xs[1] >> annotation.ys[1]
          >> annotation.label
          >> annotation.attributes[0]
          >> annotation.attributes[1];
    if (ifstr.eof())
      break;

    const int newy0 = floorplan.image_height - annotation.ys[1];
    const int newy1 = floorplan.image_height - annotation.ys[0];

    annotation.ys[0] = newy0;
    annotation.ys[1] = newy1;

    floorplan.annotations.push_back(annotation);
  }
  ifstr.close();
  cerr << "Read " << floorplan.annotations.size() << " annotations." << endl;


  floorplan.floorplan_txt_path = filename;
  floorplan.floorplan_jpg_filename = filename;
  {
    string& stmp = floorplan.floorplan_jpg_filename;
    const int length = stmp.length();
    stmp[length - 3] = 'p';
    stmp[length - 2] = 'n';
    stmp[length - 1] = 'g';
    stmp = stmp.substr(stmp.find_last_of('/') + 1, length);
  }

  floorplan.mtl_path = filename;
  {
    string& stmp = floorplan.mtl_path;
    const int length = stmp.length();
    stmp[length - 3] = 'm';
    stmp[length - 2] = 't';
    stmp[length - 1] = 'l';

    floorplan.mtl_filename = stmp.substr(stmp.find_last_of('/') + 1, length);
  }

  return true;

  /*
  ifstream ifstr;
  ifstr.open(filename.c_str());
  if (!ifstr.is_open()) {
    cerr << "Failed in reading the file: " << filename << endl;
    return false;
  }

  ifstr >> floorplan.image_width >> floorplan.image_height;
  while (true) {
    Annotation annotation;
    ifstr >> annotation.xs[0] >> annotation.ys[0]
          >> annotation.xs[1] >> annotation.ys[1]
          >> annotation.label
          >> annotation.attributes[0]
          >> annotation.attributes[1];
    if (ifstr.eof())
      break;

    const int newy0 = floorplan.image_height - annotation.ys[1];
    const int newy1 = floorplan.image_height - annotation.ys[0];

    annotation.ys[0] = newy0;
    annotation.ys[1] = newy1;

    floorplan.annotations.push_back(annotation);
  }
  ifstr.close();
  cerr << "Read " << floorplan.annotations.size() << " annotations." << endl;


  floorplan.floorplan_txt_path = filename;
  floorplan.floorplan_jpg_filename = filename;
  {
    string& stmp = floorplan.floorplan_jpg_filename;
    const int length = stmp.length();
    stmp[length - 3] = 'p';
    stmp[length - 2] = 'n';
    stmp[length - 1] = 'g';
    stmp = stmp.substr(stmp.find_last_of('/') + 1, length);
  }

  floorplan.mtl_path = filename;
  {
    string& stmp = floorplan.mtl_path;
    const int length = stmp.length();
    stmp[length - 3] = 'm';
    stmp[length - 2] = 't';
    stmp[length - 1] = 'l';

    floorplan.mtl_filename = stmp.substr(stmp.find_last_of('/') + 1, length);
  }

  return true;
  */
}

bool ChangeDoorsToWindows(const Options& options, Floorplan& floorplan) {
  const int kExterior = 11;

  vector<Vector4i> entrance_xs_ys;
  for (auto& entrance : floorplan.annotations) {
    if (entrance.label != "entrance")
      continue;
    entrance_xs_ys.push_back(Vector4i(entrance.xs[0], entrance.xs[1], entrance.ys[0], entrance.ys[1]));
  }

  for (auto& door : floorplan.annotations) {
    if (door.label != "door")
      continue;

    // Close from entrance?
    int distance_from_entrance = numeric_limits<int>::max();
    for (const auto& xs_ys : entrance_xs_ys) {
      const int distance = 
        RangeDistance(Vector2i(door.xs[0], door.xs[1]), Vector2i(xs_ys[0], xs_ys[1])) +
        RangeDistance(Vector2i(door.ys[0], door.ys[1]), Vector2i(xs_ys[2], xs_ys[3]));
      distance_from_entrance = min(distance, distance_from_entrance);
    }

    if (distance_from_entrance < options.entrance_distance)
        continue;

    // If it is on a wall which is next to the exterior.
    for (const auto& wall : floorplan.annotations) {
      // Wall.
      if (wall.label != "wall")
        continue;
      // Exterior.
      if (wall.attributes[0] != kExterior && wall.attributes[1] != kExterior)
        continue;
      
      // If wall contains a door.
      if (wall.xs[0] <= door.xs[0] && door.xs[1] <= wall.xs[1] &&
          wall.ys[0] <= door.ys[0] && door.ys[1] <= wall.ys[1]) {
        door.label = "window";
      }
    }
  }

  return true;
}

bool ExtractArchitectureFloorplan(const Floorplan& floorplan, ArchitectureFloorplan& architecture_floorplan) {
  const string kWall   = "wall";
  const string kDoor   = "door";
  const string kWindow = "window";
  for (const auto& annotation : floorplan.annotations) {
    if (annotation.label == kWall)
      architecture_floorplan.walls.push_back(annotation);
    else if (annotation.label == kDoor)
      architecture_floorplan.doors.push_back(annotation);
    else if (annotation.label == kWindow)
      architecture_floorplan.windows.push_back(annotation);
  }

  return true;
}

bool GenerateArchitectureMesh(const Floorplan& floorplan,
                              const ArchitectureFloorplan& architecture_floorplan,
                              const Options& options,
                              RasterArchitectureFloorplan& raster_architecture_floorplan,
                              ArchitectureMesh& architecture_mesh) {
  int min_x, max_x, min_y, max_y;
  if (!GetMinMaxXY(architecture_floorplan, min_x, max_x, min_y, max_y))
    return false;

  if (min_x <= options.wall_radius || min_y <= options.wall_radius) {
    cerr << "Walls are too close to the image boundary." << endl;
    return false;
  }

  const int kMargin = 2;
  const int width  = max_x + options.wall_radius + kMargin;
  const int height = max_y + options.wall_radius + kMargin;

  if (!SetRasterArchitectureFloorplan(architecture_floorplan,
                                      options, width, height, raster_architecture_floorplan))
    return false;

  if (!RasterArchitectureFloorplanToArchitectureMesh(
          floorplan,
          architecture_floorplan,
          raster_architecture_floorplan,
          options,
          architecture_mesh))
    return false;

  return true;
}

bool WriteArchitectureMesh(const ArchitectureMesh& architecture_mesh,
                           const std::string& prefix,
                           const std::string& mtl_filename) {
  if (!WriteMesh(architecture_mesh.floor, prefix, mtl_filename))
    return false;

  if (!WriteMesh(architecture_mesh.bathroom_floor, prefix, mtl_filename))
    return false;

  if (!WriteMesh(architecture_mesh.kitchen_floor, prefix, mtl_filename))
    return false;

  if (!WriteMesh(architecture_mesh.dining_floor, prefix, mtl_filename))
    return false;

  if (!WriteMesh(architecture_mesh.bedroom_floor, prefix, mtl_filename))
    return false;

  if (!WriteMesh(architecture_mesh.floor_bottom, prefix, mtl_filename))
    return false;


  if (!WriteMesh(architecture_mesh.wall, prefix, mtl_filename))
    return false;

  if (!WriteMesh(architecture_mesh.bathroom_wall, prefix, mtl_filename))
    return false;

  if (!WriteMesh(architecture_mesh.kitchen_wall, prefix, mtl_filename))
    return false;

  if (!WriteMesh(architecture_mesh.dining_wall, prefix, mtl_filename))
    return false;

  if (!WriteMesh(architecture_mesh.bedroom_wall, prefix, mtl_filename))
    return false;


  if (!WriteMesh(architecture_mesh.door0, prefix, mtl_filename))
    return false;

  if (!WriteMesh(architecture_mesh.door1, prefix, mtl_filename))
    return false;

  if (!WriteMesh(architecture_mesh.window, prefix, mtl_filename))
    return false;

  return true;
}

bool WriteObjects(const Floorplan& floorplan,
                  const std::vector<Vector4d>& free_space_ratios,
                  const double scale,
                  const std::string& prefix) {
  int bathtub_id = 0;
  int washing_basin_id0 = 0;
  int washing_basin_id1 = 0;
  int cooking_counter_id = 0;
  int toilet_id = 0;
  int stairs_id = 0;
  //----------------------------------------------------------------------
  AssetDatabase database;
  if (!InitializeAssetDatabase(database))
    return false;

  for (int obj = 0; obj < floorplan.annotations.size(); ++obj) {
    const Annotation& annotation = floorplan.annotations[obj];
    const Vector4d free_space_ratio = free_space_ratios[obj];

    Asset asset;
    char filename[1024];
    if (annotation.label == "bathtub") {
      asset = database.bathtub;
      sprintf(filename, "%sbathtub%02d.obj", prefix.c_str(), bathtub_id++);
    } else if (annotation.label == "washing_basin") {
      if (annotation.attributes[0] == 1) {
        asset = database.washing_basin0;
        sprintf(filename, "%swashing_basin0%02d.obj", prefix.c_str(), washing_basin_id0++);
      } else {
        asset = database.washing_basin1;
        sprintf(filename, "%swashing_basin1%02d.obj", prefix.c_str(), washing_basin_id1++);
      }
    } else if (annotation.label == "cooking_counter") {
      asset = database.cooking_counter;
      sprintf(filename, "%scooking_counter%02d.obj", prefix.c_str(), cooking_counter_id++);
    } else if (annotation.label == "toilet") {
      asset = database.toilet;
      sprintf(filename, "%stoilet%02d.obj", prefix.c_str(), toilet_id++);
    } else if (annotation.label == "stairs") {
      asset = database.stairs;
      sprintf(filename, "%sstairs%02d.obj", prefix.c_str(), stairs_id++);
    } else {
      continue;
    }

    const double kZ = 0;
    Vector3d annotation_min_xyz(annotation.xs[0], annotation.ys[0], kZ);
    Vector3d annotation_max_xyz(annotation.xs[1], annotation.ys[1], kZ);
    Vector3d center = (annotation_min_xyz + annotation_max_xyz) / 2.0;
    annotation_min_xyz = center + (annotation_min_xyz - center) * scale;
    annotation_max_xyz = center + (annotation_max_xyz - center) * scale;

    if (!AlignAsset(annotation_min_xyz, annotation_max_xyz, free_space_ratio, asset))
      return false;

    if (!WriteAssetObj(filename, asset))
      return false;
  }

  return true;
}

bool WriteMtl(const Options& options,
              const std::string& mtl_path,
              const std::string& floorplan_jpg_filename) {
  ofstream ofstr;
  ofstr.open(mtl_path.c_str());
  if (!ofstr.is_open())
    return false;

  ofstr << "newmtl floor" << endl;
  if (options.use_floorplan_image) {
    ofstr << "  map_Ka " << floorplan_jpg_filename << endl
          << "  map_Kd " << floorplan_jpg_filename << endl;
  } else {
    ofstr << "  map_Ka floor.jpg" << endl
          << "  map_Kd floor.jpg" << endl;
  }
  ofstr << "newmtl door0" << endl
        << "  map_Ka door.jpg" << endl
        << "  map_Kd door.jpg" << endl
        << "newmtl door1" << endl
        << "  map_Ka door2.jpg" << endl
        << "  map_Kd door2.jpg" << endl
        << "newmtl wall" << endl
        << "  map_Ka wall.jpg" << endl
        << "  map_Kd wall.jpg" << endl
        << "newmtl bathroom_wall" << endl
        << "  map_Ka bathroom_wall.jpg" << endl
        << "  map_Kd bathroom_wall.jpg" << endl
        << "newmtl kitchen_wall" << endl
        << "  map_Ka kitchen_wall.jpg" << endl
        << "  map_Kd kitchen_wall.jpg" << endl
        << "newmtl dining_wall" << endl
        << "  map_Ka dining_wall.jpg" << endl
        << "  map_Kd dining_wall.jpg" << endl
        << "newmtl bedroom_wall" << endl
        << "  map_Ka bedroom_wall.jpg" << endl
        << "  map_Kd bedroom_wall.jpg" << endl
        << "newmtl window" << endl
        << "  map_Ka window.jpg" << endl
        << "  map_Kd window.jpg" << endl
        << "newmtl white" << endl;

  return true;
}
