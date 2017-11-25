#ifndef STRUCTS_H_
#define STRUCTS_H_

#include <Eigen/Dense>
#include <string>
#include <vector>

struct Options {
  int wall_radius;
  int wall_height;
  int door_height;
  int window_upper_height;
  int window_lower_height;

  double wall_uv_scale;
  double floor_uv_scale;
  double door_uv_scale;
  double window_uv_scale;

  double door_rotation_degree;
  double window_rotation_degree;

  double object_scale;

  int object_front_search_distance;
  double lower_ratio;
  double upper_ratio;

  int entrance_distance;

  bool use_floorplan_image;

  enum HeightAdjustment {
    kTopLeft,
    kTopRight,
    kBottomLeft,
    kBottomRight,
    kNone
  };

  HeightAdjustment height_adjustment;

  Options() {
    wall_radius         = 1;
    wall_height         = 100;
    door_height         = 80;
    window_upper_height = 80;
    window_lower_height = 50;

    wall_uv_scale   = 0.02;
    floor_uv_scale  = 0.01;
    door_uv_scale   = 0.1;
    window_uv_scale = 0.1;

    door_rotation_degree   = 0.0;
    window_rotation_degree = 0.0;

    object_scale = 1.0;

    object_front_search_distance = 20;

    use_floorplan_image = true;
    lower_ratio = 0.2;
    upper_ratio = 1.6;

    entrance_distance = 30;

    height_adjustment = kNone;  // kBottomLeft;
  }
};

//----------------------------------------------------------------------
// 2D data.
//----------------------------------------------------------------------
struct Annotation {
  int xs[2];
  int ys[2];
  std::string label;
  int attributes[2];
};

struct Floorplan {
  int image_width;
  int image_height;
  std::vector<Annotation> annotations;
  std::string floorplan_txt_path;
  std::string floorplan_jpg_filename;
  std::string mtl_path;
  std::string mtl_filename;
};

struct ArchitectureFloorplan {
  std::vector<Annotation> walls;
  std::vector<Annotation> doors;
  std::vector<Annotation> windows;
};

struct RasterArchitectureFloorplan {
  enum FloorType {
    kBathroomFloor,
    kKitchenFloor,
    kDiningFloor,
    kBedroomFloor,
    kFloor,
    kNotFloor
  };

  enum WallType {
    kBathroomWall,
    kKitchenWall,
    kDiningWall,
    kBedroomWall,
    kWall,
    kNotWall
  };

  enum DirectionType {
    kVertical,
    kHorizontal,
    kInvalid
  };

  int width;
  int height;

  std::vector<FloorType> floor;

  std::vector<WallType> wall;

  std::vector<DirectionType> door;
  std::vector<DirectionType> window;
  std::vector<int> door_annotation_id;
  std::vector<int> window_annotation_id;
};

//----------------------------------------------------------------------
// 3D data.
//----------------------------------------------------------------------
struct Triangle {
  Eigen::Vector3d vertices[3];
  Eigen::Vector2d uvs[3];
};

struct Mesh {
  std::string name;
  std::string material;
  std::vector<Triangle> triangles;
};

struct ArchitectureMesh {
  Mesh floor;
  Mesh bathroom_floor;
  Mesh kitchen_floor;
  Mesh dining_floor;
  Mesh bedroom_floor;
  Mesh floor_bottom;

  Mesh wall;
  Mesh bathroom_wall;
  Mesh kitchen_wall;
  Mesh dining_wall;
  Mesh bedroom_wall;

  Mesh door0;
  Mesh door1;
  Mesh window;

  ArchitectureMesh() {
    //----------------------------------------------------------------------
    floor.name          = "floor";
    bathroom_floor.name = "bathroom_floor";
    kitchen_floor.name  = "kitchen_floor";
    dining_floor.name   = "dining_floor";
    bedroom_floor.name  = "bedroom_floor";
    floor_bottom.name   = "floor_bottom";

    wall.name          = "wall";
    bathroom_wall.name = "bathroom_wall";
    kitchen_wall.name  = "kitchen_wall";
    dining_wall.name   = "dining_wall";
    bedroom_wall.name  = "bedroom_wall";

    door0.name          = "door0";
    door1.name          = "door1";
    window.name        = "window";

    //----------------------------------------------------------------------
    floor.material          = "floor";
    bathroom_floor.material = "wooden";
    kitchen_floor.material  = "wooden";
    dining_floor.material   = "wooden";
    bedroom_floor.material  = "wooden";

    wall.material          = "wall";
    bathroom_wall.material = "bathroom_wall";
    kitchen_wall.material  = "kitchen_wall";
    dining_wall.material   = "dining_wall";
    bedroom_wall.material  = "bedroom_wall";

    door0.material          = "door0";
    door1.material          = "door1";
    window.material        = "window";
  }
};

struct HorizontalSurface {
  enum MeshType {
    kWall,
    kDoor,
    kWindow
  };

  double height;
  bool flip;
  MeshType mesh_type;
  int annotation_id;

 HorizontalSurface(const double height,
                   const bool flip,
                   const MeshType mesh_type,
                   const int annotation_id) :
  height(height), flip(flip), mesh_type(mesh_type), annotation_id(annotation_id) {
  }
};

struct VerticalSurface {
  enum MeshType {
    kWall,
    kDoor,
    kWindow
  };

  MeshType mesh_type;
  RasterArchitectureFloorplan::WallType wall_type;
  Eigen::Vector2i point0;
  Eigen::Vector2i point1;
  double upper_height;
  double lower_height;
  int x_or_y;  // uv direction.
  int annotation_id;

  VerticalSurface(const MeshType mesh_type,
                  const RasterArchitectureFloorplan::WallType wall_type,
                  const Eigen::Vector2i& point0,
                  const Eigen::Vector2i& point1,
                  const double upper_height,
                  const double lower_height,
                  const int x_or_y,
                  const int annotation_id)
  : mesh_type(mesh_type),
    wall_type(wall_type),
    point0(point0),
    point1(point1),
    upper_height(upper_height),
    lower_height(lower_height),
    x_or_y(x_or_y),
    annotation_id(annotation_id) {
  }
};

Mesh& GetWallMesh(const RasterArchitectureFloorplan::WallType wall_type,
                  ArchitectureMesh& architecture_mesh);

Mesh& GetFloorMesh(const RasterArchitectureFloorplan::FloorType floor_type,
                   ArchitectureMesh& architecture_mesh);

Mesh& GetHorizontalSurfaceMesh(const ArchitectureFloorplan& architecture_floorplan,
                               const HorizontalSurface::MeshType mesh_type,
                               const int annotation_id,
                               ArchitectureMesh& architecture_mesh);

Mesh& GetVerticalSurfaceMesh(const ArchitectureFloorplan& architecture_floorplan,
                             const VerticalSurface::MeshType mesh_type,
                             const RasterArchitectureFloorplan::WallType wall_type,
                             const int annotation_id,
                             ArchitectureMesh& architecture_mesh);

bool GetMinMaxXY(const ArchitectureFloorplan& architecture_floorplan,
                 int& min_x, int& max_x, int& min_y, int& max_y);

#endif  // STRUCTS_H_
