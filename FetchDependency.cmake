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
    "FETCH_ONLY"
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
  set(StateDirectory "${ProjectDirectory}/State")
  set(SourceDirectory "${ProjectDirectory}/Source")
  set(BuildDirectory "${ProjectDirectory}/Build")
  set(PackageDirectory "${ProjectDirectory}/Package")

  # The options file tracks the fetch_dependency() parameters that impact build or configuration in order to determine
  # when a rebuild is required.
  set(OptionsFilePath "${StateDirectory}/options.txt")

  # The manifest file contains the package directories of every dependency fetched for the calling project so far.
  set(ManifestFile "FetchedDependencies.txt")
  set(ManifestFilePath "${CMAKE_BINARY_DIR}/${ManifestFile}")

  list(APPEND FETCH_DEPENDENCY_PACKAGES "${PackageDirectory}")

  if(FD_OUT_SOURCE_DIR)
    set(${FD_OUT_SOURCE_DIR} "${SourceDirectory}" PARENT_SCOPE)
  endif()

  if(FD_OUT_BINARY_DIR)
    set(${FD_OUT_BINARY_DIR} "${BuildDirectory}" PARENT_SCOPE)
  endif()

  # Ensure the source directory exists and is up to date.
  if(NOT IS_DIRECTORY "${SourceDirectory}")
    _fd_run(COMMAND git clone ${FD_GIT_REPOSITORY} "${SourceDirectory}")
  else()
    # If the directory exists, before doing anything else, make sure the it is in a clean state. Any local changes are
    # assumed to be intentional and prevent attempts to update.
    _fd_run(COMMAND git status --porcelain WORKING_DIRECTORY "${SourceDirectory}" OUTPUT_VARIABLE GitStatus)
    if(NOT "${GitStatus}" STREQUAL "")
      message(AUTHOR_WARNING "Source has local changes; update suppressed (${SourceDirectory}).")
    else()
      _fd_run(COMMAND git fetch --tags WORKING_DIRECTORY "${SourceDirectory}")
    endif()
  endif()

  set(BuildNeededMessage "")
  _fd_run(COMMAND git rev-parse HEAD^0 WORKING_DIRECTORY "${SourceDirectory}" OUTPUT_VARIABLE ExistingCommit)
  _fd_run(COMMAND git rev-parse ${FD_GIT_TAG}^0 WORKING_DIRECTORY "${SourceDirectory}" OUTPUT_VARIABLE RequiredCommit)
  if(NOT "${ExistingCommit}" STREQUAL "${RequiredCommit}")
    _fd_run(COMMAND git -c advice.detachedHead=false checkout ${FD_GIT_TAG} WORKING_DIRECTORY "${SourceDirectory}")
    set(BuildNeededMessage "versions differ")
  endif()

  set(RequiredOptions "PACKAGE_NAME=${FD_PACKAGE_NAME}\nTOOLCHAIN=${CMAKE_TOOLCHAIN_FILE}\nCONFIGURATION=${FD_CONFIGURATION}\nCONFIGURE_OPTIONS=${FD_GENERATE_OPTIONS}\nBUILD_OPTIONS=${FD_BUILD_OPTIONS}\nCMAKELIST_SUBDIRECTORY=${FD_CMAKELIST_SUBDIRECTORY}\n")
  string(STRIP "${RequiredOptions}" RequiredOptions)
  if("${BuildNeededMessage}" STREQUAL "")
    # Assume the options differ, and clear this string only if they actually match.
    set(BuildNeededMessage "options differ")
    if(EXISTS ${OptionsFilePath})
      file(READ ${OptionsFilePath} ExistingOptions)
      string(STRIP "${ExistingOptions}" ExistingOptions)
      if("${ExistingOptions}" STREQUAL "${RequiredOptions}")
        set(BuildNeededMessage "")
      endif()
    endif()
  endif()
  file(WRITE ${OptionsFilePath} "${RequiredOptions}\n")

  if(NOT FD_FETCH_ONLY)
    if(NOT FastMode)
      if(NOT "${BuildNeededMessage}" STREQUAL "")
        message(STATUS "Building (${BuildNeededMessage}).")

        list(APPEND ConfigureArguments "-DCMAKE_INSTALL_PREFIX=${PackageDirectory}")
        list(APPEND ConfigureArguments ${FD_GENERATE_OPTIONS})
        list(APPEND BuildArguments ${FD_BUILD_OPTIONS})

        if(CMAKE_TOOLCHAIN_FILE)
          string(APPEND ConfigureArguments " --toolchain ${CMAKE_TOOLCHAIN_FILE}")
        endif()

        # Configuration handling differs for single- versus multi-config generators.
        get_property(IsMultiConfig GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
        if(IsMultiConfig)
          list(APPEND BuildArguments "--config ${FD_CONFIGURATION}")
        else()
          list(APPEND ConfigureArguments "-DCMAKE_BUILD_TYPE=${FD_CONFIGURATION}")
        endif()

        # When invoking CMake for the builds, the package paths are passed via the CMAKE_PREFIX_PATH environment variable.
        # This avoids a warning that would otherwise be generated if the dependency never actually caused
        # CMAKE_PREFIX_PATH to be referenced. Note that the platform path delimiter must be used to separate individual
        # paths in the environment variable.
        set(Packages ${FETCH_DEPENDENCY_PACKAGES})
        if(UNIX)
          string(REPLACE ";" ":" Packages "${Packages}")
        endif()
        set(ENV{CMAKE_PREFIX_PATH} ${Packages})

        # Configure, build and install the dependency.
        _fd_run(COMMAND "${CMAKE_COMMAND}" -G ${CMAKE_GENERATOR} -S "${SourceDirectory}/${FD_CMAKELIST_SUBDIRECTORY}" -B "${BuildDirectory}" ${ConfigureArguments})
        _fd_run(COMMAND "${CMAKE_COMMAND}" --build "${BuildDirectory}" --target install ${BuildArguments})
      endif()
    endif()

    # Read the dependency's package manifest and find its dependencies. Finding these packages here ensures that if the
    # dependency includes them in its link interface, they'll be loaded in the calling project when it needs to actually
    # link with this dependency.
    set(DependencyManifestFilePath "${BuildDirectory}/${ManifestFile}")
    if(EXISTS "${DependencyManifestFilePath}")
      file(STRINGS "${DependencyManifestFilePath}" DependencyPackages)
      foreach(DependencyPackage ${DependencyPackages})
        string(REGEX REPLACE "/Package$" "" PackageName "${DependencyPackage}")
        cmake_path(GET PackageName FILENAME PackageName)

        # Use the current set of package paths when finding the dependency; this is necessary to ensure that the any
        # dependencies of the dependency that use direct find_package() calls that were satisfied by an earlier call to
        # fetch_dependency() will find those dependencies.
        _fd_find(${PackageName} ROOT ${DependencyPackage} PATHS ${DependencyPackages} ${FETCH_DEPENDENCY_PACKAGES})
      endforeach()
    endif()

    # Write the most up-to-date package manifest so that anything downstream of the calling project will know where its
    # dependencies were written to.
    string(REPLACE ";" "\n" ManifestContent "${FETCH_DEPENDENCY_PACKAGES}")
    file(WRITE ${ManifestFilePath} "${ManifestContent}\n")

    _fd_find(${FD_PACKAGE_NAME} ROOT ${PackageDirectory} PATHS ${DependencyPackages} ${FETCH_DEPENDENCY_PACKAGES})

    # Propagate the updated package directory list.
    set(FETCH_DEPENDENCY_PACKAGES "${FETCH_DEPENDENCY_PACKAGES}" PARENT_SCOPE)
  endif()

  message(STATUS "Checking dependency ${FD_NAME} - done")
endfunction()

