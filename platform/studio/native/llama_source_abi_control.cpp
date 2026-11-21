#include "llama.h"
#include <cstdio>
#include <cstring>
int main() {
 const auto m=llama_model_default_params(); const auto c=llama_context_default_params();
 auto b=llama_batch_init(2,0,1);
 if(b.n_tokens!=0||!b.token||!b.pos||!b.n_seq_id||!b.seq_id||!b.logits) return 1;
 b.n_tokens=2;b.token[0]=7;b.token[1]=11;b.pos[0]=0;b.pos[1]=1;
 for(int i=0;i<2;i++){b.n_seq_id[i]=1;b.seq_id[i][0]=0;b.logits[i]=i==1;}
 if(b.token[1]!=11||b.pos[1]!=1||b.seq_id[1][0]!=0||!b.logits[1])return 2;
 llama_batch_free(b);
 std::printf("{\"version\":\"%s\",\"model_params_bytes\":%zu,\"context_params_bytes\":%zu,\"gpu_layers\":%d,\"load_mode\":%d,\"context\":%u,\"batch\":%u,\"ubatch\":%u,\"sequences\":%u,\"threads\":%d,\"batch_threads\":%d,\"batch_roundtrip\":true}\n",llama_version(),sizeof(m),sizeof(c),m.n_gpu_layers,m.load_mode,c.n_ctx,c.n_batch,c.n_ubatch,c.n_seq_max,c.n_threads,c.n_threads_batch);
 return 0;
}
