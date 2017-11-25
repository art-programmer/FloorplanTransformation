#include <fstream>
#include <iostream>
#include <limits>
#include <strstream>
#include "asset.h"

using namespace Eigen;
using namespace std;

bool InitializeAssetDatabase(AssetDatabase& database) {
  if (!ReadAssetFromObj("../data/bathtub.obj", database.bathtub))
    return false;

  if (!ReadAssetFromObj("../data/washing_basin.obj", database.washing_basin0))
    return false;

  if (!ReadAssetFromObj("../data/washing_basin2.obj", database.washing_basin1))
    return false;

  if (!ReadAssetFromObj("../data/cooking_counter.obj", database.cooking_counter))
    return false;

  if (!ReadAssetFromObj("../data/toilet.obj", database.toilet))
    return false;

  if (!ReadAssetFromObj("../data/stairs.obj", database.stairs))
    return false;

  // Add proper front for exceptional models.
  database.washing_basin0.num_turns_to_front = 1;

  return true;
}

bool ReadAssetFromObj(const std::string& filename, Asset& asset) {
  ifstream ifstr;
  ifstr.open(filename.c_str());
  if (!ifstr.is_open()) {
    cerr << "Cannot open a file: " << filename << endl;
    return false;
  }

  while (true) {
    string line;
    std::getline(ifstr, line);
    if (ifstr.eof())
      break;

    if (line.length() < 2) {
      asset.contents.push_back(line);
    } else if (line[0] == 'v' && line[1] == ' ') {
      strstream sstr;
      sstr << line;
      Vector3d v;
      string stmp;
      sstr >> stmp >> v[0] >> v[1] >> v[2];
      asset.vs.push_back(v);
    } else if (line[0] == 'v' && line[1] == 'n') {
      strstream sstr;
      sstr << line;
      Vector3d vn;
      string stmp;
      sstr >> stmp >> vn[0] >> vn[1] >> vn[2];
      asset.vns.push_back(vn);
    } else {
      asset.contents.push_back(line);
    }
  }

  //----------------------------------------------------------------------
  asset.min_xyz[0] = numeric_limits<double>::max();
  asset.min_xyz[1] = numeric_limits<double>::max();
  asset.min_xyz[2] = numeric_limits<double>::max();

  asset.max_xyz[0] = -numeric_limits<double>::max();
  asset.max_xyz[1] = -numeric_limits<double>::max();
  asset.max_xyz[2] = -numeric_limits<double>::max();

  for (const auto& v : asset.vs) {
    for (int a = 0; a < 3; ++a) {
      asset.min_xyz[a] = min(asset.min_xyz[a], v[a]);
      asset.max_xyz[a] = max(asset.max_xyz[a], v[a]);
    }
  }

  asset.size = asset.max_xyz - asset.min_xyz;

  ifstr.close();

  asset.num_turns_to_front = 0;

  return true;
}

bool WriteAssetObj(const std::string& filename, const Asset& asset) {
  ofstream ofstr;
  ofstr.open(filename.c_str());
  if (!ofstr.is_open())
    return false;

  for (const auto& v : asset.vs)
    ofstr << "v " << v[0] << ' ' << v[1] << ' ' << v[2] << endl;
  for (const auto& vn : asset.vns)
    ofstr << "vn " << vn[0] << ' ' << vn[1] << ' ' << vn[2] << endl;

  for (const auto& line : asset.contents)
    ofstr << line << endl;

  ofstr.close();
  return true;
}

bool AlignAsset(const Vector3d& min_xyz,
                const Vector3d& max_xyz,
                const Vector4d& free_space_ratio,
                Asset& asset) {
  const double kEpsilon = 0.0001;
  const Vector3d size = max_xyz - min_xyz;

  const double asset_normal_aspect_ratio = 
    asset.size[0] / max(kEpsilon, asset.size[1]);
  const double asset_rotated_aspect_ratio = 
    asset.size[1] / max(kEpsilon, asset.size[0]);

  const double normal_aspect_ratio = size[0] / max(kEpsilon, size[1]);

  const double normal_aspect_ratio_consistency = 
    min(asset_normal_aspect_ratio, normal_aspect_ratio) / 
    max(asset_normal_aspect_ratio, normal_aspect_ratio);
  
  const double rotated_aspect_ratio_consistency = 
    min(asset_rotated_aspect_ratio, normal_aspect_ratio) / 
    max(asset_rotated_aspect_ratio, normal_aspect_ratio);
  
  // Bottom, left, top, bottom.
  double rotation_score[4];
  rotation_score[0] = free_space_ratio[0] + normal_aspect_ratio_consistency;
  rotation_score[1] = free_space_ratio[1] + rotated_aspect_ratio_consistency;
  rotation_score[2] = free_space_ratio[2] + normal_aspect_ratio_consistency;
  rotation_score[3] = free_space_ratio[3] + rotated_aspect_ratio_consistency;
  
  const double max_score = max(max(rotation_score[0], rotation_score[1]),
                               max(rotation_score[2], rotation_score[3]));

  int num_rotations = 0;
  for (int i = 0; i < 4; ++i) {
    if (max_score == rotation_score[i]) {
      num_rotations = i;
      break;
    }
  }
  
  double xscale, yscale, zscale;
  if (num_rotations % 2 == 0) {
    xscale = size[0] / asset.size[0];
    yscale = size[1] / asset.size[1];
  } else {
    xscale = size[0] / asset.size[1];
    yscale = size[1] / asset.size[0];
  }
  zscale = (xscale + yscale) / 2.0;
  
  if (!Translate(- asset.min_xyz, asset))
    return false;

  if (num_rotations == 1) {
    if (!Rotate(90, asset))
      return false;
    if (!Translate(Vector3d(asset.size[1], 0, 0), asset))
      return false;
  } else if (num_rotations == 2) {
    if (!Rotate(180, asset))
      return false;
    if (!Translate(Vector3d(asset.size[0], asset.size[1], 0), asset))
      return false;
  } else if (num_rotations == 3) {
    if (!Rotate(270, asset))
      return false;
    if (!Translate(Vector3d(0, asset.size[0], 0), asset))
      return false;
  }

  if (!Scale(Vector3d(xscale, yscale, zscale), asset))
    return false;
  if (!Translate(min_xyz, asset))
    return false;

  return true;
}

bool Rotate(const double degree, Asset& asset) {
  const double radian = degree * M_PI / 180.0;
  Matrix2d rotation;
  rotation <<
      cos(radian), -sin(radian),
      sin(radian), cos(radian);

  for (auto& v : asset.vs) {
    Vector2d point(v[0], v[1]);
    point = rotation * point;
    v[0] = point[0];
    v[1] = point[1];
  }
  for (auto& vn : asset.vns) {
    Vector2d normal(vn[0], vn[1]);
    normal = rotation * normal;
    vn[0] = normal[0];
    vn[1] = normal[1];
  }

  return true;
}

bool Translate(const Eigen::Vector3d& motion, Asset& asset) {
  for (auto& v : asset.vs)
    v += motion;

  return true;
}

bool Scale(const double scale, Asset& asset) {
  for (auto& v : asset.vs)
    v *= scale;

  return true;
}

bool Scale(const Vector3d& scale, Asset& asset) {
  for (auto& v : asset.vs) {
    for (int a = 0; a < 3; ++a)
      v[a] *= scale[a];
  }

  return true;
}
