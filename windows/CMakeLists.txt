cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "flutter_ocr_native")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "flutter_ocr_native_plugin")

add_library(${PLUGIN_NAME} SHARED
  "ocr_plugin.cpp"
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

target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  windowsapp
  gdiplus
  ole32
  oleaut32
)

set(flutter_ocr_native_bundled_libraries
  ""
  PARENT_SCOPE
)
