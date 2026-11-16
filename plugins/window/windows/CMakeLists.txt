cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "window")
project(${PROJECT_NAME} LANGUAGES CXX)
cmake_policy(VERSION 3.14...3.25)

set(PLUGIN_NAME "window_plugin")

list(APPEND PLUGIN_SOURCES
  "running_instance.cpp"
  "running_instance.h"
  "window_controller.cpp"
  "window_controller.h"
  "window_plugin.cpp"
  "window_plugin.h"
  "window_style.cpp"
  "window_style.h"
)

add_library(${PLUGIN_NAME} SHARED
  "include/window/window_plugin_c_api.h"
  "window_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin dwmapi)

set(window_bundled_libraries
  ""
  PARENT_SCOPE
)

if(BUILD_TESTING)
  enable_testing()
  add_executable(window_controller_test
    "test/window_controller_test.cpp"
    "window_controller.cpp"
    "window_style.cpp"
    "running_instance.cpp"
  )
  apply_standard_settings(window_controller_test)
  target_include_directories(window_controller_test PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}")
  target_link_libraries(window_controller_test PRIVATE dwmapi ole32)
  add_test(NAME window_controller_test COMMAND window_controller_test)
endif()
