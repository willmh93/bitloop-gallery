# vcpkg_autodetect.cmake
#    - Searches for an existing vcpkg in the current directory/workspace
#    - If one isn't found, it clones vcpkg at a pinned <sha>
#    - Also picks a location for shared binary sources/cache to avoid unnecessary rebuilds
#    - then chain-load that vcpkg toolchain


# -----------------------------------------------------------------------------
# Bitloop: robust try_compile detection
#
# Visual Studio's CMake integration and some CMake modules run try_compile()
# in scratch build trees under CMakeFiles/CMakeScratch/TryCompile-... .
# In those contexts, running Bitloop discovery (which itself runs CMake) can
# recurse and/or pick up an inconsistent platform, especially with Emscripten.
#
# We therefore treat any configure happening under a scratch/TryCompile directory
# as a 'no-discovery' run. We still allow vcpkg toolchain setup to proceed.
# -----------------------------------------------------------------------------
set(BL_IN_TRY_COMPILE 0)
if (DEFINED CMAKE_IN_TRY_COMPILE AND CMAKE_IN_TRY_COMPILE)
  set(BL_IN_TRY_COMPILE 1)
elseif ("${CMAKE_BINARY_DIR}" MATCHES "CMakeFiles[/\\\\]CMakeScratch" OR
        "${CMAKE_BINARY_DIR}" MATCHES "TryCompile" OR
        "${CMAKE_CURRENT_BINARY_DIR}" MATCHES "CMakeFiles[/\\\\]CMakeScratch" OR
        "${CMAKE_CURRENT_BINARY_DIR}" MATCHES "TryCompile")
  set(BL_IN_TRY_COMPILE 1)
endif()

if (BL_IN_TRY_COMPILE)
  # Prevent nested discovery from running inside try_compile scratch projects.
  set(BITLOOP_INTERNAL_DISCOVERY_RUN 1)
endif()


# Helper: Walks up directory level looking for a ".bitloop-workspace" file
function(find_bitloop_workspace start_dir out_dir is_root_ws)
  set(limit 20)

  get_filename_component(dir "${start_dir}" REALPATH)
  set(found "")
  set(found_is_root OFF)

  while(limit GREATER 0)
    set(marker "${dir}/.bitloop-workspace")
    if (EXISTS "${marker}")
      set(found "${dir}")
      set(found_is_root ON)
      break()
    endif()

    get_filename_component(parent "${dir}" DIRECTORY)
    if (parent STREQUAL dir)
      break()
    endif()

    set(dir "${parent}")
    math(EXPR limit "${limit}-1")
  endwhile()

  # Return nearest (if any), and whether it was found
  set(${out_dir} "${found}" PARENT_SCOPE)
  set(${is_root_ws} "${found_is_root}" PARENT_SCOPE)
endfunction()


# Look for workspace root
find_bitloop_workspace(${CMAKE_SOURCE_DIR} WORKSPACE_DIR IS_ROOT_WORKSPACE)

set(VCPKG_PINNED_SHA "74e6536215718009aae747d86d84b78376bf9e09" CACHE STRING "Pinned vcpkg commit SHA")


# Potential vcpkg directory paths
set(LOCAL_VCPKG_DIR       "${CMAKE_SOURCE_DIR}/.vcpkg")
set(WORKSPACE_VCPKG_DIR   "${WORKSPACE_DIR}/.vcpkg")

# Potential vcpkg toolchain paths
set(LOCAL_VCPKG_PATH      "${LOCAL_VCPKG_DIR}/scripts/buildsystems/vcpkg.cmake")
set(WORKSPACE_VCPKG_PATH  "${WORKSPACE_VCPKG_DIR}/scripts/buildsystems/vcpkg.cmake")


# Track whether we found vcpkg
set(FOUND_LOCAL_VCPKG FALSE)
set(FOUND_WORKSPACE_VCPKG FALSE)
set(FOUND_WORKSPACE FALSE)

