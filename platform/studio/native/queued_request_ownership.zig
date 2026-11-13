//! Trusted in-process queue custody only. No admission or terminal authority.
const std = @import("std");
const owners = @import("request_ownership.zig");

pub const Scope = struct {
    retained: owners.Retained,
    previous: ?owners.Token = null,
    previous_group: ?[]const owners.Token = null,
    state: enum { captured, entered, closed, uncertain } = .captured,

    // Clone before the sender can finish its uncancelable handoff. Never
    // borrow its token-array storage across acknowledgement or cleanup.
    pub fn retain(io: std.Io, origin: *const owners.Retained) !Scope {
        if (origin.tracker != &owners.shared or origin.count == 0 or origin.count > owners.capacity) {
            owners.shared.fence(io);
            return error.InvalidQueuedOrigins;
        }
        return .{ .retained = try owners.shared.retainTokens(io, origin.tokens[0..origin.count]) };
    }
    // Called only after this object has stable storage on its original worker.
    pub fn enter(self: *Scope, io: std.Io) !void {
        if (self.state != .captured) {
            owners.shared.fence(io);
            self.state = .uncertain;
            return error.InvalidQueuedScope;
        }
        self.previous = owners.current;
        self.previous_group = owners.current_group;
        owners.current = null;
        owners.current_group = self.retained.tokens[0..self.retained.count];
        self.state = .entered;
    }
    pub fn finish(self: *Scope, io: std.Io) bool {
        if (self.state != .entered) {
            owners.shared.fence(io);
            self.state = .uncertain;
            return false;
        }
        owners.current = self.previous;
        owners.current_group = self.previous_group;
        // Local completion cannot clear an independently known source fence.
        const released = !self.retained.tracker.backendKnownUncertain(io) and self.retained.releaseIfCertain(io);
        self.state = if (released) .closed else .uncertain;
        return released;
    }
};
