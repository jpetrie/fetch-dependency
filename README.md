# FetchDependency
FetchDependency is a CMake module that provides a mechanism to download, configure, build and install (local to the
calling project) a dependency package at configuration time.

FetchDependency is designed to enable dependency handling in CMake according to a specific philosophy:
 - A project's dependencies should be made available automatically, to enable the quickest turnaround time from fetching
   a project from source control to a successful build of that project.
 - A project's dependencies should be stored with it by default, rather than in a global location, in order to isolate
   the project from changes made outside the project itself.
 - A project's dependencies should not pollute the targets of the project or any other dependencies, in order to
   avoid target name collisions and keep the project's target list focused.

The cost of the aforementioned features is increased configuration time when using FetchDependency, especially during
the initial configuration, as all dependencies are downloaded and built from source. This is _noticeably un-CMake-like
behavior_, but it is necessary to achieve the above.

To alleviate the impact of configure-time builds, FetchDependency attempts to minimize build invocations by tracking
information about the build such as its commit hash and the options used to configure it. Additionally, most of
FetchDependency's expensive logic can be temporarily bypassed entirely by setting the environment variable
`FETCH_DEPENDENCY_FAST` to 1. This enables rapid iteration on your build infrastructure following the initial configure
and build of all dependencies.

## Installation
FetchDependency requires CMake 3.25 or later.

