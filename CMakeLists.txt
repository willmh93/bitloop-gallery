# bitloop-gallery/CMakeLists.txt

cmake_minimum_required(VERSION 3.21)
project(BitloopGallery  LANGUAGES CXX)

add_subdirectory(bitloop)

# flags (applied only if project open as root)
set(BITLOOP_DEV_MODE TRUE)

bitloop_new_project(Gallery)
bitloop_add_dependency(Gallery  projects/Mandelbrot)
bitloop_add_dependency(Gallery  projects/ThreeBodyProblem)
#bitloop_add_dependency(Gallery  projects/ChatGPT_Test)
bitloop_add_dependency(Gallery  bitloop/examples)

#bitloop_show(Cardioid)

bitloop_finalize()
