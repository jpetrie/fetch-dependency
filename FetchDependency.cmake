# Minimum CMake version required. Currently driven by the use of GET_MESSAGE_LOG_LEVEL:
# https://cmake.org/cmake/help/latest/command/cmake_language.html#get-message-log-level
set(MinimumCMakeVersion "3.25")
if(${CMAKE_VERSION} VERSION_LESS ${MinimumCMakeVersion})
  message(FATAL_ERROR "FetchDependency requires CMake ${MinimumCMakeVersion} (currently using ${CMAKE_VERSION})")
endif()

# The storage version reflects how we handle the build, package and state directories and store derived dependency data
# in them. When it changes, those directories are refreshed.
set(StorageVersion "1")

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
# It returns whether or not the step should run in the variable specified by FDCS_RESULT. The current hash is returned
# in the variable specified by FDCS_RESULT_HASH.
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
  find_package(${FDF_NAME} QUIET PATHS ${FDF_ROOT})
  if(NOT ${FDF_NAME}_FOUND)
    # Try using PkgConfig to locate the dependency.
    find_package(PkgConfig QUIET)
    if(NOT PkgConfig_FOUND)
      message(FATAL_ERROR "Dependency '${FDF_NAME}' does not export targets for use with find_package().")
    endif()

    pkg_search_module(${FDF_NAME} QUIET NO_CMAKE_ENVIRONMENT_PATH IMPORTED_TARGET ${FDF_NAME})
    if(NOT ${FDF_NAME}_FOUND)
      message(FATAL_ERROR "Dependency '${FDF_NAME}' does not export targets for use with find_package() or PkgConfig.")
    endif()
  endif()
  set(CMAKE_PREFIX_PATH ${SavedPrefixPath})
endfunction()

function(declare_dependency DD_NAME)
  cmake_parse_arguments(DD
    ""
    "CONFIGURATION;OUT_BINARY_DIR"
    "CONFIGURE_OPTIONS;BUILD_OPTIONS"
    ${ARGN}
  )

  if(NOT DD_CONFIGURATION)
    message(FATAL_ERROR "CONFIGURATION must be provided")
  endif()

  message(VERBOSE "-- Configuring dependency ${DD_NAME} (${DD_CONFIGURATION})")
  set(_fd_${DD_NAME}_${DD_CONFIGURATION}_ConfigureOptions ${DD_CONFIGURE_OPTIONS} PARENT_SCOPE)
  set(_fd_${DD_NAME}_${DD_CONFIGURATION}_BuildOptions ${DD_BUILD_OPTIONS} PARENT_SCOPE)

  list(APPEND _fd_${DD_NAME}_Configurations ${DD_CONFIGURATION})
  set(_fd_${DD_NAME}_Configurations ${_fd_${DD_NAME}_Configurations} PARENT_SCOPE)

  if(DD_OUT_BINARY_DIR)
    set(_fd_${DD_NAME}_${DD_CONFIGURATION}_BinaryDirectoryVariable "${DD_OUT_BINARY_DIR}" PARENT_SCOPE)
  endif()
endfunction()

