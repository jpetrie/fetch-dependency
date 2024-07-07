# fetch_dependency(<name> GIT_REPOSITORY <repository> GIT_TAG <tag> <options>...)
#
# Download, configure, build and locally install a dependency named `<name>`. The name is used to create the directory
# where the dependency's source and artifacts will be stored and doesn't need to correspond to the official name of the
# dependency. The dependency is cloned from the specified Git `<repository>` and the specific `<tag>` is checked out; 
# both parameters are required.
#
# If the global FETCH_DEPENDENCY_PREFIX is set, the dependency will be cloned beneath that directory. Otherwise, the
# dependency will be cloned underneath CMAKE_BINARY_DIR/External. Using FETCH_DEPENDENCY_PREFIX can be useful when a
# project has many configurations, as it will allow all configurations to share the dependency clones.
#
# Additional supported options for fetch_dependency() are:
#
#  - `CMAKE_OPTIONS <options>`: Pass the remaining options along to CMake when configuring the dependency.
#  - `CMAKE_BUILD_OPTIONS <options>`: Pass the remaining options along to CMake when building the dependency.

function(fetch_dependency FD_NAME)
  cmake_parse_arguments(FD "" "GIT_REPOSITORY;GIT_TAG" "CMAKE_OPTIONS;CMAKE_BUILD_OPTIONS" ${ARGN})

  message("Fetching dependency '${FD_NAME}'...")

  if(NOT FD_GIT_REPOSITORY)
    message(FATAL_ERROR "GIT_REPOSITORY must be provided.")
  endif()
  
  if(NOT FD_GIT_TAG)
    message(FATAL_ERROR "GIT_TAG must be provided.")
  endif()

  if(FETCH_DEPENDENCY_PREFIX)
    set(FD_PREFIX "${FETCH_DEPENDENCY_PREFIX}")
  else()
    set(FD_PREFIX "${CMAKE_BINARY_DIR}/External")
  endif()

  set(ProjectDirectory "${FD_PREFIX}/Projects/${FD_NAME}")
  set(VersionFilePath "${ProjectDirectory}/version.txt")
  set(PerformFetch YES)
  if(EXISTS ${VersionFilePath})
    # If the version file exists, make sure the tag inside it matches the requested dependency tag. If it does,
    # early-out because the dependency exists and is up-to-date.
    file(READ ${VersionFilePath} ExistingVersion)
    string(STRIP ${ExistingVersion} ExistingVersion)
    if(${FD_GIT_TAG} STREQUAL ${ExistingVersion})
      message("Requested version '${FD_GIT_TAG}' matches existing version '${ExistingVersion}', skipping fetch.")
      set(PerformFetch NO)
    endif()
  endif()

  set(ConfigureDirectory "${ProjectDirectory}/Configure")
  set(BuildDirectory "${ProjectDirectory}/Build")
  set(PackageDirectory "${FD_PREFIX}/Packages")

  if(PerformFetch)
    configure_file(
      ${CMAKE_CURRENT_FUNCTION_LIST_DIR}/FetchDependencyProject.cmake.in
      ${ConfigureDirectory}/CMakeLists.txt
    )

    execute_process(
      COMMAND ${CMAKE_COMMAND} -G ${CMAKE_GENERATOR} -S ${ConfigureDirectory} -B ${BuildDirectory} ${FD_CMAKE_OPTIONS}
      OUTPUT_QUIET
      RESULT_VARIABLE ConfigureResult
    )

    if(ConfigureResult)
      message(FATAL_ERROR "Configuration failed (${ConfigureResult}).")
    endif()

    execute_process(
      COMMAND ${CMAKE_COMMAND} --build ${BuildDirectory} ${FD_CMAKE_BUILD_OPTIONS}
      OUTPUT_QUIET
      RESULT_VARIABLE BuildResult
    )

    if(BuildResult)
      message(FATAL_ERROR "Build failed (${BuildResult}).")
    endif()

    # Write the configured tag into the version file.
    file(WRITE ${VersionFilePath} "${FD_GIT_TAG}\n")
  endif()

  set(SavedPrefixPath ${CMAKE_PREFIX_PATH})
  set(CMAKE_PREFIX_PATH ${PackageDirectory})
  find_package(${FD_NAME} REQUIRED HINTS ${PackageDirectory} NO_DEFAULT_PATH)
  set(CMAKE_PREFIX_PATH ${SavedPrefixPath})
endfunction()

