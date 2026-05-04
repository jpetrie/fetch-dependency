#include "B/B.hpp"

#include <A/A.hpp>

#include <iostream>

namespace b {
  int test() {
    a::test();

    std::cout << "This is library B.\n";
    return 0;
  }
}

