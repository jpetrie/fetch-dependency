cmake_minimum_required(VERSION 3.25)
project(T1-Nested)

include(../../FetchDependency.cmake)

fetch_dependency(B
  LOCAL_SOURCE ../LibB
  CONFIGURATION Debug
)

add_executable(T01 main.cpp)
target_link_libraries(T01 B::B)

