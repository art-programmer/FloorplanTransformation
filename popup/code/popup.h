#ifndef POPUP_H_
#define POPUP_H_

#include <string>
#include <utility>
#include <vector>

#include "structs.h"

bool ReadFloorplan(const std::string& filename,
                   Floorplan& floorplan);

bool ChangeDoorsToWindows(const Options& options, Floorplan& floorplan);

bool ExtractArchitectureFloorplan(const Floorplan& floorplan,
                                  ArchitectureFloorplan& architecture_floorplan);

bool GenerateArchitectureMesh(const Floorplan& floorplan,
                              const ArchitectureFloorplan& architecture_floorplan,
                              const Options& options,
                              RasterArchitectureFloorplan& raster_architecture_floorplan,
                              ArchitectureMesh& architecture_mesh);

bool WriteArchitectureMesh(const ArchitectureMesh& architecture_mesh,
                           const std::string& prefix,
                           const std::string& mtl_filename);

bool WriteObjects(const Floorplan& floorplan, 
                  const std::vector<Eigen::Vector4d>& free_space_ratios,
                  const double scale,
                  const std::string& prefix);

bool WriteMtl(const Options& options,
              const std::string& mtl_path,
              const std::string& floorplan_jpg_filename);

#endif  // POPUP_H_
