cmake_minimum_required(VERSION 3.10)
set(PROJECT_NAME "flutter_ocr_native")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "flutter_ocr_native_plugin")

find_package(PkgConfig REQUIRED)
pkg_check_modules(TESSERACT REQUIRED tesseract)
pkg_check_modules(LEPTONICA REQUIRED lept)

add_library(${PLUGIN_NAME} SHARED
  "ocr_plugin.cc"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED YES
)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_include_directories(${PLUGIN_NAME} PRIVATE
  ${TESSERACT_INCLUDE_DIRS}
  ${LEPTONICA_INCLUDE_DIRS}
)

target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  ${TESSERACT_LIBRARIES}
  ${LEPTONICA_LIBRARIES}
)

set(flutter_ocr_native_bundled_libraries
  ""
  PARENT_SCOPE
)
