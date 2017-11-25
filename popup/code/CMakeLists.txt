cmake_minimum_required(VERSION 3.4)

# find_package(Eigen REQUIRED)
# include(${Eigen_USE_FILE})

include_directories("/usr/local/include")
include_directories("/usr/local/include/eigen3")
set(CMAKE_CXX_FLAGS "-O3 -std=c++11 -Wno-c++11-extensions -Wno-deprecated-register")

add_executable(popup_cli popup_cli.cc asset.cc popup.cc popup_2d.cc popup_3d.cc structs.cc)
