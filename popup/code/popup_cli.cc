#include <iostream>
#include <string>

#include "popup.h"
#include "popup_2d.h"
#include "structs.h"

using namespace std;
using namespace Eigen;

int main(int argc, char* argv[]) {
  if (argc < 2) {
    cerr << "Usage: " << argv[0] << " input.txt" << endl;
    return 1;
  }

  Options options;

  Floorplan floorplan;
  if (!ReadFloorplan(argv[1], floorplan))
    return 1;

  if (!ChangeDoorsToWindows(options, floorplan))
    return 1;

  ArchitectureFloorplan architecture_floorplan;
  if (!ExtractArchitectureFloorplan(floorplan, architecture_floorplan))
    return 1;

  ArchitectureMesh architecture_mesh;
  RasterArchitectureFloorplan raster_architecture_floorplan;
  if (!GenerateArchitectureMesh(floorplan, architecture_floorplan, options, 
                                raster_architecture_floorplan,
                                architecture_mesh))
    return 1;

  if (!WriteArchitectureMesh(architecture_mesh,
                             string(argv[1]) + "-",
                             floorplan.mtl_filename))
    return 1;

  vector<Vector4d> free_space_ratios;
  if (!ComputeObjectFreeSpaceRatios(floorplan, 
                                    architecture_floorplan,
                                    raster_architecture_floorplan,
                                    options,
                                    free_space_ratios))
    return false;

  if (!WriteObjects(floorplan, free_space_ratios, options.object_scale, 
                    string(argv[1]) + "-"))
    return 1;

  if (!WriteMtl(options, floorplan.mtl_path, floorplan.floorplan_jpg_filename))
    return 1;

  return 0;
}
