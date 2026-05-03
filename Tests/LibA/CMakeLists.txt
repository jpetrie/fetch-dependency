cmake_minimum_required(VERSION 3.25)
project(LibA)

add_library(A STATIC)
target_sources(A
  PRIVATE
    A.cpp
  PUBLIC FILE_SET HEADERS
    FILES
      A/A.hpp
)

include(GNUInstallDirs)
install(
  TARGETS A
  EXPORT A
  FILE_SET HEADERS DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

install(
  EXPORT A
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/A
  NAMESPACE A::
  FILE AConfig.cmake
)