if (WORKSPACE_DIR AND NOT WORKSPACE_DIR STREQUAL "")
  set(FOUND_WORKSPACE TRUE)
endif()

# Choose vcpkg location (workspace preferred, then local)
set(_vcpkg_dir "")
if (EXISTS "${WORKSPACE_VCPKG_PATH}")
  set(_vcpkg_dir "${WORKSPACE_VCPKG_DIR}")
  set(FOUND_WORKSPACE_VCPKG TRUE)
elseif (EXISTS "${LOCAL_VCPKG_PATH}")
  set(_vcpkg_dir "${LOCAL_VCPKG_DIR}")
  set(FOUND_LOCAL_VCPKG TRUE)
endif()


# Clone vcpkg if not present
if (_vcpkg_dir STREQUAL "")
  # Default to workspace vcpkg if workspace found, otherwise local
  if (FOUND_WORKSPACE)
    set(_vcpkg_dir "${WORKSPACE_VCPKG_DIR}")
  else()
    set(_vcpkg_dir "${LOCAL_VCPKG_DIR}")
  endif()

  message(STATUS "No vcpkg found; cloning pinned vcpkg into: ${_vcpkg_dir}")

  find_package(Git REQUIRED)

  execute_process(
    COMMAND ${GIT_EXECUTABLE} clone https://github.com/microsoft/vcpkg.git "${_vcpkg_dir}"
    RESULT_VARIABLE _git_clone_result
  )
  if (NOT _git_clone_result EQUAL 0)
    message(FATAL_ERROR "Failed to clone vcpkg into ${_vcpkg_dir}")
  endif()

  execute_process(
    COMMAND ${GIT_EXECUTABLE} -C "${_vcpkg_dir}" checkout "${VCPKG_PINNED_SHA}"
    RESULT_VARIABLE _git_checkout_result
  )
  if (NOT _git_checkout_result EQUAL 0)
    message(FATAL_ERROR "Failed to checkout vcpkg commit ${VCPKG_PINNED_SHA}")
  endif()

  # Bootstrap vcpkg
  if (WIN32)
    execute_process(
      COMMAND cmd /c "${_vcpkg_dir}/bootstrap-vcpkg.bat"
      WORKING_DIRECTORY "${_vcpkg_dir}"
      RESULT_VARIABLE _bootstrap_result
    )
  else()
    execute_process(
      COMMAND "${_vcpkg_dir}/bootstrap-vcpkg.sh"
      WORKING_DIRECTORY "${_vcpkg_dir}"
      RESULT_VARIABLE _bootstrap_result
    )
  endif()

  if (NOT _bootstrap_result EQUAL 0)
    message(FATAL_ERROR "Failed to bootstrap vcpkg in ${_vcpkg_dir}")
  endif()
endif()


# Export environment + cache variables vcpkg expects
set(ENV{VCPKG_ROOT} "${_vcpkg_dir}")
set(VCPKG_ROOT "${_vcpkg_dir}" CACHE PATH "" FORCE)

# Pick a root location relative to the determined VCPKG_ROOT
get_filename_component(_root_dir "${_vcpkg_dir}/.." REALPATH)

set(_cache_dir      "${_root_dir}/.vcpkg-cache")

file(MAKE_DIRECTORY "${_cache_dir}")

set(ENV{VCPKG_DEFAULT_BINARY_CACHE}  "${_cache_dir}")
set(ENV{VCPKG_BINARY_SOURCES}        "clear;files,${_cache_dir},readwrite")


# ---- Manifest Compiler (merge child vcpkg.json into one generated manifest) ----

set(BL_MERGED_MANIFEST_DIR "${CMAKE_BINARY_DIR}/_vcpkg_merged")
file(MAKE_DIRECTORY "${BL_MERGED_MANIFEST_DIR}")

# Avoid recursion if this toolchain loader is hit during the discovery configure
# OR while we are inside a try_compile scratch project.
if (BL_IN_TRY_COMPILE OR (DEFINED BITLOOP_INTERNAL_DISCOVERY_RUN AND BITLOOP_INTERNAL_DISCOVERY_RUN))
  set(BL_CHILD_MANIFESTS "")
