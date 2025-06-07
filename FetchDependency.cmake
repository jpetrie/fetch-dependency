# Minimum CMake version required. Currently driven by the use of GET_MESSAGE_LOG_LEVEL:
# https://cmake.org/cmake/help/latest/command/cmake_language.html#get-message-log-level
set(FetchDependencyMinimumVersion "3.25")
if(${CMAKE_VERSION} VERSION_LESS ${FetchDependencyMinimumVersion})
  message(FATAL_ERROR "FetchDependency requires CMake ${FetchDependencyMinimumVersion} (currently using ${CMAKE_VERSION}).")
endif()

set(FetchDependencyMajorVersion "0")
set(FetchDependencyMinorVersion "3")
set(FetchDependencyPatchVersion "2")
set(FetchDependencyVersion "${FetchDependencyMajorVersion}.${FetchDependencyMinorVersion}.${FetchDependencyPatchVersion}")

function(_fd_run)
  cmake_parse_arguments(FDR "" "WORKING_DIRECTORY;ERROR_CONTEXT;OUT_STDOUT;OUT_STDERR" "COMMAND" ${ARGN})
  if(NOT FDR_WORKING_DIRECTORY)
    set(FDR_WORKING_DIRECTORY "")
  endif()

  cmake_language(GET_MESSAGE_LOG_LEVEL Level)
  if((${Level} STREQUAL "VERBOSE") OR (${Level} STREQUAL "DEBUG") OR (${Level} STREQUAL "TRACE"))
    set(EchoOutput "ECHO_OUTPUT_VARIABLE")
    set(EchoError "ECHO_ERROR_VARIABLE")
  endif()

  string(REPLACE ";" " " Command "${FDR_COMMAND}")
  message(VERBOSE ">> ${Command}")
  execute_process(
    COMMAND ${FDR_COMMAND}
    OUTPUT_VARIABLE Output
    ERROR_VARIABLE Error
    RESULT_VARIABLE Result
    WORKING_DIRECTORY "${FDR_WORKING_DIRECTORY}"
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_STRIP_TRAILING_WHITESPACE
    ${EchoOutput}
    ${EchoError}
  )

  if(Result)
    if(FDR_OUT_STDERR)
      set(${FDR_OUT_STDERR} ${Error} PARENT_SCOPE)
    else()
      message(FATAL_ERROR "${FDR_ERROR_CONTEXT} (${Result})\n${Output}\n${Error}")
    endif()
  endif()

  if(FDR_OUT_STDOUT)
    set(${FDR_OUT_STDOUT} ${Output} PARENT_SCOPE)
  endif()
endfunction()

