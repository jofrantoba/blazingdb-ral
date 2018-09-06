#=============================================================================
# Copyright 2018 BlazingDB, Inc.
#     Copyright 2018 Percy Camilo Triveño Aucahuasi <percy@blazingdb.com>
#=============================================================================

# - Find GPU Open Analytics Initiative (GoAi) libgdf (libgdf.a)
# LIBGDF_ROOT hints the location
#
# This module defines
# LIBGDF_FOUND
# LIBGDF_INCLUDEDIR Preferred include directory e.g. <prefix>/include
# LIBGDF_INCLUDE_DIR, directory containing libgdf headers
# LIBGDF_LIBS, libgdf libraries
# LIBGDF_LIBDIR, directory containing libgdf libraries
# LIBGDF_STATIC_LIB, path to libgdf.a
# gdf - static library

# If LIBGDF_ROOT is not defined try to search in the default system path
if ("${LIBGDF_ROOT}" STREQUAL "")
    set(LIBGDF_ROOT "/usr")
endif()

set(LIBGDF_SEARCH_LIB_PATH
  ${LIBGDF_ROOT}/lib
  ${LIBGDF_ROOT}/lib/x86_64-linux-gnu
  ${LIBGDF_ROOT}/lib64
  ${LIBGDF_ROOT}/build
)

set(LIBGDF_SEARCH_INCLUDE_DIR
  ${LIBGDF_ROOT}/include/gdf
)

find_path(LIBGDF_INCLUDE_DIR gdf.h
    PATHS ${LIBGDF_SEARCH_INCLUDE_DIR}
    NO_DEFAULT_PATH
    DOC "Path to libgdf headers"
)

find_library(LIBGDF_LIBS NAMES gdf
    PATHS ${LIBGDF_SEARCH_LIB_PATH}
    NO_DEFAULT_PATH
    DOC "Path to libgdf library"
)

# TODO percy uncomment this when libgdf can be built as static lib too
#find_library(LIBGDF_STATIC_LIB NAMES libgdf.a
#    PATHS ${LIBGDF_SEARCH_LIB_PATH}
#    NO_DEFAULT_PATH
#    DOC "Path to libgdf static library"
#)

# TODO percy uncomment this when libgdf can be built as static lib too
#if (NOT LIBGDF_LIBS OR NOT LIBGDF_STATIC_LIB)
if (NOT LIBGDF_LIBS)
    message(FATAL_ERROR "libgdf includes and libraries NOT found. "
      "Looked for headers in ${LIBGDF_SEARCH_INCLUDE_DIR}, "
      "and for libs in ${LIBGDF_SEARCH_LIB_PATH}")
    set(LIBGDF_FOUND FALSE)
else()
    set(LIBGDF_INCLUDEDIR ${LIBGDF_ROOT}/include/)
    set(LIBGDF_LIBDIR ${LIBGDF_ROOT}/build) # TODO percy make this part cross platform
    set(LIBGDF_FOUND TRUE)
    add_library(gdf STATIC IMPORTED)
    set_target_properties(gdf PROPERTIES IMPORTED_LOCATION "${LIBGDF_STATIC_LIB}")
endif ()

mark_as_advanced(
  LIBGDF_FOUND
  LIBGDF_INCLUDEDIR
  LIBGDF_INCLUDE_DIR
  LIBGDF_LIBS
  LIBGDF_STATIC_LIB
  gdf
)
