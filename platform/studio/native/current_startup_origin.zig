//! Startup CPU/load custody only. No native completion or admission authority.
const std = @import("std");
const owners = @import("request_ownership.zig");
const queue = @import("queued_request_ownership.zig");
pub const Scope = struct {
    queued: queue.Scope,
    // Reserve before thread publication. The reservation's single reference
    // moves with the context; TLS is installed only in stable worker storage.
    pub fn capture(io: std.Io, model: []const u8) !Scope {
        const token = try owners.shared().reservePreparation(io, null, model);
        var retained: owners.Retained = .{ .tracker = owners.shared(), .count = 1 };
        retained.tokens[0] = token;
        return .{ .queued = .{ .retained = retained } };
    }
    pub fn enter(self: *Scope, io: std.Io) !void { try self.queued.enter(io); }
    pub fn finish(self: *Scope, io: std.Io) bool { return self.queued.finish(io); }
    // Only the failed spawn edge calls this: no worker received the context.
    // Independent uncertainty still retains the original reservation.
    pub fn unpublished(self: *Scope, io: std.Io) bool {
        if (self.queued.state != .captured) {
            owners.shared().fence(io);
            self.queued.state = .uncertain;
            return false;
        }
        const released = !owners.shared().backendKnownUncertain(io) and self.queued.retained.releaseIfCertain(io);
        self.queued.state = if (released) .closed else .uncertain;
        return released;
    }
};
