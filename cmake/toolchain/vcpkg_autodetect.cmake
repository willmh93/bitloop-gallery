# Purpose: pick a vcpkg location early, then chain-load the real vcpkg toolchain

set(VCPKG_PINNED_SHA "74e6536215718009aae747d86d84b78376bf9e09" CACHE STRING "Pinned vcpkg commit SHA")


# prioritize BITLOOP_ROOT for a single souce of truth (if installed)
#if (DEFINED ENV{VCPKG_ROOT} AND EXISTS "$ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake")
#  set(_vcpkg_dir "$ENV{VCPKG_ROOT}")
#  message(STATUS "vcpkg toolchain detected at: ${_vcpkg_dir}")
#
#elseif (DEFINED ENV{BITLOOP_ROOT} AND EXISTS "$ENV{BITLOOP_ROOT}/vcpkg/scripts/buildsystems/vcpkg.cmake")

message(STATUS "Searching for vcpkg...")

message(STATUS "Checking... ${CMAKE_SOURCE_DIR}/vcpkg/scripts/buildsystems/vcpkg.cmake")

if (EXISTS "${CMAKE_SOURCE_DIR}/vcpkg/scripts/buildsystems/vcpkg.cmake")
  set(_vcpkg_dir "${CMAKE_SOURCE_DIR}/vcpkg")
  message(STATUS "vcpkg toolchain detected at: ${_vcpkg_dir}")

elseif (EXISTS "${CMAKE_SOURCE_DIR}/bitloop/vcpkg/scripts/buildsystems/vcpkg.cmake")
  set(_vcpkg_dir "${CMAKE_SOURCE_DIR}/bitloop/vcpkg")
  message(STATUS "vcpkg toolchain detected at: ${_vcpkg_dir}")

elseif (DEFINED ENV{BITLOOP_ROOT} AND EXISTS "$ENV{BITLOOP_ROOT}/vcpkg/scripts/buildsystems/vcpkg.cmake")
  set(_vcpkg_dir "$ENV{BITLOOP_ROOT}/vcpkg")
  message(STATUS "vcpkg toolchain detected at: ${_vcpkg_dir}")

else()
  message(STATUS "WARNING: vcpkg not found.  To enable shared builds across all bitloop projects, it's reccommended you")
  message(STATUS "                           set user environment variable BITLOOP_ROOT to ")


  find_package(Git QUIET)
  if(GIT_FOUND)
    set(fetch_vcpkg_dir "${CMAKE_SOURCE_DIR}/vcpkg")

    message(STATUS "Cloning pinned vcpkg @ ${VCPKG_PINNED_SHA}")
    execute_process(
      COMMAND "${GIT_EXECUTABLE}" clone https://github.com/microsoft/vcpkg "${fetch_vcpkg_dir}"
      RESULT_VARIABLE _git_clone_rv
      OUTPUT_QUIET ERROR_QUIET
    )

    if(NOT _git_clone_rv EQUAL 0)
      message(STATUS "[vcpkg] git clone failed, falling back to archive download")
      set(GIT_FOUND OFF)
    else()
      # switch to correct sha
      execute_process(
        COMMAND "${GIT_EXECUTABLE}" -C "${fetch_vcpkg_dir}" checkout ${VCPKG_PINNED_SHA}
        RESULT_VARIABLE _git_co_rv
        OUTPUT_QUIET ERROR_QUIET
      )
      if(NOT _git_co_rv EQUAL 0)
        message(FATAL_ERROR "[vcpkg] Failed to checkout ${VCPKG_PINNED_SHA}")
      endif()

      set(_vcpkg_dir ${fetch_vcpkg_dir})
    endif()
  endif()


endif()

# 5) Export and chain-load
set(ENV{VCPKG_ROOT} "${_vcpkg_dir}")
set(VCPKG_ROOT "${_vcpkg_dir}" CACHE PATH "" FORCE)
set(_vcpkg_toolchain "${_vcpkg_dir}/scripts/buildsystems/vcpkg.cmake")

#if (DEFINED ENV{BITLOOP_ROOT})
#  set(OVERLAY_PORTS_PATH "$ENV{BITLOOP_ROOT}/vcpkg-ports/ports")
#  list(APPEND VCPKG_OVERLAY_PORTS ${OVERLAY_PORTS_PATH})
#endif()


message(STATUS "Using vcpkg at: ${_vcpkg_dir}")
include("${_vcpkg_toolchain}")
