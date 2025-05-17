# FetchDependency

FetchDependency is a CMake module that provides a mechanism to download, configure, build and install (local to the
calling project) a dependency package at configuration time.

FetchDependency is designed to enable dependency handling in CMake according to a specific philosophy:

 - A project's dependencies should be made available automatically, to enable the quickest turnaround time from fetching
   a project from source control to a successful build of that project.
 - A project's dependencies should be stored with it by default, rather than in a global location, in order to isolate
   the project from changes made outside the project itself.
 - A project's dependencies should not pollute the targets of the project or any other dependencies, in order to
   avoid target name collisions and keep a the project's target list focused.

The cost of the aforementioned features is increased configuration time when using FetchDependency, especially during
the initial configuration, as all dependencies are downloaded and built from source. This is noticeably un-CMake-like
behavior, but it is neccessary to achieve the above. 

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
  GIT_TAG origin/main
)
FetchContent_MakeAvailable(FetchDependency)
include(${fetchdependency_SOURCE_DIR}/FetchDependency.cmake)
```

⚠️FetchDependency has not reached version 1.0!⚠️

As such you should expect breaking changes with potentially every commit, including changes to the storage architecture
that will require all dependencies to be re-downloaded and/or re-built. It is strongly recommended that you pin
FetchDependency to a specific commit ID via `GIT_TAG` when installing.

## Usage

FetchDependency provides a single function, `fetch_dependency()`, which will fetch and find a dependency package:

```cmake
  fetch_dependency(Catch2 GIT_REPOSITORY https://github.com/catchorg/Catch2.git GIT_TAG v2.13.8)
```

This will fetch, configure, build and install [Catch2](https://github.com/catchorg/Catch2) within the calling project's
CMake binary directory. It will then call `find_package()` to locate the dependency and make it available to future
targets immediately:

```cmake
  target_link_libraries(... Catch2::Catch2)
```

## Documentation

### fetch_dependency()
Download, build and locally install a dependency named `<name>` during configuration.

```cmake
  fetch_dependency(
    <name>
    GIT_REPOSITORY <url>
    GIT_TAG <tag>
    [ROOT <path>]
    [PACKAGE_NAME <package>]
    [CONFIGURATION <configuration>]
    [GENERATE_OPTIONS <options...>]
    [BUILD_OPTIONS <options...>]
    [CMAKELIST_SUBDIRECTORY <path>]
    [OUT_SOURCE_DIR <out-var>]
    [OUT_BINARY_DIR <out-var>]
  )
```

`<name>` is used to create the directory where the dependency's source and artifacts will be stored. Unless
`PACKAGE_NAME` is provided (see below), it will also be used in the internal `find_package()` call to locate the
dependency's targets.

Options:
- `GIT_REPOSITORY <url>` URL of the Git repository. See the documentation for the `ROOT` parameter below for detail on
  where the repository will be cloned.

- `GIT_TAG <tag>` Git branch name, tag or commit hash. A commit hash is the recommended means of specifying a dependency
   version. Branches and tags should generally be specified as remote names to ensure the local clone will be correctly
   updated in the event of a tag move, branch rebase, or history rewrite.

- `ROOT <path>` The root storage directory for the dependency. If not specified, the value of the global
  `FETCH_DEPENDENCY_DEFAULT_ROOT` will be used. If `FETCH_DEPENDENCY_DEFAULT_ROOT` is not defined, the value "External"
  will be used. In all cases, if the root is a relative path, it will be interpreted as relative to `CMAKE_BINARY_DIR`.

- `PACKAGE_NAME <package>` Pass `<package>` to `find_package()` internally when locating the built dependency's
   targets. If not specified, the value of `<name>` will be used.

- `CONFIGURATION <name>` Use the named configuration instead of the default for the dependency. Specifying a
   configuration via this option will work correctly regardless of whether or not the generator in use is a single-
   or multi-configuration generator. If not specified, "Release" is assumed.

- `GENERATE_OPTIONS <options...>` Pass the following options to CMake when generating the dependency.

- `BUILD_OPTIONS <options...>` Pass the following options to CMake's `--build` command when building the dependency.

- `CMAKELIST_SUBDIRECTORY <path>` The path to the directory containing the `CMakeLists.txt` for the dependency if it
   is not located at the root of the dependency's source tree. Always interpreted as a path relative to the dependency's
   source tree.

- `OUT_SOURCE_DIR <out-var>` The name of a variable that will be set to the absolute path to the dependency's source
  tree.

- `OUT_BINARY_DIR <out-var>` The name of a variable that will be set the absolute path to the dependency's binary tree.

### FETCH_DEPENDENCY_DEFAULT_ROOT
Defines the default root directory for fetched dependencies. It is initially undefined, which causes
`fetch_dependency()` to fall back to storing dependencies underneath `${CMAKE_BINARY_DIR}/External/`. 

### FETCH_DEPENDENCY_PACKAGES
Stores the set of package directories fetched by the project (and all of its dependencies, recursively) so far.

## Recipes
### Fast Build Infrastructure Interation
In cases where you need to work on your project's `CMakeLists.txt` or similar and will be repeatedly re-configuring your
project, it can be desirable to skip as much of FetchDependency's overhead as possible. This can be accomplished by
setting the environment variable `FETCH_DEPENDENCY_FAST` to 1.

When this "fast mode" is enabled, `fetch_dependency()` only executes the logic needed to call `find_package()` on the
dependency. It skips the up-to-date checks and build attempts that it might normally run, saving considerable time in
the configuration process (especially if you have many dependencies).

"Fast mode" requires that a regular configure has been executed at least once, or the files neccessary for the
`find_package()` machinery to work correctly will not exist and the configuration will fail.

