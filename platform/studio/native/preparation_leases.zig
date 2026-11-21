//! Bounded single-use CPU preparation bridge. No coverage/device/capacity proof.
//! Not installed or callable from model-facing management. Unsupported native
//! source guards continue to refuse in the existing registry claim operation.
const std = @import("std");
const owners = @import("request_ownership.zig");
const claims = @import("current_registry_claim.zig");
pub const capacity = 32;
pub const Handle = struct { instance: [16]u8, correlation: owners.CorrelationID, root: u64 };
const Entry = struct {
    token: owners.Token,
    correlation: owners.CorrelationID,
    model: [owners.model_limit]u8 = @splat(0),
    len: usize,
    expires: u64,
    consumed: bool = false,
};
pub const Leases = struct {
    mutex: std.Io.Mutex = .init,
    entries: [capacity]?Entry = @splat(null),
    previous_time: u64 = 0,
    clock_fenced: bool = false,
    fn time(self: *Leases, now: u64) !void {
        if (now < self.previous_time) self.clock_fenced = true;
        self.previous_time = @max(now, self.previous_time);
        if (self.clock_fenced) return error.ClockUncertain;
    }
    // Caller supplies monotonic milliseconds, never client wall-clock time.
    // Lock order is lease -> registry -> tracker; fixed backend probes precede
    // all of those locks. Expiration never drops an original native owner.
    pub fn reserve(self: *Leases, io: std.Io, tracker: *owners.Tracker, registry: anytype, model: []const u8, id: owners.CorrelationID, now: u64, lifetime: u64) !Handle {
        _ = tracker.backendKnownUncertain(io);
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        try self.time(now);
        if (lifetime == 0 or lifetime > 5000 or now > std.math.maxInt(u64) - lifetime) return error.InvalidLease;
        var free: ?usize = null;
        for (self.entries, 0..) |entry, index| {
            if (entry) |value| {
                if (std.mem.eql(u8, &value.correlation, &id)) return error.DuplicateCorrelation;
            } else if (free == null) free = index;
        }
        const index = free orelse return error.LeaseCapacity;
        const token = try claims.claimKnown(io, tracker, registry, model, id);
        var entry: Entry = .{ .token = token, .correlation = id, .len = model.len, .expires = now + lifetime };
        @memcpy(entry.model[0..model.len], model);
        self.entries[index] = entry;
        return .{ .instance = token.instance, .correlation = id, .root = token.sequence };
    }
    fn find(self: *Leases, handle: Handle, model: []const u8) !usize {
        for (&self.entries, 0..) |*entry, index| {
            if (entry.*) |value| {
                if (value.token.sequence == handle.root and std.mem.eql(u8, &value.token.instance, &handle.instance) and std.mem.eql(u8, &value.correlation, &handle.correlation)) {
                    if (!std.mem.eql(u8, value.model[0..value.len], model)) return error.ModelMismatch;
                    return index;
                }
            }
        }
        return error.UnknownLease;
    }
    pub fn attach(self: *Leases, io: std.Io, tracker: *owners.Tracker, registry: anytype, handle: Handle, ingress: owners.Token, model: []const u8, now: u64) !void {
        _ = tracker.backendKnownUncertain(io);
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        try self.time(now);
        const index = try self.find(handle, model);
        const entry = &self.entries[index].?;
        if (entry.consumed) return error.LeaseConsumed;
        if (now >= entry.expires) return error.LeaseExpired;
        // A failure may occur after native attachment (generation race).
        // Consume before calling; never retry or withdraw that uncertain edge.
        entry.consumed = true;
        try claims.attachKnown(io, tracker, registry, entry.token, ingress, model, handle.correlation);
        try tracker.leave(io, entry.token);
        self.entries[index] = null;
    }
    pub fn withdraw(self: *Leases, io: std.Io, tracker: *owners.Tracker, handle: Handle, model: []const u8) !void {
        _ = tracker.backendKnownUncertain(io);
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        const index = try self.find(handle, model);
        const entry = &self.entries[index].?;
        if (entry.consumed) return error.LeaseConsumed;
        // Expiration/clock uncertainty does not manufacture terminality; only
        // the tracker's exact unattached-claim check can remove this reference.
        try tracker.withdrawUnattachedPreparationKnown(io, entry.token, model, handle.correlation);
        self.entries[index] = null;
    }
};
