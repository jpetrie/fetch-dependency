cmake_minimum_required(VERSION 3.25)
project(LibB)

add_library(B STATIC)
target_sources(B
  PRIVATE
    B.cpp
  PUBLIC FILE_SET HEADERS
    FILES
      B/B.hpp
)

include(../../FetchDependency.cmake)
fetch_dependency(A
  LOCAL_SOURCE ../LibA
  CONFIGURATION Debug
)

target_link_libraries(B A::A)

include(GNUInstallDirs)
install(
  TARGETS B
  EXPORT B
  FILE_SET HEADERS DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

install(
  EXPORT B
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/B
  NAMESPACE B::
  FILE BConfig.cmake
)

