# FetchDependency

FetchDependency is a CMake module that provides a mechanism to download, configure, build and install (local to the
calling project) a dependency package at configuration time.

FetchDependency is designed to enable dependency handling in CMake according to a specific philosophy. It offers:

 - A project's dependencies should be made available automatically, in order to facilitate the quickest turnaround
   from cloning a project to a successful build.
 - A project's dependencies should be stored with it by default, rather than a global location, in order to isolate
   the project from changes made outside the project.
 - A project's dependencies should not pollute the targets of the project or any other dependencies, in order to 
   avoid target name collisions and keep an IDE's target list (when an IDE is used) focused.

The cost of both of the aforementioned features is increased configuration time for the calling project (especially
during initial configuration) as all dependencies are downloaded and built from source. To alleviate the impact on
configuration time, FetchDependency tracks the fetched and configured version of each dependency. Only if the tracking
file is missing or refers to a different version will FetchDependency actually re-do the fetch, configure and build
steps.

## Installation

Use Git submodules or subtrees to import the FetchDependency repository into your project repository, or simply
download the code and place it in a suitable directory. Ensure your project's `CMAKE_MODULE_PATH` includes the
directory containing FetchDependency, and then `include(FetchDependency)` in your `CMakeLists.txt`.

FetchDependency requires CMake 3.19 or later.

## Usage

FetchDependency provides a single function, `fetch_dependency()`, which will fetch and find a dependency package:

    fetch_dependency(Catch2 GIT_REPOSITORY https://github.com/catchorg/Catch2.git GIT_TAG v2.13.8)

This will fetch, configure, build and install [Catch2](https://github.com/catchorg/Catch2) within the calling project's
CMake binary directory. It will then call `find_package()` to locate the dependency and make it available to future
targets:

    target_link_libraries(... Catch2::Catch2)

The source code of the FetchDependency module contains detailed documentation of `fetch_dependency()`'s behavior and
options.
