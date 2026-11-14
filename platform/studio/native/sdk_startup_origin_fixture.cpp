// Existing genuine CPU callback chain plus an exact mapped-library check.
#include "sdk_host_owners_fixture.cpp"
#include <dlfcn.h>
#include <limits.h>
#include <cstdlib>
#include <cstring>
extern "C" int fios_startup_sdk_library_is_selected(const char* expected) {
  Dl_info info{};
  if (!expected || !dladdr(reinterpret_cast<const void*>(&mx::fios_host_queue_state), &info)) return 0;
  char mapped[PATH_MAX], requested[PATH_MAX];
  return realpath(info.dli_fname, mapped) && realpath(expected, requested) &&
      std::strcmp(mapped, requested) == 0;
}
