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

function(_fd_find FDF_NAME)
  cmake_parse_arguments(FDF "" "ROOT" "PATHS" ${ARGN})
  set(SavedPrefixPath ${CMAKE_PREFIX_PATH})
  set(CMAKE_PREFIX_PATH "${FDF_PATHS}")
  find_package(${FDF_NAME} REQUIRED PATHS ${FDF_ROOT})
  set(CMAKE_PREFIX_PATH ${SavedPrefixPath})
endfunction()

function(fetch_dependency FD_NAME)
  cmake_parse_arguments(FD
    ""
    "ROOT;GIT_REPOSITORY;GIT_TAG;PACKAGE_NAME;CONFIGURATION;CMAKELIST_SUBDIRECTORY;OUT_SOURCE_DIR;OUT_BINARY_DIR"
    "GENERATE_OPTIONS;BUILD_OPTIONS"
    ${ARGN}
  )

  if($ENV{FETCH_DEPENDENCY_FAST})
    set(FastMode ON)
    message(STATUS "Checking dependency ${FD_NAME} (fast)")
  else()
    set(FastMode OFF)
    message(STATUS "Checking dependency ${FD_NAME}")
  endif()

  if(NOT FD_GIT_REPOSITORY)
    message(FATAL_ERROR "GIT_REPOSITORY must be provided.")
  endif()
  
  if(NOT FD_GIT_TAG)
    message(FATAL_ERROR "GIT_TAG must be provided.")
  endif()

  if(NOT FD_PACKAGE_NAME)
    set(FD_PACKAGE_NAME "${FD_NAME}")
  endif()

  if(NOT FD_ROOT)
    if(FETCH_DEPENDENCY_DEFAULT_ROOT)
      set(FD_ROOT "${FETCH_DEPENDENCY_DEFAULT_ROOT}")
    else()
      set(FD_ROOT "External")
    endif()
  endif()

  # If FD_ROOT is a relative path, it is interpreted as being relative to the current binary directory.
  cmake_path(IS_RELATIVE FD_ROOT IsRootRelative)
  if(IsRootRelative)
    cmake_path(APPEND CMAKE_BINARY_DIR ${FD_ROOT} OUTPUT_VARIABLE FD_ROOT)
  endif()
  message(VERBOSE "  Using root: ${FD_ROOT}")

  if(NOT FD_CONFIGURATION)
    set(FD_CONFIGURATION "Release")
  endif()

  set(ProjectDirectory "${FD_ROOT}/${FD_NAME}")
  set(ConfigureDirectory "${ProjectDirectory}/Configure")
  set(SourceDirectory "${ProjectDirectory}/Source")
  set(BuildDirectory "${ProjectDirectory}/Build")
  set(PackageDirectory "${ProjectDirectory}/Package")

  set(CommitFilePath "${ProjectDirectory}/commit.txt")
  set(OptionsFilePath "${ProjectDirectory}/options.txt")
  set(CallerFetchedFilePath "${CMAKE_BINARY_DIR}/FetchedDependencies.txt")

  list(APPEND FETCH_DEPENDENCY_PACKAGES "${PackageDirectory}")

  if(FD_OUT_SOURCE_DIR)
    set(${FD_OUT_SOURCE_DIR} "${SourceDirectory}" PARENT_SCOPE)
  endif()

  if(FD_OUT_BINARY_DIR)
    set(${FD_OUT_BINARY_DIR} "${BuildDirectory}" PARENT_SCOPE)
  endif()

  if(NOT FastMode)
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

    set(ToolchainSnippet "")
    if (CMAKE_TOOLCHAIN_FILE)
      set(ToolchainSnippet "--toolchain ${CMAKE_TOOLCHAIN_FILE}")
    endif()

    set(Options "${CMAKE_TOOLCHAIN_FILE}\n${FD_CONFIGURATION}\n${FD_GENERATE_OPTIONS}\n${FD_BUILD_OPTIONS}\n${FD_CMAKELIST_SUBDIRECTORY}")
    string(STRIP "${Options}" Options)

    set(PreviousCommit "n/a")
    if(EXISTS ${CommitFilePath})
      file(READ ${CommitFilePath} PreviousCommit)
      string(STRIP "${PreviousCommit}" PreviousCommit)
    endif()

    configure_file(
      "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/FetchDependencyProject.cmake.in"
      "${ConfigureDirectory}/CMakeLists.txt"
    )

    # Pass the prefix paths via the CMAKE_PREFIX_PATH environment variable. This avoids a warning that would otherwise be
    # generated if the dependency never actually caused CMAKE_PREFIX_PATH to be referenced.
    set(ChildPaths ${FETCH_DEPENDENCY_PACKAGES})
    if(UNIX)
      # The platform path delimiter must be used for the environment variable.
      string(REPLACE ";" ":" ChildPaths "${ChildPaths}")
    endif()
    set(ENV{CMAKE_PREFIX_PATH} ${ChildPaths})

    # Configure the dependency and execute the update target to ensure the source exists and matches what was requested
    # in GIT_TAG.
    _fd_run(COMMAND "${CMAKE_COMMAND}" -G ${CMAKE_GENERATOR} -S "${ConfigureDirectory}" -B "${BuildDirectory}")
    _fd_run(COMMAND "${CMAKE_COMMAND}" --build "${BuildDirectory}" ${ConfigurationBuildSnippet} --target ${FD_NAME}-update)

    # Extract the commit.
    _fd_run(
      COMMAND git rev-parse HEAD
      WORKING_DIRECTORY "${SourceDirectory}"
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
  endif()

  # Read the local package cache for the dependency, if it exists.
  #
  # Finding these packages here ensures that if the dependency includes them in its link interface, they'll be loaded
  # in the calling project when it needs to actually link with this dependency.
  set(LocalPackagesFilePath "${BuildDirectory}/${FD_NAME}-prefix/src/${FD_NAME}-build/FetchedDependencies.txt")
  if(EXISTS "${LocalPackagesFilePath}")
    file(STRINGS "${LocalPackagesFilePath}" LocalPackages)
    foreach(LocalPackage ${LocalPackages})
      string(REGEX REPLACE "/Package$" "" LocalName "${LocalPackage}")
      cmake_path(GET LocalName FILENAME LocalName)

      # Use the current set of package paths when finding the dependency; this is neccessary to ensure that the any
      # dependencies of the dependency that use direct find_package() calls that were satified by an earlier call to
      # fetch_dependency() will find those dependencies.
      _fd_find(${LocalName} ROOT ${LocalPackage} PATHS ${LocalPackages} ${FETCH_DEPENDENCY_PACKAGES})
    endforeach()
  endif()

  # Write the cache files.
  file(WRITE ${OptionsFilePath} "${Options}\n")
  file(WRITE ${CommitFilePath} "${CommitOutput}\n")

  # Write the most up-to-date list of packages fetched so that anything downstream of the calling project will know
  # where its dependencies were written to.
  string(REPLACE ";" "\n" CallerFetchedFileLines "${FETCH_DEPENDENCY_PACKAGES}")
  file(WRITE ${CallerFetchedFilePath} "${CallerFetchedFileLines}\n")

  _fd_find(${FD_PACKAGE_NAME} ROOT ${PackageDirectory} PATHS ${LocalPackages} ${FETCH_DEPENDENCY_PACKAGES})

  # Propagate the updated package directory list.
  set(FETCH_DEPENDENCY_PACKAGES "${FETCH_DEPENDENCY_PACKAGES}" PARENT_SCOPE)

  message(STATUS "Checking dependency ${FD_NAME} - done")
endfunction()

