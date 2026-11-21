//! Host implementation of the SDK's opaque pure-CPU ownership hook.
const std = @import("std");
const owners = @import("request_ownership.zig");
const queue = @import("queued_request_ownership.zig");
const sdk = @import("../sdk/media/offload_origins.zig");
const State = struct { io: std.Io, scope: queue.Scope };
comptime {
    if (@sizeOf(State) > @sizeOf(sdk.Payload) or @alignOf(State) > @alignOf(sdk.Payload))
        @compileError("CPU media ownership exceeds its fixed opaque payload");
}
const hooks: sdk.Hooks = .{ .capture = capture, .enter = enter, .finish = finish, .abandon = abandon };
pub fn install() !void { try sdk.install(&hooks); }
fn state(payload: *sdk.Payload) *State { return @ptrCast(@alignCast(payload)); }
fn capture(payload: *sdk.Payload) sdk.Capture {
    const io = std.Io.Threaded.global_single_threaded.io();
    const original = owners.retainCurrent(io) catch return .failed;
    const held = original orelse return .unavailable;
    state(payload).* = .{ .io = io, .scope = .{ .retained = held } };
    return .retained;
}
fn enter(payload: *sdk.Payload) bool {
    const s = state(payload);
    s.scope.enter(s.io) catch return false;
    return true;
}
fn finish(payload: *sdk.Payload) void {
    const s = state(payload);
    _ = s.scope.finish(s.io);
}
fn abandon(payload: *sdk.Payload) void {
    const s = state(payload);
    if (s.scope.state != .captured) { owners.shared().fence(s.io); return; }
    // No worker started. Release only this local capture, preserving any
    // independent native uncertainty and all native-object custody.
    if (!s.scope.retained.tracker.backendKnownUncertain(s.io))
        _ = s.scope.retained.releaseIfCertain(s.io);
}