function(fetch_dependency FD_NAME)
  cmake_parse_arguments(FD
    "GIT_DISABLE_SUBMODULES;GIT_DISABLE_SUBMODULE_RECURSION;FETCH_ONLY;NO_RESOLVE;NO_BUILD"
    "ROOT;GIT_SOURCE;LOCAL_SOURCE;VERSION;PACKAGE_NAME;CONFIGURATION;CMAKELIST_SUBDIRECTORY;OUT_SOURCE_DIR"
    "GIT_SUBMODULES;CONFIGURE_OPTIONS;BUILD_OPTIONS"
    ${ARGN}
  )

  if(FD_FETCH_ONLY)
    message(AUTHOR_WARNING "FETCH_ONLY is deprecated and will be removed in a future version of FetchDependency. Use the NO_BUILD option instead.")
    set(FD_NO_BUILD TRUE)
  endif()

  set(FastMode OFF)
  set(FastModeNotice "")
  if($ENV{FETCH_DEPENDENCY_FAST})
    set(FastMode ON)
    set(FastModeNotice " (fast)")
  endif()
  message(STATUS "Checking dependency ${FD_NAME}${FastModeNotice}")

  # Process the source arguments.
  set(SourceMode "")
  if(FD_LOCAL_SOURCE)
    if(FD_GIT_SOURCE)
      message(AUTHOR_WARNING "LOCAL_SOURCE and GIT_SOURCE are mutually exclusive, LOCAL_SOURCE will be used")
    endif()

    if(FD_VERSION)
      message(AUTHOR_WARNING "VERSION is ignored when LOCAL_SOURCE is provided")
    endif()

    set(SourceMode "local")
  elseif(FD_GIT_SOURCE)
    if(NOT FD_VERSION)
      message(FATAL_ERROR "VERSION must be provided")
    endif()

    set(SourceMode "git")
  else()
    message(FATAL_ERROR "LOCAL_SOURCE or GIT_SOURCE must be provided")
  endif()

  if(FD_GIT_DISABLE_SUBMODULES)
    set(IsSubmoduleUpdateEnabled FALSE)
  else()
    set(IsSubmoduleUpdateEnabled TRUE)
  endif()

  if(FD_GIT_DISABLE_SUBMODULE_RECURSION)
    set(SubmoduleRecursiveFlag "")
  else()
    set(SubmoduleRecursiveFlag "--recursive")
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

  set(ProjectDirectory "${FD_ROOT}/${FD_NAME}")
  if("${SourceMode}" STREQUAL "local")
    set(SourceDirectory "${FD_LOCAL_SOURCE}")
  else()
    set(SourceDirectory "${ProjectDirectory}/Source")
  endif()

  set(BuildDirectory "${ProjectDirectory}/Build")
  set(PackageDirectory "${ProjectDirectory}/Package")
  set(StateDirectory "${ProjectDirectory}/State")

  # The source file tracks the source mode and value when the dependency was last processed.
  set(SourceFilePath "${StateDirectory}/source.txt")
  
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
  set(BuildScriptTemplateFilePath "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/Steps/build.in")

  list(APPEND FETCH_DEPENDENCY_PACKAGES "${PackageDirectory}")

  if(FD_OUT_SOURCE_DIR)
    set(${FD_OUT_SOURCE_DIR} "${SourceDirectory}" PARENT_SCOPE)
  endif()

  get_property(IsMultiConfig GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)

  set(BuildNeededMessage "")

  # Check the source stamp. If it changed, the whole dependency needs to be refreshed.
  set(RequiredSourceStamp "${SourceMode}: ${SourceDirectory}")
  set(PreviousSourceStamp "")
  if(EXISTS "${SourceFilePath}")
    file(READ "${SourceFilePath}" PreviousSourceStamp)
    if(NOT "${RequiredSourceStamp}" STREQUAL "${PreviousSourceStamp}")
      message(STATUS "Updating (source changed)")
      file(REMOVE_RECURSE "${ProjectDirectory}")
    endif()
  else()
    message(STATUS "Downloading (source missing)")
    file(REMOVE_RECURSE "${ProjectDirectory}")
  endif()

  # Check the version stamp. If it changed, the build, package and state directories need to be refreshed.
  if(EXISTS ${VersionFilePath})
    file(READ ${VersionFilePath} PreviousVersion)
    if(NOT "${StorageVersion}" STREQUAL "${PreviousVersion}")
      message(STATUS "Updating (storage format changed)")
      file(REMOVE_RECURSE "${BuildDirectory}")
      file(REMOVE_RECURSE "${PackageDirectory}")
      file(REMOVE_RECURSE "${StateDirectory}")
    endif()
  endif()

  if("${SourceMode}" STREQUAL "git")
    # Ensure the source directory exists and is up to date.
    set(IsFetchRequired FALSE)
    if(NOT IS_DIRECTORY "${SourceDirectory}")
      _fd_run(COMMAND git clone ${FD_GIT_SOURCE} "${SourceDirectory}")
      if(IsSubmoduleUpdateEnabled)
        _fd_run(COMMAND git submodule update --init ${SubmoduleRecursiveFlag} ${FD_GIT_SUBMODULES} WORKING_DIRECTORY "${SourceDirectory}")
      endif()
    elseif(NOT FastMode)
      # If the directory exists, before doing anything else, make sure the it is in a clean state. Any local changes are
      # assumed to be intentional and prevent attempts to update.
      _fd_run(COMMAND git status --porcelain WORKING_DIRECTORY "${SourceDirectory}" OUT_STDOUT GitStatus)
      if(NOT "${GitStatus}" STREQUAL "")
        message(AUTHOR_WARNING "Source has local changes, update suppressed (${SourceDirectory})")
      else()
        # Determine what the required version refers to in order to decide if we need to fetch from the remote or not.
        _fd_run(COMMAND git show-ref ${FD_VERSION} WORKING_DIRECTORY "${SourceDirectory}" OUT_STDOUT ShowRefOutput OUT_STDERR DiscardedError)
        if(${ShowRefOutput} MATCHES "^[a-z0-9]+[ \\t]+refs/(remotes|tags)/")
          # The version is a branch name (with remote) or a tag. The underlying commit can move, so a fetch is required.
          set(IsFetchRequired TRUE)
        elseif(${ShowRefOutput} MATCHES "^[a-z0-9]+[ \\t]+refs/heads/")
          # The version is a branch name without a remote. We don't allow this; the remote name must be specified.
          message(FATAL_ERROR "VERSION must include a remote when referring to branch (e.g., 'origin/branch' instead of 'branch')")
        else()
          # The version is a commit hash. This is the ideal case, because if the current and required commits match we can
          # skip the fetch entirely.
          _fd_run(COMMAND git rev-parse HEAD^0 WORKING_DIRECTORY "${SourceDirectory}" OUT_STDOUT ExistingCommit)
          _fd_run(COMMAND git rev-parse ${FD_VERSION}^0 WORKING_DIRECTORY "${SourceDirectory}" OUT_STDOUT RequiredCommit OUT_STDERR RevParseError)
          if(NOT "${ExistingCommit}" STREQUAL "${RequiredCommit}")
            # They don't match, so we have to fetch.
            set(IsFetchRequired TRUE)
          endif()
        endif()

        if(IsFetchRequired)
          _fd_run(COMMAND git fetch --tags WORKING_DIRECTORY "${SourceDirectory}")
          if(IsSubmoduleUpdateEnabled)
            _fd_run(COMMAND git submodule update --init ${SubmoduleRecursiveFlag} ${FD_GIT_SUBMODULES} WORKING_DIRECTORY "${SourceDirectory}")
          endif()
        endif()
      endif()
    endif()

    _fd_run(COMMAND git rev-parse HEAD^0 WORKING_DIRECTORY "${SourceDirectory}" OUT_STDOUT ExistingCommit)
    _fd_run(COMMAND git rev-parse ${FD_VERSION}^0 WORKING_DIRECTORY "${SourceDirectory}" OUT_STDOUT RequiredCommit)
    if(NOT "${ExistingCommit}" STREQUAL "${RequiredCommit}")
      _fd_run(COMMAND git -c advice.detachedHead=false checkout ${FD_VERSION} WORKING_DIRECTORY "${SourceDirectory}")
      if(IsSubmoduleUpdateEnabled)
        _fd_run(COMMAND git submodule update --init ${SubmoduleRecursiveFlag} ${FD_GIT_SUBMODULES} WORKING_DIRECTORY "${SourceDirectory}")
      endif()
      set(BuildNeededMessage "new version")
    endif()
  elseif("${SourceMode}" STREQUAL "local")
    set(BuildNeededMessage "local source")
  endif()

  file(WRITE "${SourceFilePath}" "${RequiredSourceStamp}")

  if(NOT FD_NO_BUILD)
    if(NOT FastMode)
      # If CONFIGURATION is provided, allow explicitly-specified configure or build options to override those provided
      # by declare_dependency().
      if(FD_CONFIGURATION) 
        list(FIND _fd_${FD_NAME}_Configurations ${FD_CONFIGURATION} ThisConfigurationIndex)
        if(${ThisConfigurationIndex} LESS 0)
          # declare_dependency() was never called, so do so now.
          declare_dependency(${FD_NAME} CONFIGURATION ${FD_CONFIGURATION} CONFIGURE_OPTIONS ${FD_CONFIGURE_OPTIONS} BUILD_OPTIONS ${FD_BUILD_OPTIONS})
        else()
          # Replace the options previously given to declare_dependency().
          if(FD_CONFIGURE_OPTIONS)
            set(${_fd_${FD_NAME}_${ConfigurationName}_ConfigureOptions} ${FD_CONFIGURE_OPTIONS})
          endif()
          if(FD_BUILD_OPTIONS)
            set(${_fd_${FD_NAME}_${ConfigurationName}_BuildOptions} ${FD_BUILD_OPTIONS})
          endif()
        endif()
      else()
        # If CONFIGURATION isn't specified, there must have been at least one prior call to declare_dependency().
        list(LENGTH _fd_${FD_NAME}_Configurations ConfigurationCount)
        if(${ConfigurationCount} LESS_EQUAL 0)
          message(FATAL_ERROR "CONFIGURATION must be provided if declare_dependency() has not been called")
        endif()

        # Additionally, if CONFIGURATION isn't specified, it doesn't make sense for options to be provided.
        if(FD_CONFIGURE_OPTIONS)
          message(FATAL_ERROR "CONFIGURE_OPTIONS must not be provided if no CONFIGURATION is provided")
        endif()
        if(FD_BUILD_OPTIONS)
          message(FATAL_ERROR "BUILD_OPTIONS must not be provided if no CONFIGURATION is provided")
        endif()
      endif()

      # This list holds the dependencies of the current dependency that need to be propagated. Each configuration likely
      # has the same dependencies, but it's not guaranteed. Every dependency referenced is collected in this list, which
      # is then de-duplicated before resolution.
      set(PropagatedPackages "")
      foreach(ConfigurationName ${_fd_${FD_NAME}_Configurations})
        message(STATUS "Preparing configuration ${ConfigurationName}")

        if(_fd_${FD_NAME}_${ConfigurationName}_BinaryDirectoryVariable)
          set(${_fd_${FD_NAME}_${ConfigurationName}_BinaryDirectoryVariable} "${BuildDirectory}/${ConfigurationName}" PARENT_SCOPE)
        endif()

        set(ConfigureScriptFilePath "${StateDirectory}/${ConfigurationName}/configure.${ScriptExtension}")
        set(ConfigureScriptHashFilePath "${StateDirectory}/${ConfigurationName}/last-configure.txt")

        set(BuildScriptFilePath "${StateDirectory}/${ConfigurationName}/build.${ScriptExtension}")
        set(BuildScriptHashFilePath "${StateDirectory}/${ConfigurationName}/last-build.txt")

        list(APPEND ConfigureArguments "-DCMAKE_INSTALL_PREFIX=${PackageDirectory}")
        list(APPEND ConfigureArguments ${_fd_${FD_NAME}_${ConfigurationName}_ConfigureOptions})
        list(APPEND BuildArguments ${_fd_${FD_NAME}_${ConfigurationName}_BuildOptions})

        if(CMAKE_TOOLCHAIN_FILE)
          list(APPEND ConfigureArguments " --toolchain ${CMAKE_TOOLCHAIN_FILE}")
        endif()

        # Configuration handling differs for single- versus multi-config generators. Note that we use a unique directory
        # per configuration even when multi-configuration generators are used because this allows each configuration to
        # have its own set of generated properties (stored in ConfigureArguments), preserving the same behavior as with
        # single-configuration generators.
        if(IsMultiConfig)
          list(APPEND BuildArguments "--config ${ConfigurationName}")
        else()
          list(APPEND ConfigureArguments "-DCMAKE_BUILD_TYPE=${ConfigurationName}")
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
          set(BuildNeededMessage "new configure options")
        elseif(IsBuildNeeded)
          set(BuildNeededMessage "new build options")
        endif()

        if(NOT "${BuildNeededMessage}" STREQUAL "")
          message(STATUS "Building (${BuildNeededMessage})")
          if(IsConfigureNeeded)
            _fd_run(COMMAND "${ConfigureScriptFilePath}" ERROR_CONTEXT "Configure failed: ")
            file(WRITE "${ConfigureScriptHashFilePath}" ${ConfigureScriptHash})
          endif()

          _fd_run(COMMAND "${BuildScriptFilePath}" ERROR_CONTEXT "Build failed: ")
          file(WRITE "${BuildScriptHashFilePath}" ${BuildScriptHash})
        endif()

        # Read the dependency's package manifest and propagate its dependencies.
        set(DependencyManifestFilePath "${BuildDirectory}/${ConfigurationName}/${ManifestFile}")
        if(EXISTS "${DependencyManifestFilePath}")
          file(STRINGS "${DependencyManifestFilePath}" DependencyPackages)
          foreach(DependencyPackage ${DependencyPackages})
            list(APPEND PropagatedPackages "${DependencyPackage}")
          endforeach()
        endif()
      endforeach()

      list(REMOVE_DUPLICATES PropagatedPackages)
      foreach(Propagated ${PropagatedPackages})
        # Ensure the package is propagated down.
        list(APPEND FETCH_DEPENDENCY_PACKAGES "${DependencyPackage}")

        string(REGEX REPLACE "/Package$" "" PackageName "${DependencyPackage}")
        cmake_path(GET PackageName FILENAME PackageName)

        # Resolve the dependency in the context of the calling project. This ensures that if the dependency includes
        # them in its link interface, they're loaded when CMake tries to actually link with the this dependency.
        _fd_find(${PackageName} ROOT ${DependencyPackage} PATHS ${FETCH_DEPENDENCY_PACKAGES})
      endforeach()
    endif()

    if(NOT FD_NO_RESOLVE)
      # Write the most up-to-date package manifest so that anything downstream of the calling project will know where its
      # dependencies were written to.
      string(REPLACE ";" "\n" ManifestContent "${FETCH_DEPENDENCY_PACKAGES}")
      file(WRITE ${ManifestFilePath} "${ManifestContent}\n")

      _fd_find(${FD_PACKAGE_NAME} ROOT ${PackageDirectory} PATHS ${DependencyPackages} ${FETCH_DEPENDENCY_PACKAGES})

      # Propagate the updated package directory list.
      set(FETCH_DEPENDENCY_PACKAGES "${FETCH_DEPENDENCY_PACKAGES}" PARENT_SCOPE)
    endif()
  endif()

  # The dependency was fully-processed, so stamp it with the current storage version.
  file(WRITE ${VersionFilePath} "${StorageVersion}")

  message(STATUS "Checking dependency ${FD_NAME} - done")
endfunction()

