#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Native-internal MLX primitive, NOT all-client quiescence/coverage authority.
// Caller must close admission, drain roots/queues, hold registry transitions
// and account for every other backend. owner_thread is captured by that actual
// device-owner thread at startup, never accepted from a model/wire request.
// Counts cover only the current recorded owner, not every registered owner.
// Other live/retired owners remain unresolved; no aggregate receipt exists.
struct fios_mlx_barrier_result {
    uint32_t streams_seen;
    uint32_t streams_synchronized;
};
enum fios_mlx_barrier_status {
    FIOS_MLX_OWNER_STREAMS_SYNCHRONIZED = 0,
    FIOS_MLX_WRONG_OWNER = 1,
    FIOS_MLX_STREAMS_CHANGED = 2,
    FIOS_MLX_UNSUPPORTED_OR_FAILED = 3,
    FIOS_MLX_INVALID = 4
};
uint64_t fios_mlx_current_thread(void);
// Creates and records a genuine CPU stream on this owner. No arbitrary stream
// registration/adoption: public get_streams alone cannot prove its owner or
// distinguish global thread-unsafe encoders. Additional native/model streams
// remain unsupported until their creation/owners are enrolled as explicitly.
int fios_mlx_create_owned_cpu_stream(uint64_t owner_thread);
// Creates a real owned stream AND genuine mlx-c handle on the same thread.
// type0=CPU/type1=GPU, device0 only. No existing stream ID is accepted.
// On success out_context is mlx_stream.ctx, freed with mlx_stream_free;
// failure leaves it NULL. No inference or synchronization receipt is implied.
int fios_mlx_create_owned_c_stream(uint64_t owner_thread, uint32_t type, int32_t device, void** out_context);
// Same handle contract, but preserve the genuine thread-local default.
// Create/record only if absent; return a fresh handle only when a preexisting
// default has THIS actual recorded creation owner. Never adopt foreign/global.
int fios_mlx_owned_default_c_stream(uint64_t owner_thread, uint32_t type, int32_t device, void** out_context);
// Source fixture only: before ANY default exists on this thread, create and
// record genuine CPU/GPU defaults. Refuse preexisting defaults, never adopt.
// No arrays/models/kernels. Not other-thread/backend enrollment or authority.
int fios_mlx_initialize_owner_defaults(uint64_t owner_thread);
int fios_mlx_owner_barrier(uint64_t owner_thread, struct fios_mlx_barrier_result* result);
// Partial metadata hold ONLY: atomically excludes this bridge's registered
// stream-creation wrappers while held, without retaining a mutex across I/O.
// NOT a reservation of raw MLX APIs, default-handle clones, device encoders,
// model/context lifetime, other backend actors or native lifecycle authority.
// Returns0 for a granted hold (NOT synchronization); output is0 on failure.
// Exact creator-local non-reusable owner and one-use ticket release only.
// No timeout, thread exit or failed probe refunds/reopens this hold.
int fios_mlx_hold_owned_registry(uint64_t owner_thread, uint64_t* out_ticket);
int fios_mlx_release_owned_registry(uint64_t owner_thread, uint64_t ticket);
#ifdef __cplusplus
}
#endif
