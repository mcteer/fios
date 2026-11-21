// Private reviewed-source composition only. Registration is not enrollment,
// native terminality, all-client coverage or admission authority.
#include "ds4_gpu.h"
#include <cstdlib>
#ifndef DS4_GPU_REQUEST_OWNER_HOOKS
#error "Reviewed DS4 request-owner hooks are required"
#endif
extern "C" void* fios_native_request_owners_capture();
extern "C" uint64_t fios_native_request_owners_enter(void*);
extern "C" int fios_native_request_owners_leave(uint64_t);
extern "C" void fios_native_request_owners_release(void*);
extern "C" void* fios_native_request_owners_merge(void*,void*);
extern "C" int fios_native_request_owners_covers_current(void*);
extern "C" void fios_native_request_owners_uncertain();
namespace {
__attribute__((constructor)) void register_current_source_ds4_owners() {
    static const ds4_gpu_request_owner_hooks hooks{
        fios_native_request_owners_capture,fios_native_request_owners_enter,
        fios_native_request_owners_leave,fios_native_request_owners_release,
        fios_native_request_owners_merge,fios_native_request_owners_covers_current,
        fios_native_request_owners_uncertain};
    if (!ds4_gpu_register_request_owner_hooks(&hooks)) std::_Exit(78);
}
}
