//! Optional trusted source-SDK host callback ownership. Local reference/TLS
//! custody only, never all-client coverage, device completion or a wire API.
const std = @import("std");
const owners = @import("request_ownership.zig");
pub const maximum_contexts = 4096;
const maximum_depth = 64;
const Context = struct { retained: owners.Retained };
const Frame = struct { previous: ?owners.Token, group: ?[]const owners.Token, sequence: u64 };
var state: std.atomic.Value(u8) = .init(0); // absent, configuring, ready; never reset
var source_io: ?std.Io = null;
var contexts: std.atomic.Value(u32) = .init(0);
var next_scope: std.atomic.Value(u64) = .init(0);
var failed: std.atomic.Value(bool) = .init(false);
threadlocal var frames: [maximum_depth]Frame = undefined;
threadlocal var depth: usize = 0;

pub fn initialize(io: std.Io) !void {
    if (state.cmpxchgStrong(0, 1, .acq_rel, .acquire) != null) return error.AlreadyConfigured;
    source_io = io;
    if (!owners.shared.initialized or failed.load(.acquire)) {
        failed.store(true, .release);
        owners.shared.fence(io);
        return error.Unavailable;
    }
    state.store(2, .release);
}
fn fence() void {
    failed.store(true, .release);
    if (state.load(.acquire) == 2) owners.shared.fence(source_io.?);
}
pub const Diagnostic = struct { active_contexts: u32, uncertain: bool };
pub fn diagnostic() Diagnostic {
    return .{ .active_contexts = contexts.load(.acquire), .uncertain = failed.load(.acquire) };
}

// Called only by an immutable compiled SDK hook. A nil result outside an
// attributed native scope is unavailable, not evidence of zero model work.
pub export fn fios_native_request_owners_capture() ?*anyopaque {
    if (state.load(.acquire) != 2 or failed.load(.acquire)) return null;
    const io = source_io.?;
    const retained = owners.retainCurrent(io) catch { fence(); return null; } orelse return null;
    var count = contexts.load(.acquire);
    while (true) {
        if (count >= maximum_contexts) {
            // Retain the already-acquired original references on uncertainty.
            // No age, queue count or local cleanup can refund a lost context.
            fence(); return null;
        }
        if (contexts.cmpxchgWeak(count, count + 1, .acq_rel, .acquire)) |actual| count = actual else break;
    }
    const context = std.heap.c_allocator.create(Context) catch {
        // Preserve original references even when no descriptor can allocate.
        _ = contexts.fetchSub(1, .acq_rel);
        fence();
        return null;
    };
    context.* = .{ .retained = retained };
    return @ptrCast(context);
}
// Context addresses are private compiled-SDK values, never wire/model input.
// The SDK owns their shared lifetime through the complete callback cleanup.
pub export fn fios_native_request_owners_release(raw: ?*anyopaque) void {
    const context: *Context = @ptrCast(@alignCast(raw orelse { fence(); return; }));
    if (state.load(.acquire) != 2) { fence(); return; }
    if (failed.load(.acquire)) return; // Quarantine original descriptor/references.
    context.retained.release(source_io.?);
    std.heap.c_allocator.destroy(context);
    _ = contexts.fetchSub(1, .acq_rel);
}
pub export fn fios_native_request_owners_enter(raw: ?*anyopaque) u64 {
    if (state.load(.acquire) != 2 or failed.load(.acquire) or depth == maximum_depth) { fence(); return 0; }
    const context: *Context = @ptrCast(@alignCast(raw orelse { fence(); return 0; }));
    if (context.retained.tracker != &owners.shared or context.retained.count == 0 or context.retained.count > owners.capacity) { fence(); return 0; }
    var sequence = next_scope.load(.acquire);
    while (true) {
        if (sequence == std.math.maxInt(u64)) { fence(); return 0; }
        if (next_scope.cmpxchgWeak(sequence, sequence + 1, .acq_rel, .acquire)) |actual| sequence = actual else break;
    }
    sequence += 1;
    frames[depth] = .{ .previous = owners.current, .group = owners.current_group, .sequence = sequence };
    depth += 1;
    owners.current = context.retained.tokens[0];
    owners.current_group = context.retained.tokens[0..context.retained.count];
    return sequence;
}
pub export fn fios_native_request_owners_leave(sequence: u64) c_int {
    if (state.load(.acquire) != 2 or depth == 0 or sequence == 0 or frames[depth - 1].sequence != sequence) { fence(); return 1; }
    const original = frames[depth - 1];
    depth -= 1;
    owners.current = original.previous;
    owners.current_group = original.group;
    return 0;
}
