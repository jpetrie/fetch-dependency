# Minimum CMake version required. Currently driven by the use of GET_MESSAGE_LOG_LEVEL:
# https://cmake.org/cmake/help/latest/command/cmake_language.html#get-message-log-level
set(FetchDependencyMinimumVersion "3.25")
if(${CMAKE_VERSION} VERSION_LESS ${FetchDependencyMinimumVersion})
  message(FATAL_ERROR "FetchDependency requires CMake ${FetchDependencyMinimumVersion} (currently using ${CMAKE_VERSION}).")
endif()

function(_fd_run)
  cmake_parse_arguments(FDR "" "WORKING_DIRECTORY;OUTPUT_VARIABLE" "COMMAND" ${ARGN})

  if(NOT FDR_WORKING_DIRECTORY)
    set(FDR_WORKING_DIRECTORY "")
  endif()

  cmake_language(GET_MESSAGE_LOG_LEVEL Level)
  if((${Level} STREQUAL "VERBOSE") OR (${Level} STREQUAL "DEBUG") OR (${Level} STREQUAL "TRACE"))
    set(EchoCommand "STDOUT")
    set(EchoOutput "ECHO_OUTPUT_VARIABLE")
    set(EchoError "ECHO_ERROR_VARIABLE")
  else()
    set(EchoCommand "NONE")
  endif()

  execute_process(
    COMMAND ${FDR_COMMAND}
    OUTPUT_VARIABLE Output
    ERROR_VARIABLE Output
    RESULT_VARIABLE Result
    WORKING_DIRECTORY "${FDR_WORKING_DIRECTORY}"
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_STRIP_TRAILING_WHITESPACE
    COMMAND_ECHO ${EchoCommand}
    ${EchoOutput}
    ${EchoError}
  )

  if(Result)
    message(FATAL_ERROR "${Output}")
  endif()

  if(FDR_OUTPUT_VARIABLE)
    set(${FDR_OUTPUT_VARIABLE} ${Output} PARENT_SCOPE)
  endif()
endfunction()

function(fetch_dependency FD_NAME)
  cmake_parse_arguments(FD "" "GIT_REPOSITORY;GIT_TAG;PACKAGE_NAME;CONFIGURATION;CMAKELIST_SUBDIRECTORY" "GENERATE_OPTIONS;BUILD_OPTIONS" ${ARGN})

  message(STATUS "Checking dependency ${FD_NAME}")

  if(NOT FD_GIT_REPOSITORY)
    message(FATAL_ERROR "GIT_REPOSITORY must be provided.")
  endif()
  
  if(NOT FD_GIT_TAG)
    message(FATAL_ERROR "GIT_TAG must be provided.")
  endif()

  if(NOT FD_PACKAGE_NAME)
    set(FD_PACKAGE_NAME "${FD_NAME}")
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
    "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/FetchDependencyProject.cmake.in"
    "${ConfigureDirectory}/CMakeLists.txt"
  )

  # Configure the dependency and execute the update target to ensure the source exists and matches what was requested
  # in GIT_TAG.
  _fd_run(COMMAND "${CMAKE_COMMAND}" -G ${CMAKE_GENERATOR} -S "${ConfigureDirectory}" -B "${BuildDirectory}")
  _fd_run(COMMAND "${CMAKE_COMMAND}" --build "${BuildDirectory}" ${ConfigurationBuildSnippet} --target ${FD_NAME}-update)

  # Extract the commit.
  _fd_run(
    COMMAND git rev-parse HEAD
    WORKING_DIRECTORY "${ProjectDirectory}/Build/${FD_NAME}-prefix/src/${FD_NAME}"
    OUTPUT_VARIABLE CommitOutput
  )

  # If the current and requested commits differ, the build step needs to run.
  set(PerformBuild NO)
  message(VERBOSE "  This revision: ${CommitOutput}")
  message(VERBOSE "  Last revision: ${PreviousCommit}")
  if(NOT "${CommitOutput}" STREQUAL "${PreviousCommit}")
    message(STATUS "  Building (revisions don't match)")
    set(PerformBuild YES)
  endif()

  # If the current and requested options differ, the build step needs to run.
  set(OptionsFilePath "${ProjectDirectory}/options.txt")
  if(NOT PerformBuild)
    if(EXISTS ${OptionsFilePath})
      file(READ ${OptionsFilePath} PreviousOptions)
      string(STRIP "${PreviousOptions}" PreviousOptions)
      if(NOT "${Options}" STREQUAL "${PreviousOptions}")
        message(STATUS "  Building (options don't match)")
        set(PerformBuild YES)
      endif()
    endif()
  endif()

  if(PerformBuild)
    _fd_run(COMMAND "${CMAKE_COMMAND}" --build "${BuildDirectory}" ${ConfigurationBuildSnippet} ${FD_BUILD_OPTIONS})
  endif()

  # Import any propagated dependencies.
  file(GLOB_RECURSE PropagatedDependencies "${FD_PREFIX}/fetched-*.cmake")
  foreach(Propagated ${PropagatedDependencies})
    include(${Propagated})
  endforeach()

  # Write the cache files.
  file(WRITE ${OptionsFilePath} "${Options}\n")
  file(WRITE ${CommitFilePath} "${CommitOutput}\n")
  file(WRITE "${ProjectDirectory}/fetched-${FD_PACKAGE_NAME}.cmake" "find_package(${FD_PACKAGE_NAME} REQUIRED HINTS \"${PackageDirectory}\" NO_DEFAULT_PATH)")

  set(SavedPrefixPath ${CMAKE_PREFIX_PATH})
  set(CMAKE_PREFIX_PATH ${PackageDirectory})
  find_package(${FD_PACKAGE_NAME} REQUIRED HINTS ${PackageDirectory} NO_DEFAULT_PATH)
  set(CMAKE_PREFIX_PATH ${SavedPrefixPath})

  message(STATUS "Checking dependency ${FD_NAME} - done")
endfunction()