else()
  message(STATUS "Running bitloop project discovery phase")

  set(_bl_discovery_build_dir "${CMAKE_BINARY_DIR}/_bitloop_discovery")
  set(_bl_discovery_out_file  "${_bl_discovery_build_dir}/discovered_manifests.cmake")
  file(MAKE_DIRECTORY "${_bl_discovery_build_dir}")

  set(_bl_discovery_toolchain "${_root_dir}/tooling/cmake/toolchain/discovery_toolchain.cmake")

  set(_cmd
    ${CMAKE_COMMAND}
    -S ${_root_dir}
    -B ${_bl_discovery_build_dir}
    -DBITLOOP_DISCOVERY=ON
    -DBITLOOP_INTERNAL_DISCOVERY_RUN=1
    -DBITLOOP_DISCOVERY_OUT=${_bl_discovery_out_file}
    -DCMAKE_TOOLCHAIN_FILE=${_bl_discovery_toolchain}
  )

  # Preserve generator/toolset/platform so the discovery configure matches the real one.
  if (CMAKE_GENERATOR)
    list(APPEND _cmd -G "${CMAKE_GENERATOR}")
  endif()
  if (CMAKE_GENERATOR_PLATFORM)
    list(APPEND _cmd -A "${CMAKE_GENERATOR_PLATFORM}")
  endif()
  if (CMAKE_GENERATOR_TOOLSET)
    list(APPEND _cmd -T "${CMAKE_GENERATOR_TOOLSET}")
  endif()

  execute_process(COMMAND ${_cmd} RESULT_VARIABLE _r)
  if (NOT _r EQUAL 0)
    message(FATAL_ERROR "Bitloop discovery configure failed (code=${_r}).\nCommand: ${_cmd}")
  endif()

  if (NOT EXISTS "${_bl_discovery_out_file}")
    message(FATAL_ERROR "Bitloop: discovery output missing: ${_bl_discovery_out_file}")
  endif()

  include("${_bl_discovery_out_file}") # -> defines BL_CHILD_MANIFESTS

  if (BL_CHILD_MANIFESTS)
    list(REMOVE_DUPLICATES BL_CHILD_MANIFESTS)
    list(SORT BL_CHILD_MANIFESTS)
  endif()
endif()


# Guard against foreign superprojects (but NOT during try_compile scratch projects).
if(NOT BL_IN_TRY_COMPILE AND NOT "${CMAKE_SOURCE_DIR}" STREQUAL "${_root_dir}")
  return()
endif()

# Ensure we only do this once per configure
if(DEFINED BL_VCPKG_MERGED_MANIFEST_DONE)
  return()
endif()
set(BL_VCPKG_MERGED_MANIFEST_DONE 1)

set(BL_MERGED_MANIFEST_DIR "${CMAKE_BINARY_DIR}/_vcpkg_merged")
file(MAKE_DIRECTORY "${BL_MERGED_MANIFEST_DIR}")

include("${_root_dir}/tooling/cmake/toolchain/merge_vcpkg_manifests.cmake")
bl_merge_vcpkg_manifests(
  ROOT_MANIFEST   "${_root_dir}/vcpkg.json"
  CHILD_MANIFESTS "${BL_CHILD_MANIFESTS}"
  OUT_DIR         "${BL_MERGED_MANIFEST_DIR}"
  MODE            "UNION"
)

# Point vcpkg at the generated manifest (must be set before including vcpkg.cmake)
set(VCPKG_MANIFEST_DIR "${BL_MERGED_MANIFEST_DIR}" CACHE PATH "" FORCE)
set(VCPKG_MANIFEST_INSTALL ON CACHE BOOL "" FORCE)

# Finally, load vcpkg toolchain
include("${_vcpkg_dir}/scripts/buildsystems/vcpkg.cmake")
