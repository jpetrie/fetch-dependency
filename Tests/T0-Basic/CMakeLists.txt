cmake_minimum_required(VERSION 3.25)
project(T0-Basic)

include(../../FetchDependency.cmake)

fetch_dependency(A
  LOCAL_SOURCE ../LibA
  CONFIGURATION Debug
)

add_executable(T00 main.cpp)
target_link_libraries(T00 A::A)

