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
#  - `CONFIGURATION <name>`: Use the named configuration instead of the default for the dependency. Specifying a
#     configuration via this option will work correctly regardless of whether or not the generator in use is a single-
#     or multi-configuration generator. If not specified, "Release" is assumed.
#  - `GENERATE_OPTIONS <options>`: Pass the following options to CMake when generating the dependency.
#  - `BUILD_OPTIONS <options>`: Pass the following options to CMake when building the dependency. Note that these
#     options are for CMake's `--build` command specifically.
#  - `CMAKELIST_SUBDIRECTORY <path>`: The path to the directory containing the `CMakeLists.txt` for the dependency,
#     if it is not located at the root. Always interpreted as a path relative to the dependency root.

function(fetch_dependency FD_NAME)
  cmake_parse_arguments(FD "" "GIT_REPOSITORY;GIT_TAG;CONFIGURATION;CMAKELIST_SUBDIRECTORY" "GENERATE_OPTIONS;BUILD_OPTIONS" ${ARGN})

  message("-- Checking dependency ${FD_NAME}")

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

  if(NOT FD_CONFIGURATION)
    set(FD_CONFIGURATION "Release")
  endif()

  get_property(IsMultiConfig GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
  set(ConfigurationBuildSnippet "")
  set(ConfigurationGenerateSnippet "")
  if(IsMultiConfig)
    # Multi-configuration generators need to specify the configuration during the build step.
    set(ConfigurationBuildSnippet "--config ${FD_CONFIGURATION}")
  else()
    # Single-configuration generators can simply inject a value for CMAKE_BUILD_TYPE during configuration.
    # Note that this variable is only actually used in the configure_file() template.
    set(ConfigurationGenerateSnippet "-DCMAKE_BUILD_TYPE=${FD_CONFIGURATION}")
  endif()

  set(ProjectDirectory "${FD_PREFIX}/Projects/${FD_NAME}")
  set(BuildDirectory "${ProjectDirectory}/Build")
  set(PackageDirectory "${FD_PREFIX}/Packages")

  set(Options "${FD_CONFIGURATION}\n${FD_GENERATE_OPTIONS}\n${FD_BUILD_OPTIONS}\n${FD_CMAKELIST_SUBDIRECTORY}")
  string(STRIP "${Options}" Options)

  set(CommitFilePath "${ProjectDirectory}/commit.txt")
  set(PreviousCommit "n/a")
  if(EXISTS ${CommitFilePath})
    file(READ ${CommitFilePath} PreviousCommit)
    string(STRIP "${PreviousCommit}" PreviousCommit)
  endif()

  set(ConfigureDirectory "${ProjectDirectory}/Configure")
  configure_file(
    ${CMAKE_CURRENT_FUNCTION_LIST_DIR}/FetchDependencyProject.cmake.in
    ${ConfigureDirectory}/CMakeLists.txt
  )

  # Configure the dependency and execute the update target to ensure the source exists and matches what was requested
  # in GIT_TAG.
  execute_process(
    COMMAND ${CMAKE_COMMAND} -G ${CMAKE_GENERATOR} -S ${ConfigureDirectory} -B ${BuildDirectory}
    OUTPUT_VARIABLE ConfigureOutput
    ERROR_VARIABLE ConfigureOutput
    RESULT_VARIABLE ConfigureResult
  )

  if(ConfigureResult)
    message(FATAL_ERROR "${ConfigureOutput}")
  endif()

  execute_process(
    COMMAND ${CMAKE_COMMAND} --build ${BuildDirectory} ${ConfigurationBuildSnippet} --target ${FD_NAME}-update
    OUTPUT_VARIABLE BuildOutput
    ERROR_VARIABLE BuildOutput
    RESULT_VARIABLE BuildResult
  )

  if(BuildResult)
    message(FATAL_ERROR "${BuildOutput}")
  endif()

  # Extract the commit.
  execute_process(
    COMMAND git rev-parse HEAD
    WORKING_DIRECTORY ${ProjectDirectory}/Build/${FD_NAME}-prefix/src/${FD_NAME}
    OUTPUT_VARIABLE CommitOutput
    ERROR_VARIABLE CommitOutput
    RESULT_VARIABLE CommitResult
  )

  if(CommitResult)
    message(FATAL_ERROR "${CommitOutput}")
  endif()

  # If the current and requested commits differ, the build step needs to run.
  set(PerformBuild NO)
  string(STRIP "${CommitOutput}" CommitOutput)
  message("   HEAD is at ${CommitOutput}.")
  if(NOT "${CommitOutput}" STREQUAL "${PreviousCommit}")
    message("   Building because the previous HEAD was ${PreviousCommit}.")
    set(PerformBuild YES)
  endif()

  # If the current and requested options differ, the build step needs to run.
  set(OptionsFilePath "${ProjectDirectory}/options.txt")
  if(NOT PerformBuild)
    if(EXISTS ${OptionsFilePath})
      file(READ ${OptionsFilePath} PreviousOptions)
      string(STRIP "${PreviousOptions}" PreviousOptions)
      if(NOT "${Options}" STREQUAL "${PreviousOptions}")
        message("   Building because the dependency options have changed.") 
        set(PerformBuild YES)
      endif()
    endif()
  endif()

  if(PerformBuild)
    execute_process(
      COMMAND ${CMAKE_COMMAND} --build ${BuildDirectory} ${ConfigurationBuildSnippet} ${FD_BUILD_OPTIONS}
      OUTPUT_VARIABLE BuildOutput
      ERROR_VARIABLE BuildOutput
      RESULT_VARIABLE BuildResult
    )

    if(BuildResult)
      message(FATAL_ERROR "${BuildOutput}")
    endif()
  endif()

  # Write the cache files.
  file(WRITE ${OptionsFilePath} "${Options}\n")
  file(WRITE ${CommitFilePath} "${CommitOutput}\n")

  set(SavedPrefixPath ${CMAKE_PREFIX_PATH})
  set(CMAKE_PREFIX_PATH ${PackageDirectory})
  find_package(${FD_NAME} REQUIRED HINTS ${PackageDirectory} NO_DEFAULT_PATH)
  set(CMAKE_PREFIX_PATH ${SavedPrefixPath})

  message("-- Checking dependency ${FD_NAME} - done")
endfunction()

