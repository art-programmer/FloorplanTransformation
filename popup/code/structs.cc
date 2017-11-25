#include <iostream>
#include "structs.h"

using namespace std;

Mesh& GetWallMesh(const RasterArchitectureFloorplan::WallType wall_type,
                  ArchitectureMesh& architecture_mesh) {
  switch (wall_type) {
    case RasterArchitectureFloorplan::kBathroomWall: {
      return architecture_mesh.bathroom_wall;
    }
    case RasterArchitectureFloorplan::kKitchenWall: {
      return architecture_mesh.kitchen_wall;
    }
    case RasterArchitectureFloorplan::kDiningWall: {
      return architecture_mesh.dining_wall;
    }
    case RasterArchitectureFloorplan::kBedroomWall: {
      return architecture_mesh.bedroom_wall;
    }
    case RasterArchitectureFloorplan::kWall: {
      return architecture_mesh.wall;
    }
    default: {
      cerr << "Impossible0." << endl;
      exit (1);
    }
  }
}

Mesh& GetFloorMesh(const RasterArchitectureFloorplan::FloorType floor_type,
                   ArchitectureMesh& architecture_mesh) {
  switch (floor_type) {
    case RasterArchitectureFloorplan::kBathroomFloor: {
      return architecture_mesh.bathroom_floor;
    }
    case RasterArchitectureFloorplan::kKitchenFloor: {
      return architecture_mesh.kitchen_floor;
    }
    case RasterArchitectureFloorplan::kDiningFloor: {
      return architecture_mesh.dining_floor;
    }
    case RasterArchitectureFloorplan::kBedroomFloor: {
      return architecture_mesh.bedroom_floor;
    }
    case RasterArchitectureFloorplan::kFloor: {
      return architecture_mesh.floor;
    }
    default: {
      cerr << "Impossible1." << endl;
      exit (1);
    }
  }
}

Mesh& GetHorizontalSurfaceMesh(const ArchitectureFloorplan& architecture_floorplan,
                               const HorizontalSurface::MeshType mesh_type,
                               const int annotation_id,
                               ArchitectureMesh& architecture_mesh) {
  switch (mesh_type) {
    case HorizontalSurface::kWall: {
      return architecture_mesh.wall;
    }
    case HorizontalSurface::kDoor: {
      if (annotation_id < 0 || architecture_floorplan.doors.size() <= annotation_id) {
        cerr << "Index out of bounds: " << annotation_id << ' ' << architecture_floorplan.doors.size() << endl;
        exit (1);
      }
      if (architecture_floorplan.doors[annotation_id].attributes[0] == 1)
        return architecture_mesh.door0;
      else
        return architecture_mesh.door1;
    }
    case HorizontalSurface::kWindow: {
      return architecture_mesh.window;
    }
  }
}

Mesh& GetVerticalSurfaceMesh(const ArchitectureFloorplan& architecture_floorplan,
                             const VerticalSurface::MeshType mesh_type,
                             const RasterArchitectureFloorplan::WallType wall_type,
                             const int annotation_id,
                             ArchitectureMesh& architecture_mesh) {
  switch (mesh_type) {
    case VerticalSurface::kWall: {
      return GetWallMesh(wall_type, architecture_mesh);
    }
    case VerticalSurface::kDoor: {
      if (annotation_id < 0 || architecture_floorplan.doors.size() <= annotation_id) {
        cerr << "Index out of bounds: " << annotation_id << ' ' << architecture_floorplan.doors.size() << endl;
        exit (1);
      }
      if (architecture_floorplan.doors[annotation_id].attributes[0] == 1)
        return architecture_mesh.door0;
      else
        return architecture_mesh.door1;
    }
    case VerticalSurface::kWindow: {
      return architecture_mesh.window;
    }
  }
}

bool GetMinMaxXY(const ArchitectureFloorplan& architecture_floorplan,
                 int& min_x, int& max_x, int& min_y, int& max_y) {
  min_x = min_y = numeric_limits<int>::max();
  max_x = max_y = -numeric_limits<int>::max();

  for (const auto& wall : architecture_floorplan.walls) {
    min_x = min(min_x, min(wall.xs[0], wall.xs[1]));
    max_x = max(max_x, max(wall.xs[0], wall.xs[1]));

    min_y = min(min_y, min(wall.ys[0], wall.ys[1]));
    max_y = max(max_y, max(wall.ys[0], wall.ys[1]));
  }

  return true;
}
