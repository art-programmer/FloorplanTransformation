#ifndef ASSET_H_
#define ASSET_H_

#include <string>
#include <vector>
#include <Eigen/Dense>

struct Asset {
  std::vector<std::string> contents;
  std::vector<Eigen::Vector3d> vs;
  std::vector<Eigen::Vector3d> vns;

  // Stats.
  Eigen::Vector3d min_xyz;
  Eigen::Vector3d max_xyz;
  Eigen::Vector3d size;

  // Orientation.
  int num_turns_to_front;
};

struct AssetDatabase {
  Asset bathtub;
  Asset cooking_counter;
  Asset toilet;
  // Asset entrance;
  Asset washing_basin0;
  Asset washing_basin1;
  Asset stairs;
};

bool InitializeAssetDatabase(AssetDatabase& database);

bool ReadAssetFromObj(const std::string& filename, Asset& asset);
bool WriteAssetObj(const std::string& filename, const Asset& asset);

bool AlignAsset(const Eigen::Vector3d& min_xyz,
                const Eigen::Vector3d& max_xyz,
                const Eigen::Vector4d& free_space_ratio,
                Asset& asset);

bool Rotate(const double degree, Asset& asset);
bool Translate(const Eigen::Vector3d& motion, Asset& asset);
bool Scale(const double scale, Asset& asset);
bool Scale(const Eigen::Vector3d& scale, Asset& asset);

#endif  // ASSET_H_
