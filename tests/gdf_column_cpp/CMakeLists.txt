set(gdf_column_cpp_test_SRCS
    gdf_column_cpp_test.cu
    ${CMAKE_SOURCE_DIR}/tests/utilities/gdf_column_cpp_utilities.cu
)


#configure_test(gdf_column_cpp_test "${gdf_column_cpp_test_SRCS}")

set(test_name "gdf_column_cpp_test")

project(${test_name} CXX CUDA)

set(test_sources
    ${CMAKE_CURRENT_SOURCE_DIR}/gdf_column_cpp_test.cu
    ${CMAKE_SOURCE_DIR}/src/GDFColumn.cu
    ${CMAKE_SOURCE_DIR}/src/GDFCounter.cu
    ${CMAKE_SOURCE_DIR}/src/cuDF/Allocator.cpp
    ${CMAKE_SOURCE_DIR}/src/FreeMemory.cpp)

add_executable(${test_name} ${test_sources})

target_include_directories(${test_name} PUBLIC ${CMAKE_SOURCE_DIR}/src)

target_link_libraries(${test_name}
                      ${CUDA_CUDA_LIBRARY}
                      GTest::GTest
                      GTest::Main
                      cudart
                      ${LIBGDF_STATIC_LIB}
                      NVCategory
                      NVStrings
                      rmm)

set_target_properties(${test_name} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/gtests/")

add_test(NAME ${test_name} COMMAND ${test_name})
