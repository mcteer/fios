const std = @import("std");
pub const Outcome = enum(u8) { not_requested, owner_streams_synchronized, blocked, wrong_owner, streams_changed, failed, timed_out };
pub const Reading = struct { outcome: Outcome = .blocked, streams: u32 = 0 };
const CResult = extern struct { seen: u32 = 0, synchronized: u32 = 0 };
extern "c" fn fios_mlx_current_thread() u64;
extern "c" fn fios_mlx_owner_barrier(owner: u64, result: *CResult) c_int;
extern "c" fn fios_mlx_initialize_owner_defaults(owner: u64) c_int;
pub fn initializeDefaults(owner: u64) bool { return fios_mlx_initialize_owner_defaults(owner) == 0; }
pub fn currentThread() u64 { return fios_mlx_current_thread(); }
pub fn synchronize(owner: u64) Reading {
    var result: CResult = .{};
    const status = fios_mlx_owner_barrier(owner, &result);
    if (status == 0 and result.seen == result.synchronized and result.seen <= 256)
        return .{ .outcome = .owner_streams_synchronized, .streams = result.synchronized };
    return .{ .outcome = switch (status) { 1 => .wrong_owner, 2 => .streams_changed, else => .failed } };
}
// Optional partial bridge-creation metadata hold. These hooks do NOT reserve
// raw MLX, model/context lifetime, other backends or all native transitions.
pub const RegistryHooks = struct {
    acquire: *const fn (u64) ?u64,
    release: *const fn (u64, u64) bool,
};
extern "c" fn fios_mlx_hold_owned_registry(owner: u64, ticket: *u64) c_int;
extern "c" fn fios_mlx_release_owned_registry(owner: u64, ticket: u64) c_int;
fn acquireOwnedRegistry(owner: u64) ?u64 {
    var ticket: u64 = 0;
    if (fios_mlx_hold_owned_registry(owner, &ticket) != 0 or ticket == 0) return null;
    return ticket;
}
fn releaseOwnedRegistry(owner: u64, ticket: u64) bool {
    return fios_mlx_release_owned_registry(owner, ticket) == 0;
}
pub fn ownedRegistryHooks() RegistryHooks { return .{ .acquire = acquireOwnedRegistry, .release = releaseOwnedRegistry }; }
// Scheduler parking with optional partial bridge metadata hold, NOT backend
// terminality or an all-model/backend transition reservation. No age, failed
// probe or foreign snapshot releases either hold.
pub const ActorPauseHold = struct {
    instance: [16]u8 = @splat(0),
    sequence: u64 = 0,
    registry: ?struct { owner: u64, ticket: u64, hooks: RegistryHooks } = null,
    pub fn reserveOwnedRegistry(self: *ActorPauseHold, owner: u64, hooks: RegistryHooks) !void {
        if (self.sequence == 0) return error.InvalidPause;
        if (self.registry) |held| {
            if (held.owner != owner) return error.WrongOwner;
            return; // Never retarget the existing ticket/release hook.
        }
        const ticket = hooks.acquire(owner) orelse return error.Unavailable;
        if (ticket == 0) return error.Unavailable;
        self.registry = .{ .owner = owner, .ticket = ticket, .hooks = hooks };
    }
    pub fn reserve(self: *ActorPauseHold, instance: [16]u8, sequence: u64) !void {
        if (sequence == 0 or (self.sequence != 0 and
            (!std.mem.eql(u8, &self.instance, &instance) or sequence < self.sequence))) return error.InvalidPause;
        self.instance = instance;
        self.sequence = sequence;
    }
    pub fn blocks(self: *ActorPauseHold, instance: [16]u8, paused: bool, sequence: u64) bool {
        if (self.sequence == 0) return false;
        // Same tracker can expose open/newer pause only after exact resume.
        if (std.mem.eql(u8, &self.instance, &instance) and
            ((!paused and sequence == 0) or (paused and sequence > self.sequence))) {
            if (self.registry) |held| {
                if (!held.hooks.release(held.owner, held.ticket)) return true;
                self.registry = null;
            }
            self.sequence = 0;
            return false;
        }
        return true;
    }
};
// Two references: parked sender and scheduler. Sender timeout never frees a
// queued/executing request. One scheduler slot stays occupied until completion.
pub const Request = struct {
    allocator: std.mem.Allocator,
    references: std.atomic.Value(u32) = .init(2),
    done_mu: std.Io.Mutex = .init,
    done_cond: std.Io.Condition = .init,
    done: bool = false,
    reading: Reading = .{},
    instance: [16]u8,
    pause_sequence: u64,
    pub fn release(self: *Request) void {
        if (self.references.fetchSub(1, .acq_rel) == 1) self.allocator.destroy(self);
    }
};
