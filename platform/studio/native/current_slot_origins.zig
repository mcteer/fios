//! Current-source actor attribution only. No admission or terminal authority.
const std = @import("std");
const owners = @import("request_ownership.zig");
const queue = @import("queued_request_ownership.zig");
pub const Scope = queue.Scope;

// Slots remain alive under their existing in_pass/cleanup custody while this
// immutable union is cloned. Never borrow a slot's token-array storage into TLS.
pub fn retain(io: std.Io, slots: anytype) !?Scope {
    var tokens: [owners.capacity]owners.Token = undefined;
    var count: usize = 0;
    var missing = false;
    for (slots) |slot| {
        const held = slot.fios_owner orelse { missing = true; continue; };
        if (held.tracker != owners.shared() or held.count == 0 or held.count > owners.capacity)
            return invalid(io);
        for (held.tokens[0..held.count]) |token| {
            var duplicate = false;
            for (tokens[0..count]) |existing| {
                if (existing.slot != token.slot) continue;
                if (!std.meta.eql(existing, token)) return invalid(io);
                duplicate = true;
                break;
            }
            if (duplicate) continue;
            if (count == tokens.len) return invalid(io);
            tokens[count] = token;
            count += 1;
        }
    }
    // Unattributed legacy actors remain unavailable diagnostics, never empty
    // all-client evidence. A partially attributed batch cannot drop its peers.
    if (count == 0) return null;
    if (missing) return invalid(io);
    const origins: owners.Retained = .{ .tracker = owners.shared(), .tokens = tokens, .count = count };
    return try Scope.retain(io, &origins);
}
fn invalid(io: std.Io) error{InvalidSlotOrigins} {
    owners.shared().fence(io);
    return error.InvalidSlotOrigins;
}
