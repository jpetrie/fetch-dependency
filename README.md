# FetchDependency

FetchDependency is a CMake module that provides a mechanism to download, configure, build and install (local to the
calling project) a dependency package at configuration time.

FetchDependency is designed to enable dependency handling in CMake according to a specific philosophy:

 - A project's dependencies should be made available automatically, in order to facilitate the quickest turnaround
   from cloning a project to a successful build.
 - A project's dependencies should be stored with it by default, rather than a global location, in order to isolate
   the project from changes made outside the project.
 - A project's dependencies should not pollute the targets of the project or any other dependencies, in order to 
   avoid target name collisions and keep an IDE's target list (when an IDE is used) focused.

The cost of both of the aforementioned features is increased configuration time for the calling project (especially
during initial configuration) as all dependencies are downloaded and built from source. To alleviate the impact on
configuration time, FetchDependency tracks the configured version of each dependency to avoid unneccessary pulls
or rebuilds.

## Installation

The recommended way to automatically include FetchDependency in your project is to use CMake's
[FetchContent](https://cmake.org/cmake/help/latest/module/FetchContent.html) module:

```cmake
include(FetchContent)
FetchContent_Declare(FetchDependency
  GIT_REPOSITORY https://github.com/jpetrie/fetch-dependency.git
  GIT_TAG origin/main
)
FetchContent_MakeAvailable(FetchDependency)
include(${fetchdependency_SOURCE_DIR}/FetchDependency.cmake")
```

Other options include using Git submodules or subtrees to import this repository, or simply downloading the code to a
suitable location.

FetchDependency requires CMake 3.19 or later.

## Usage

FetchDependency provides a single function, `fetch_dependency()`, which will fetch and find a dependency package:

```cmake
  fetch_dependency(Catch2 GIT_REPOSITORY https://github.com/catchorg/Catch2.git GIT_TAG v2.13.8)
```

This will fetch, configure, build and install [Catch2](https://github.com/catchorg/Catch2) within the calling project's
CMake binary directory. It will then call `find_package()` to locate the dependency and make it available to future
targets:

```cmake
  target_link_libraries(... Catch2::Catch2)
```

The source code of the FetchDependency module contains detailed documentation of `fetch_dependency()`'s behavior and
options.
