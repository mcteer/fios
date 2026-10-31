// Genuine MLX host scheduler tasks only; no arrays, kernels, models or GPU.
#include "mlx/scheduler.h"
#include "mlx/backend/cpu/eval.h"
#include "mlx/stream.h"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <future>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>
using namespace mlx::core;
using namespace std::chrono_literals;
static void require(bool condition) { if (!condition) { std::fputs("FAIL: host-queue custody assertion\n",stderr);std::exit(77); } }
static void clear_mode(const std::string& mode) {
 if(mode.starts_with("--cpu-clear")) {
#ifdef FIOS_CPU_PRIVATE_FIXTURE
  cpu::clear_streams();return;
#else
  require(false);
#endif
 }
 clear_streams();
}
static void wait(std::future<void>& signal) {require(signal.wait_for(3s)==std::future_status::ready);signal.get();}
static FiosHostQueueState retired() {
 const auto end=std::chrono::steady_clock::now()+3s;
 while(std::chrono::steady_clock::now()<end){auto state=fios_host_queue_state();if(!state.pending&&!state.active)return state;std::this_thread::sleep_for(1ms);}
 require(false);return {};
}
static uint64_t hold_and_resume() {
 const auto creation=fios_hold_stream_creation(fios_host_queue_state().epoch);require(creation);
 const auto gate=fios_hold_host_queues(creation,fios_host_queue_state().epoch);require(gate);
 require(!fios_release_stream_creation(creation));
 bool foreign=true;std::thread other([&]{foreign=fios_release_host_queues(gate);});other.join();require(!foreign);
 require(fios_host_queue_state().held);
 require(fios_release_host_queues(gate));require(!fios_release_host_queues(gate));require(!fios_release_stream_creation(creation));return gate;
}
int main(int argc,char** argv) {
 require(argc==2);const std::string mode=argv[1];
 if(mode=="--assertion-negative"){require(false);}
 if(mode=="--clear-before-enable"||mode=="--cpu-clear-before-enable"){
  clear_mode(mode);
  require(!fios_enable_stream_custody_fixture());
 }else if(mode=="--default-off"){
  const auto stream=new_stream(Device::cpu);std::promise<void> ran;auto future=ran.get_future();
  scheduler::enqueue(stream,[&]{ran.set_value();});wait(future);
  require(!fios_host_queue_state().enabled);require(!fios_enable_stream_custody_fixture());
 }else{
  require(fios_enable_stream_custody_fixture());const auto stream=new_stream(Device::cpu);
  if(mode=="--clear-held"||mode=="--cpu-clear-held"){
   const auto creation=fios_hold_stream_creation(fios_host_queue_state().epoch);require(creation);
   const auto gate=fios_hold_host_queues(creation,fios_host_queue_state().epoch);require(gate);
   bool blocked=false;try{clear_mode(mode);}catch(const std::runtime_error&){blocked=true;}
   if(!blocked){std::fputs(mode=="--cpu-clear-held"?"CPU_STREAM_TEARDOWN_ALLOWED_WHILE_HELD\n":"STREAM_TEARDOWN_ALLOWED_WHILE_HELD\n",stderr);std::exit(77);}
   require(fios_host_queue_state().held&&fios_stream_custody_state().held&&!fios_host_queue_state().uncertain);
   require(fios_release_host_queues(gate));
  }else if(mode=="--clear-unheld"||mode=="--cpu-clear-unheld"){
   clear_mode(mode);require(fios_host_queue_state().uncertain);require(!fios_hold_stream_creation(fios_host_queue_state().epoch));
  }else if(mode=="--pending"){
   std::promise<void> entered,released;auto begin=entered.get_future();auto release=released.get_future().share();
   scheduler::enqueue(stream,[&]{entered.set_value();release.wait();});wait(begin);
   auto state=fios_host_queue_state();require(state.pending==1&&state.active==1&&!state.uncertain);
   std::promise<void> queued;auto queued_done=queued.get_future();scheduler::enqueue(stream,[&]{queued.set_value();});
   state=fios_host_queue_state();require(state.pending==2&&state.active==1&&!state.uncertain);
   const auto creation=fios_hold_stream_creation(state.epoch);require(creation);
   require(!fios_hold_host_queues(creation,fios_host_queue_state().epoch));
   released.set_value();wait(queued_done);state=retired();require(!state.uncertain);
   const auto gate=fios_hold_host_queues(creation,state.epoch);require(gate);
   bool blocked=false;try{scheduler::enqueue(stream,[]{});}catch(const std::runtime_error&){blocked=true;}
   if(!blocked){std::fputs("HOST_GATE_ALLOWED_SUBMISSION\n",stderr);std::exit(77);}
   require(fios_host_queue_state().pending==0);
   require(fios_release_host_queues(gate));
   std::promise<void> rearmed;auto done=rearmed.get_future();scheduler::enqueue(stream,[&]{rearmed.set_value();});wait(done);require(!retired().uncertain);
  }else if(mode=="--capture-retire"){
   std::promise<void> destroying,released;auto entered=destroying.get_future();auto release=released.get_future().share();
   auto payload=std::shared_ptr<int>(new int(1),[&](int* value){destroying.set_value();release.wait();delete value;});
   scheduler::enqueue(stream,[payload=std::move(payload)]{});wait(entered);
   // Callback has returned, but its actual captured payload is not destroyed.
   const auto state=fios_host_queue_state();
   if(state.pending!=1||state.active!=1){std::fputs("EARLY_HOST_TASK_RETIREMENT\n",stderr);std::exit(77);}
   require(!state.uncertain);
   const auto creation=fios_hold_stream_creation(state.epoch);require(creation);
   require(!fios_hold_host_queues(creation,fios_host_queue_state().epoch));
   released.set_value();require(!retired().uncertain);
   const auto gate=fios_hold_host_queues(creation,fios_host_queue_state().epoch);require(gate);require(fios_release_host_queues(gate));
  }else if(mode=="--foreign"){
   std::promise<void> ran;auto done=ran.get_future();std::thread other([&]{scheduler::enqueue(stream,[&]{ran.set_value();});});other.join();wait(done);
   require(fios_host_queue_state().uncertain);require(!fios_hold_stream_creation(fios_host_queue_state().epoch));
  }else if(mode=="--failure"){
   std::promise<void> ran;auto done=ran.get_future();scheduler::enqueue(stream,[&]{ran.set_value();throw std::runtime_error("owned test task failure");});wait(done);
   require(retired().uncertain);require(!fios_hold_stream_creation(fios_host_queue_state().epoch));
  }else if(mode=="--owner-exit"){
   uint64_t creation=0,gate=0;
   std::thread creator([&]{(void)new_stream(Device::cpu);creation=fios_hold_stream_creation(fios_host_queue_state().epoch);require(creation);gate=fios_hold_host_queues(creation,fios_host_queue_state().epoch);require(gate);});creator.join();
   require(!fios_release_host_queues(gate));require(!fios_release_stream_creation(creation));require(fios_host_queue_state().held);
  }else if(mode=="--exhausted-host-release"){
   const auto creation=fios_hold_stream_creation(fios_host_queue_state().epoch);require(creation);
   const auto gate=fios_hold_host_queues(creation,fios_host_queue_state().epoch);require(gate);
   require(!fios_release_host_queues(gate));
   if(!fios_host_queue_state().held||!fios_stream_custody_state().held){std::fputs("HOST_RELEASE_CLEARED_ON_EXHAUSTION\n",stderr);std::exit(77);}
   require(fios_host_queue_state().uncertain);
  }else if(mode=="--exact-release"){
   const auto old=hold_and_resume();
   const auto creation=fios_hold_stream_creation(fios_host_queue_state().epoch);require(creation);
   const auto gate=fios_hold_host_queues(creation,fios_host_queue_state().epoch);require(gate&&gate!=old);
   require(!fios_release_host_queues(old)&&!fios_release_host_queues(gate+1));require(fios_host_queue_state().held);require(fios_release_host_queues(gate));
   std::promise<void> ran;auto done=ran.get_future();scheduler::enqueue(stream,[&]{ran.set_value();});wait(done);require(!retired().uncertain);
  }else require(false);
 }
 std::puts("PASS: genuine MLX host queue fixture; scoped task/payload retirement only, no device/model/lifecycle authority.");
}
