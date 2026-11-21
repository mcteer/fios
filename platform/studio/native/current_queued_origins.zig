//! Current queued-request attribution. No admission or terminal authority.
const std = @import("std");
const owners = @import("request_ownership.zig");
const slots = @import("current_slot_origins.zig");
pub const Scope = slots.Scope;

// Pointer views keep this adapter bounded without copying 256 complete token
// arrays onto the worker stack. The tested union helper clones before return;
// no sender/view storage is borrowed by the returned scope or by worker TLS.
pub fn retain(io: std.Io, requests: anytype) !?Scope {
    if (requests.len > owners.capacity) {
        owners.shared().fence(io);
        return error.InvalidQueuedOrigins;
    }
    const View = struct { fios_owner: ?*const owners.Retained };
    var views: [owners.capacity]View = undefined;
    var pointers: [owners.capacity]*View = undefined;
    for (requests, 0..) |request, index| {
        views[index] = .{ .fios_owner = request.fios_origins };
        pointers[index] = &views[index];
    }
    return try slots.retain(io, pointers[0..requests.len]);
}
