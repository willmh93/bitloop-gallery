# bitloop-gallery/CMakeLists.txt

cmake_minimum_required(VERSION 3.21)
project(BitloopGallery  LANGUAGES CXX)

add_subdirectory(bitloop)

bitloop_new_project(Gallery)
bitloop_add_dependency(Gallery  projects/Mandelbrot)
bitloop_add_dependency(Gallery  bitloop/examples)
bitloop_finalize()
