// Genuine SDK metadata boundary only. No physical GPU completion is claimed.
#include "mlx/stream.h"
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>
using namespace mlx::core;
int main(int argc,char** argv){
 if(argc!=2||!fios_enable_stream_custody_fixture())return 77;
 const bool global=std::string(argv[1])=="--global";
 if(!global&&std::string(argv[1])!="--per-buffer")return 77;
 const auto stream=new_stream(Device::gpu);
 std::vector<std::shared_ptr<FiosMetalBuffer>> buffers;
 std::vector<std::shared_ptr<FiosMetalCapture>> captures;
 for(unsigned b=0;b<(global?4u:1u);++b){
  auto buffer=fios_reserve_metal_buffer(stream.index);if(!buffer)return 77;
  buffers.push_back(buffer);
  for(unsigned n=0;n<4096;++n){
   auto capture=fios_metal_capture_begin(buffer);
   if(!capture){std::fputs("CAPTURE_BUDGET_REFUSED_BEFORE_REVIEWED_BOUND\n",stderr);std::fflush(nullptr);std::_Exit(77);}
   captures.push_back(capture);
  }
 }
 auto target=global?fios_reserve_metal_buffer(stream.index):buffers.back();
 if(!target||fios_metal_capture_begin(target)||fios_first_uncertainty_site()!=(global?27u:26u))return 77;
 const auto state=fios_metal_buffer_state();
 if(!state.uncertain||state.captures!=(global?16384u:4096u))return 77;
 std::puts("PASS: exact finite capture budget and exhaustion retain all outstanding metadata/uncertainty; deliberate exit, no physical retirement proof.");
 std::fflush(nullptr);std::_Exit(0);
}
