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
#  - `GENERATE_OPTIONS <options>`: Pass the remaining options to CMake when generating the dependency.
#  - `BUILD_OPTIONS <options>`: Pass the remaining options to CMake when building the dependency. Note that these
#     options are for CMake's `--build` command specifically.
#  - `CMAKE_OPTIONS <options>`: Deprecated; please use `GENERATE_OPTIONS` instead. This option will be removed in a
#     future version.

function(fetch_dependency FD_NAME)
  cmake_parse_arguments(FD "" "GIT_REPOSITORY;GIT_TAG;CONFIGURATION" "GENERATE_OPTIONS;BUILD_OPTIONS;CMAKE_OPTIONS" ${ARGN})

  message("-- Checking dependency ${FD_NAME}")

  if(NOT FD_GIT_REPOSITORY)
    message(FATAL_ERROR "GIT_REPOSITORY must be provided.")
  endif()
  
  if(NOT FD_GIT_TAG)
    message(FATAL_ERROR "GIT_TAG must be provided.")
  endif()

  if(FD_CMAKE_OPTIONS)
    message(AUTHOR_WARNING "CMAKE_OPTIONS is deprecated in favor of GENERATE_OPTIONS; please update your projects accordingly.")
    if(NOT FD_GENERATE_OPTIONS)
      set(FD_GENERATE_OPTIONS ${FD_CMAKE_OPTIONS})
    endif()
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

  set(Version "${FD_CONFIGURATION}\n${FD_GENERATE_OPTIONS}\n${FD_BUILD_OPTIONS}")
  string(STRIP "${Version}" Version)

  set(ProjectDirectory "${FD_PREFIX}/Projects/${FD_NAME}")
  set(VersionFilePath "${ProjectDirectory}/version.txt")
  set(PerformFetch YES)
  if(EXISTS ${VersionFilePath})
    # If the version file exists, make sure the tag inside it matches the requested dependency tag. If it does,
    # early-out because the dependency exists and is up-to-date.
    file(READ ${VersionFilePath} ConfiguredVersion)
    string(STRIP "${ConfiguredVersion}" ConfiguredVersion)
    if("${Version}" STREQUAL "${ConfiguredVersion}")
      message("Dependency '${FD_NAME}' is up to date.")
      set(PerformFetch NO)
    else()
      message("Dependency '${FD_NAME}' is out of date.")
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
      COMMAND ${CMAKE_COMMAND} -G ${CMAKE_GENERATOR} -S ${ConfigureDirectory} -B ${BuildDirectory}
      OUTPUT_VARIABLE ConfigureOutput
      ERROR_VARIABLE ConfigureOutput
      RESULT_VARIABLE ConfigureResult
    )

    if(ConfigureResult)
      message(FATAL_ERROR "${ConfigureOutput}")
    endif()

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

  # Cache the configured version.
  file(WRITE ${VersionFilePath} "${Version}\n")

  set(SavedPrefixPath ${CMAKE_PREFIX_PATH})
  set(CMAKE_PREFIX_PATH ${PackageDirectory})
  find_package(${FD_NAME} REQUIRED HINTS ${PackageDirectory} NO_DEFAULT_PATH)
  set(CMAKE_PREFIX_PATH ${SavedPrefixPath})

  message("-- Checking dependency ${FD_NAME} - done")
endfunction()