# This function computes the hash of the given script and compares it to the previous hash stored in the hash file.
# It returns whether or not the step should run and the hash of the given script in the last two variables.
function(_fd_check_step FDCS_SCRIPT_FILE FDCS_HASH_FILE FDCS_RESULT FDCS_RESULT_HASH)
  file(MD5 "${FDCS_SCRIPT_FILE}" CurrentHash)

  set(PreviousHash "")
  if(EXISTS "${FDCS_HASH_FILE}")
    file(READ "${FDCS_HASH_FILE}" PreviousHash)
  endif()

  set(${FDCS_RESULT_HASH} "${CurrentHash}" PARENT_SCOPE)
  if("${CurrentHash}" STREQUAL "${PreviousHash}")
    set(${FDCS_RESULT} FALSE PARENT_SCOPE)
  else()
    set(${FDCS_RESULT} TRUE PARENT_SCOPE)
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
    "ROOT;GIT_REPOSITORY;GIT_TAG;LOCAL_SOURCE;PACKAGE_NAME;CONFIGURATION;CMAKELIST_SUBDIRECTORY;OUT_SOURCE_DIR;OUT_BINARY_DIR"
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

  # Process the source arguments.
  set(SourceMode "")
  if(FD_LOCAL_SOURCE)
    if(FD_GIT_REPOSITORY)
      message(AUTHOR_WARNING "LOCAL_SOURCE and GIT_REPOSITORY are mutually exlusive; LOCAL_SOURCE will be used.")
    endif()

    if(FD_GIT_TAG)
      message(AUTHOR_WARNING "GIT_TAG is ignored when LOCAL_SOURCE is provided.")
    endif()

    set(SourceMode "local")
  elseif(FD_GIT_REPOSITORY)
    if(NOT FD_GIT_TAG)
      message(FATAL_ERROR "GIT_TAG must be provided.")
    endif()

    set(SourceMode "git")
  else()
    message(FATAL_ERROR "One of LOCAL_SOURCE or GIT_REPOSITORY must be provided.")
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
  message(VERBOSE "Using root: ${FD_ROOT}")

  if(NOT FD_CONFIGURATION)
    set(FD_CONFIGURATION "Release")
  endif()
  
  set(ProjectDirectory "${FD_ROOT}/${FD_NAME}")
  if("${SourceMode}" STREQUAL "local")
    set(SourceDirectory "${FD_LOCAL_SOURCE}")
  else()
    set(SourceDirectory "${ProjectDirectory}/Source")
  endif()

  set(BuildDirectory "${ProjectDirectory}/Build")
  set(PackageDirectory "${ProjectDirectory}/Package")
  set(StateDirectory "${ProjectDirectory}/State")

  # The version file tracks the version of FetchDependency that last processed the dependency.
  set(VersionFilePath "${StateDirectory}/version.txt")
  
  # The manifest file contains the package directories of every dependency fetched for the calling project so far.
  set(ManifestFile "FetchedDependencies.txt")
  set(ManifestFilePath "${CMAKE_BINARY_DIR}/${ManifestFile}")

  if(UNIX)
    set(ScriptHeader "#!/bin/sh")
    set(ScriptSet "export")
    set(ScriptExtension "sh")
  else()
    set(ScriptHeader "@echo off")
    set(ScriptSet "set")
    set(ScriptExtension "bat")
  endif()

  set(ConfigureScriptTemplateFilePath "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/Steps/configure.in")
  set(ConfigureScriptFilePath "${StateDirectory}/configure.${ScriptExtension}")
  set(ConfigureScriptHashFilePath "${StateDirectory}/last-configure.txt")

  set(BuildScriptTemplateFilePath "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/Steps/build.in")
  set(BuildScriptFilePath "${StateDirectory}/build.${ScriptExtension}")
  set(BuildScriptHashFilePath "${StateDirectory}/last-build.txt")

  list(APPEND FETCH_DEPENDENCY_PACKAGES "${PackageDirectory}")

  if(FD_OUT_SOURCE_DIR)
    set(${FD_OUT_SOURCE_DIR} "${SourceDirectory}" PARENT_SCOPE)
  endif()

  if(FD_OUT_BINARY_DIR)
    set(${FD_OUT_BINARY_DIR} "${BuildDirectory}" PARENT_SCOPE)
  endif()

  set(BuildNeededMessage "")

  # Check the version stamp. If this dependency was last processed with a version of FetchDependency with a different
  # major or minor version, the binary and package directories should be erased so that the dependency is rebuilt from
  # a clean state. This doesn't affect the source directory.
  if(EXISTS ${VersionFilePath})
    file(READ ${VersionFilePath} LastVersion)
    string(REGEX MATCH "^([0-9]+)\\.([0-9]+)\\.([0-9]+)" LastVersionMatch ${LastVersion})

    # Match 0 is the full match, 1-3 are the sub-matches for the major, minor and patch components.
    if(NOT ("${CMAKE_MATCH_1}" STREQUAL "${FetchDependencyMajorVersion}" AND "${CMAKE_MATCH_2}" STREQUAL "${FetchDependencyMinorVersion}"))
      message(VERBOSE "Removing directory ${BuildDirectory}")
      file(REMOVE_RECURSE "${BuildDirectory}")

      message(VERBOSE "Removing directory ${PackageDirectory}")
      file(REMOVE_RECURSE "${PackageDirectory}")

      message(VERBOSE "Removing directory ${StateDirectory}")
      file(REMOVE_RECURSE "${StateDirectory}")

      set(BuildNeededMessage "last built with ${LastVersionMatch}, now on ${FetchDependencyVersion}")
    endif()
  endif()

  if("${SourceMode}" STREQUAL "git")
    # Ensure the source directory exists and is up to date.
    set(IsFetchRequired FALSE)
    if(NOT IS_DIRECTORY "${SourceDirectory}")
      _fd_run(COMMAND git clone --recurse-submodules ${FD_GIT_REPOSITORY} "${SourceDirectory}")
    elseif(NOT FastMode)
      # If the directory exists, before doing anything else, make sure the it is in a clean state. Any local changes are
      # assumed to be intentional and prevent attempts to update.
      _fd_run(COMMAND git status --porcelain WORKING_DIRECTORY "${SourceDirectory}" OUT_STDOUT GitStatus)
      if(NOT "${GitStatus}" STREQUAL "")
        message(AUTHOR_WARNING "Source has local changes; update suppressed (${SourceDirectory}).")
      else()
        # Determine what the required version refers to in order to decide if we need to fetch from the remote or not.
        _fd_run(COMMAND git show-ref ${FD_GIT_TAG} WORKING_DIRECTORY "${SourceDirectory}" OUT_STDOUT ShowRefOutput OUT_STDERR DiscardedError)
        if(${ShowRefOutput} MATCHES "^[a-z0-9]+[ \\t]+refs/(remotes|tags)/")
          # The version is a branch name (with remote) or a tag. The underlying commit can move, so a fetch is required.
          set(IsFetchRequired TRUE)
        elseif(${ShowRefOutput} MATCHES "^[a-z0-9]+[ \\t]+refs/heads/")
          # The version is a branch name without a remote. We don't allow this; the remote name must be specified.
          message(FATAL_ERROR "GIT_TAG must include a remote when referring to branch (e.g., 'origin/branch' instead of 'branch').")
        else()
          # The version is a commit hash. This is the ideal case, because if the current and required commits match we can
          # skip the fetch entirely.
          _fd_run(COMMAND git rev-parse HEAD^0 WORKING_DIRECTORY "${SourceDirectory}" OUT_STDOUT ExistingCommit)
          _fd_run(COMMAND git rev-parse ${FD_GIT_TAG}^0 WORKING_DIRECTORY "${SourceDirectory}" OUT_STDOUT RequiredCommit OUT_STDERR RevParseError)
          if(NOT "${ExistingCommit}" STREQUAL "${RequiredCommit}")
            # They don't match, so we have to fetch.
            set(IsFetchRequired TRUE)
          endif()
        endif()

        if(IsFetchRequired)
          _fd_run(COMMAND git fetch --tags WORKING_DIRECTORY "${SourceDirectory}")
          _fd_run(COMMAND git submodule update --remote WORKING_DIRECTORY "${SourceDirectory}")
        endif()
      endif()
    endif()

    _fd_run(COMMAND git rev-parse HEAD^0 WORKING_DIRECTORY "${SourceDirectory}" OUT_STDOUT ExistingCommit)
    _fd_run(COMMAND git rev-parse ${FD_GIT_TAG}^0 WORKING_DIRECTORY "${SourceDirectory}" OUT_STDOUT RequiredCommit)
    if(NOT "${ExistingCommit}" STREQUAL "${RequiredCommit}")
      _fd_run(COMMAND git -c advice.detachedHead=false checkout --recurse-submodules ${FD_GIT_TAG} WORKING_DIRECTORY "${SourceDirectory}")
      set(BuildNeededMessage "versions differ")
    endif()
  elseif("${SourceMode}" STREQUAL "local")
    set(BuildNeededMessage "local source")
  endif()

  if(NOT FD_FETCH_ONLY)
    if(NOT FastMode)
      list(APPEND ConfigureArguments "-DCMAKE_INSTALL_PREFIX=${PackageDirectory}")
      list(APPEND ConfigureArguments ${FD_GENERATE_OPTIONS})
      list(APPEND BuildArguments ${FD_BUILD_OPTIONS})

      if(CMAKE_TOOLCHAIN_FILE)
        list(APPEND ConfigureArguments " --toolchain ${CMAKE_TOOLCHAIN_FILE}")
      endif()

      # Configuration handling differs for single- versus multi-config generators.
      get_property(IsMultiConfig GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
      if(IsMultiConfig)
        list(APPEND BuildArguments "--config ${FD_CONFIGURATION}")
      else()
        list(APPEND ConfigureArguments "-DCMAKE_BUILD_TYPE=${FD_CONFIGURATION}")
      endif()

      # When invoking CMake, the package paths are passed via the CMAKE_PREFIX_PATH environment variable. This avoids a
      # warning that would otherwise be generated if the dependency never actually caused CMAKE_PREFIX_PATH to be
      # referenced. Note that the platform path delimiter must be used to separate individual paths in this case.
      set(Packages ${FETCH_DEPENDENCY_PACKAGES})
      if(UNIX)
        string(REPLACE ";" ":" Packages "${Packages}")
      endif()

      string(REPLACE ";" " " ConfigureArguments "${ConfigureArguments}")
      configure_file(
        "${ConfigureScriptTemplateFilePath}"
        "${ConfigureScriptFilePath}"
        FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_WRITE GROUP_EXECUTE WORLD_READ
      )
      _fd_check_step("${ConfigureScriptFilePath}" "${ConfigureScriptHashFilePath}" IsConfigureNeeded ConfigureScriptHash)

      string(REPLACE ";" " " BuildArguments "${BuildArguments}")
      configure_file(
        "${BuildScriptTemplateFilePath}"
        "${BuildScriptFilePath}"
        FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_WRITE GROUP_EXECUTE WORLD_READ
      )
      _fd_check_step("${BuildScriptFilePath}" "${BuildScriptHashFilePath}" IsBuildNeeded BuildScriptHash)

      if(IsConfigureNeeded)
        set(BuildNeededMessage "configure options differ")
      elseif(IsBuildNeeded)
        set(BuildNeededMessage "build options differ")
      endif()

      if(NOT "${BuildNeededMessage}" STREQUAL "")
        message(STATUS "Building (${BuildNeededMessage}).")
        if(IsConfigureNeeded)
          _fd_run(COMMAND "${ConfigureScriptFilePath}" ERROR_CONTEXT "Configure failed: ")
          file(WRITE "${ConfigureScriptHashFilePath}" ${ConfigureScriptHash})
        endif()

        _fd_run(COMMAND "${BuildScriptFilePath}" ERROR_CONTEXT "Build failed: ")
        file(WRITE "${BuildScriptHashFilePath}" ${BuildScriptHash})
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

  # The dependency was fully-processed, so stamp it with the current FetchDependency version.
  file(WRITE ${VersionFilePath} "${FetchDependencyVersion}")

  message(STATUS "Checking dependency ${FD_NAME} - done")
endfunction()

