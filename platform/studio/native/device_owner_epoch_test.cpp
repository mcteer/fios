// Actual project bridge implementation + genuine MLX/C SDK, not fake APIs.
// Explicit metadata boundary: epoch exhaustion cannot clear an exact hold.
#include "device_owner_barrier.cpp"
#include <cstdio>
int main(){
 const auto owner=fios_mlx_current_thread();
 if(!owner||fios_mlx_create_owned_cpu_stream(owner)!=0)return 78;
 uint64_t ticket=0;
 if(fios_mlx_hold_owned_registry(owner,&ticket)!=0||!ticket)return 78;
 {
  std::lock_guard lock(registry.mutex);
  registry.epoch=std::numeric_limits<uint64_t>::max();
 }
 const int result=fios_mlx_release_owned_registry(owner,ticket);
 if(result==0)return 78;
 {
  std::lock_guard lock(registry.mutex);
  if(registry.hold!=ticket||registry.hold_owner!=local.owner){
   std::fputs("OWNED_BRIDGE_RELEASE_CLEARED_ON_EXHAUSTION\n",stderr);return 77;
  }
  if(!registry.uncertain||registry.epoch!=std::numeric_limits<uint64_t>::max())return 78;
 }
 std::puts("PASS: actual owned bridge retains exact hold/uncertainty on epoch exhaustion; metadata boundary only, NOT terminality/lifecycle authority");
}
