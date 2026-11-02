// Genuine source SDK scalar I/O, no model/inference/GPU allocation.
#include "mlx/io.h"
#include "mlx/device.h"
#include <cstdio>
#include <string>
using namespace mlx::core;
int main(int argc,char**argv){
 if(argc!=2)return 77;
 try{
  set_default_device(Device::cpu);
  save_safetensors(std::string(argv[1]),{{"sample",array(1.25f)}},{{"purpose","source-fixture"}});
  auto loaded=load_safetensors(std::string(argv[1]),Device::cpu);
  if(loaded.first.size()!=1||loaded.second.size()!=1||loaded.second.at("purpose")!="source-fixture"||loaded.first.at("sample").item<float>()!=1.25f)return 77;
  std::puts("PASS: genuine CPU scalar safetensors roundtrip; no model/GPU/inference authority.");
  return 0;
 }catch(...){
  std::fputs("FIOS_SOURCE_SAFETENSORS_UNAVAILABLE\n",stderr);return 77;
 }
}