The recommended way to automatically include FetchDependency in your project is to use CMake's
[FetchContent](https://cmake.org/cmake/help/latest/module/FetchContent.html) module:

```cmake
include(FetchContent)
FetchContent_Declare(FetchDependency
  GIT_REPOSITORY https://github.com/jpetrie/fetch-dependency.git
  GIT_TAG 1.1.0
)
FetchContent_MakeAvailable(FetchDependency)
include(${fetchdependency_SOURCE_DIR}/FetchDependency.cmake)
```

## Usage
Calling `fetch_dependency()` will fetch, build and install a dependency package:
```cmake
  fetch_dependency(Catch2 GIT_SOURCE https://github.com/catchorg/Catch2.git VERSION v2.13.8 CONFIGURATION Release)
```

This will make the Release configuration of [Catch2](https://github.com/catchorg/Catch2) immediately available to the
calling project's future targets:
```cmake
  target_link_libraries(... Catch2::Catch2)
```

If you need to build multiple configurations of a dependency, you can use `declare_dependency()` to pre-declare a
dependency configuration and its associated options before calling `fetch_dependency()`. See the full documentation
below for details.

## Documentation
### `fetch_dependency()`
Download, build and locally install a dependency named `<name>` during configuration.
```
  fetch_dependency(
    <name>
    LOCAL_SOURCE <path>
    GIT_SOURCE <url>
    [VERSION <version>]
    [FETCH_ONLY]
    [GIT_DISABLE_SUBMODULES]
    [GIT_DISABLE_SUBMODULE_RECURSION]
    [GIT_SUBMODULES <paths...>]
    [ROOT <path>]
    [PACKAGE_NAME <package>]
    [CONFIGURATION <configuration>]
    [CONFIGURE_OPTIONS <options...>]
    [BUILD_OPTIONS <options...>]
    [CMAKELIST_SUBDIRECTORY <path>]
    [OUT_SOURCE_DIR <out-var>]
  )
```
`<name>` is used to create the directory where the dependency's source and artifacts will be stored. Unless
`PACKAGE_NAME` is provided (see below), it will also be used in the internal `find_package()` call to locate the
dependency's targets.

One of `LOCAL_SOURCE` or `GIT_SOURCE` are required, and they are mutually exclusive.

Options:
 - `LOCAL_SOURCE <path>` Path to the source of the dependency on the local file system.
 - `GIT_SOURCE <url>` URL of the Git repository. See the documentation for the `ROOT` parameter below for detail on
   where the repository will be cloned.
 - `VERSION <version>` Version string associated with the source. For local sources, this is unused and shouldn't be
   provided. For Git sources, this is a Git branch name, tag or commit hash. A commit hash is the recommended means of
   specifying a dependency version. Branches must be specified with their name to ensure they are correctly updated.
   Specifying a commit hash is recommended because it can allow the `git fetch` operation to be avoided during configure
   when the local copy is already on the specified tag. This option is required when `GIT_SOURCE` is specified.
 - `FETCH_ONLY` Download the dependency, but do not build or install it. This is useful for dependencies where only the
   source is needed. Note that this will still _configure_ the dependency (this is required to enable updates if
   `VERSION` is changed, due to how `fetch_dependency()` is implemented). If you do not want the dependency configured
   (or it is not a CMake project), consider using CMake's [FetchContent](https://cmake.org/cmake/help/latest/module/FetchContent.html)
   module instead.
 - `GIT_DISABLE_SUBMODULES` Prevent submodule updates when downloading the dependency (in other words, do not execute
   `git submodule` commands).
 - `GIT_DISABLE_SUBMODULE_RECURSION` Prevent submodule updates from recursively updating additional submodules (in other
   words, do not pass `--recursive` to `git submodule` commands).
 - `GIT_SUBMODULES <paths...>` Process only the specified submodule paths during submodule updates. If this option is
   not specified, all submodules will be updated. `GIT_DISABLE_SUBMODULES` will override this option.
 - `ROOT <path>` The root storage directory for the dependency. If not specified, the value of the global
   `FETCH_DEPENDENCY_DEFAULT_ROOT` will be used. If `FETCH_DEPENDENCY_DEFAULT_ROOT` is not defined, the value "External"
   will be used. In all cases, if the root is a relative path, it will be interpreted as relative to `CMAKE_BINARY_DIR`.
   This parameter is ignored when the `LOCAL_SOURCE` option is used.
 - `PACKAGE_NAME <package>` Pass `<package>` to `find_package()` internally when locating the built dependency's
   targets. If not specified, the value of `<name>` will be used.
 - `CONFIGURATION <name>` Use the named configuration instead of the default for the dependency. Specifying a
   configuration via this option will work correctly regardless of whether or not the generator in use is a single-
   or multi-configuration generator. If not specified, "Release" is assumed.
 - `CONFIGURE_OPTIONS <options...>` Pass the following options to CMake when generating the dependency.
 - `BUILD_OPTIONS <options...>` Pass the following options to CMake's `--build` command when building the dependency.
 - `CMAKELIST_SUBDIRECTORY <path>` The path to the directory containing the `CMakeLists.txt` for the dependency if it
   is not located at the root of the dependency's source tree. Always interpreted as a path relative to the dependency's
   source tree.
 - `OUT_SOURCE_DIR <out-var>` The name of a variable that will be set to the absolute path to the dependency's source
   tree.

### `declare_dependency()`
Pre-declare a dependency's configuration.
```
  declare_dependency(
    <name>
    CONFIGURATION <path>
    [CONFIGURE_OPTIONS <options...>]
    [BUILD_OPTIONS <options...>]
    [OUT_BINARY_DIR <out-var>]
  )
```

`declare_dependency()` must be called before the corresponding `fetch_dependency()` call. When pre-declaring
configurations, it isn't neccessary to pass configuration-related parameters to `fetch_dependency()`. All declared
configurations will be built and installed.

`<name>` must match the name used when `fetch_dependency()` is called.

Options:
 - `CONFIGURATION <name>` The configuration to declare.
 - `CONFIGURE_OPTIONS <options...>` Pass the following options to CMake when generating this configuration of the
   dependency.
 - `BUILD_OPTIONS <options...>` Pass the following options to CMake's `--build` command when building this configuration
   of the dependency.
 - `OUT_BINARY_DIR <out-var>` The name of a variable that will be set the absolute path to the dependency's binary tree.
   Note that this variable will not be written to until the corresponding `fetch_dependency()` call completes.

### `FETCH_DEPENDENCY_DEFAULT_ROOT`
Defines the default root directory for fetched dependencies. It is initially undefined, which causes
`fetch_dependency()` to fall back to storing dependencies underneath `${CMAKE_BINARY_DIR}/External/`. 

### `FETCH_DEPENDENCY_PACKAGES`
Stores the set of package directories fetched by the project (and all of its dependencies, recursively) so far.

## Recipes
### Fast Build Infrastructure Iteration
In cases where you need to work on your project's `CMakeLists.txt` or similar and will be repeatedly re-configuring your
project, it can be desirable to skip as much of FetchDependency's overhead as possible. This can be accomplished by
setting the environment variable `FETCH_DEPENDENCY_FAST` to 1.

When this "fast mode" is enabled, `fetch_dependency()` only executes the logic needed to call `find_package()` on the
dependency. It skips the up-to-date checks and build attempts that it might normally run, saving considerable time in
the configuration process (especially if you have many dependencies).

"Fast mode" requires that a regular configure has been executed at least once, or the files necessary for the
`find_package()` machinery to work correctly will not exist and the configuration will fail.

### Local Dependency Edits
Sometimes it is necessary to make local changes to a dependency - if it's something you are developing it parallel to
your main project, or if there are bugs you're trying to address. FetchDependency generates CMake projects for each
dependency, so it is possible to simply use those generated projects as you would normally. FetchDependency also allows
you to reproduce the configure and build steps it uses exactly by executing scripts in the `State` subdirectory of the
dependency folder. These scripts will be named `configure.sh`/`build.sh` or `configure.bat`/`build.bat` depending on
your OS. 

When FetchDependency detects a local change to a dependency's source (either because `LOCAL_SOURCE` is in use, or
because the Git working tree is dirty), it will never attempt to perform any updates to the source and it will always
attempt to trigger the build step. Note that there is no link created between dependency source files and any targets
in your main project, so simply building that may not detect local changes to a dependency - you will need to explicitly
run CMake against your main project, or use the per-dependency scripts within their state folder.

Keep in mind that if you are using `GIT_SOURCE` for your dependency, the dependency's working tree is very likely in a
"detached HEAD" state (confirm with `git status`). If that is true and you want to commit any local edits you make, you
will need to make sure to create a branch from the local changes, switch over to a real branch, and merge those changes
back in.

## Architecture
FetchDependency stores each dependency in its own "project folder" under a root directory. The project folder in turn
contains four directories:
  - _Source_, which holds the actual dependency source (unless `LOCAL_SOURCE` is being used).
  - _Build_, which is the project's binary directory.
  - _Package_, which is where the built project is installed.
  - _State_, which holds data FetchDependency uses to process the build.

Additionally, FetchDependency maintains a manifest (`FetchedDependencies.txt`) in your project's binary directory that
lists the absolute path to the package directories for every dependency processed.

When called for a given dependency, `fetch_dependency()` makes sure the source directory is available and matches the
required `VERSION`. It will then determine if it needs to run the configure and build steps, as specified.
`fetch_dependency()` always builds the `install` target explicitly. Finally, `fetch_dependency()` calls `find_package()`
to make the exported targets from the dependency available to the rest of your project's configuration.

