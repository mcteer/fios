// Genuine source diagnostic API, one empty Metal buffer and deliberate raw
// alias. Physical buffers drain; uncertainty is never refunded/terminal proof.
#include "mlx/stream.h"
#include "mlx/backend/metal/device.h"
#include <cstdio>
using namespace mlx::core;
int main(){
 if(!fios_enable_stream_custody_fixture()||fios_first_uncertainty_site()!=0)return 77;
 const auto stream=new_stream(Device::gpu);
 auto& encoder=metal::get_command_encoder(stream);
 if(!encoder.get_command_buffer())return 77; // Deliberate genuine raw escape.
 encoder.synchronize();
 const auto first=fios_first_uncertainty_site();
 if(first!=23||!fios_metal_buffer_state().uncertain)return 77;
 if(!encoder.get_command_buffer())return 77;
 encoder.synchronize();
 if(fios_first_uncertainty_site()!=first)return 77;
 std::puts("PASS: genuine exported first-uncertainty accessor, raw-alias site and sticky first failure; no model/terminal authority.");
 return 0;
}
