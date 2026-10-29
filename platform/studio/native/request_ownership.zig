//! Bounded request ownership, not a claim of native quiescence. No workload
//! bodies, headers, credentials, allocation, I/O or callbacks under the mutex.
//! Any overflow or protocol contradiction permanently makes coverage uncertain.
const std = @import("std");
pub const capacity = 256;
pub const model_limit = 1024;
pub const model_capacity = 64;
// Exact JSON-safe capture counter; exhaustion stays fenced, never wraps.
pub const maximum_sample_sequence: u64 = 9_007_199_254_740_991;
pub const Token = struct { slot: usize, sequence: u64, instance: [16]u8 };
pub const Phase = enum { vacant, ingress, preparing, active, responding };
// Native-internal lease, NOT authentication or a wire management capability.
// A future enrolled manager bridge must authenticate before calling these APIs.
pub const AdmissionPause = struct { instance: [16]u8, sequence: u64 };
const Slot = struct {
    sequence: u64 = 0,
    phase: Phase = .vacant,
    primary: ?u6 = null,
    models: u64 = 0,
    references: u32 = 0,
};
const Model = struct {
    id: [model_limit]u8 = @splat(0),
    len: usize = 0,
    owners: usize = 0,
};
// These are conservative REQUEST-OWNERSHIP phases, not GPU execution phases.
// The diagnostic deliberately does not export these identities or normalize
// this incomplete source into the manager's all-client activity contract.
pub const ModelSnapshot = struct {
    id: [model_limit]u8 = @splat(0),
    len: usize = 0,
    preparing: usize = 0,
    active: usize = 0,
    responding: usize = 0,
};
pub const Snapshot = struct {
    sequence: u64,
    sample_sequence: u64 = 0,
    instance: [16]u8 = @splat(0),
    initialized: bool = false,
    admissions_closed: bool = false,
    admission_pause: u64 = 0, // Native-private control state; not exported by HTTP.
    owned: usize = 0,
    ingress: usize = 0,
    preparing: usize = 0,
    active: usize = 0,
    responding: usize = 0,
    uncertain: bool,
    model_count: usize = 0,
    models: [model_capacity]ModelSnapshot = @splat(.{}),
};
pub fn renderSnapshot(snapshot: Snapshot, buffer: []u8) ![]const u8 {
    const instance = std.fmt.bytesToHex(snapshot.instance, .lower);
    const label: []const u8 = if (snapshot.initialized) &instance else "uninitialized";
    return std.fmt.bufPrint(buffer, "{{\"schema_version\":1,\"coverage\":\"unknown\",\"reason\":\"native_ownership_audit_incomplete\",\"observer_included\":true,\"source_instance\":\"{s}\",\"admissions_closed\":{s},\"sequence\":{d},\"sample_sequence\":{d},\"uncertain\":{s},\"owned_requests\":{d},\"ingress\":{d},\"preparing\":{d},\"active\":{d},\"responding\":{d}}}", .{ label, if (snapshot.admissions_closed) "true" else "false", snapshot.sequence, snapshot.sample_sequence, if (snapshot.uncertain) "true" else "false", snapshot.owned, snapshot.ingress, snapshot.preparing, snapshot.active, snapshot.responding });
}

// One process-local source, shared by connection and inference threads. TLS
// propagates only a native-created token, never client-provided authority.
pub var shared: Tracker = .{ .primary_guard = true };
pub threadlocal var current: ?Token = null;
pub const Retained = struct {
    token: Token,
    pub fn release(self: Retained, io: std.Io) void {
        shared.leave(io, self.token) catch {};
    }
};
pub fn retainCurrent(io: std.Io) !?Retained {
    const token = current orelse return null;
    try shared.retain(io, token);
    return .{ .token = token };
}
pub fn bindAuxiliaryCurrent(io: std.Io, model: []const u8) !void {
    const token = current orelse {
        shared.fence(io);
        return error.MissingOwner;
    };
    try shared.bindAuxiliary(io, token, model);
}

// Clone an existing caller-held model reference without waiting on eviction:
// waiting could deadlock an evictor that is itself waiting for that caller.
pub fn retainReference(reference: *std.atomic.Value(u32)) !void {
    var old = reference.load(.acquire);
    while (true) {
        if (old == 0) return error.MissingReference;
        if (old == std.math.maxInt(u32)) return error.ReferenceOverflow;
        if (reference.cmpxchgWeak(old, old + 1, .acq_rel, .acquire)) |actual| {
            old = actual;
        } else return;
    }
}

pub const Tracker = struct {
    mutex: std.Io.Mutex = .init,
    // Trusted native construction only, never a wire option. The serving
    // singleton protects primary binding; local audit fixtures may track
    // multiple primaries to characterize incomplete/contradictory sources.
    primary_guard: bool = false,
    slots: [capacity]Slot = @splat(.{}),
    models: [model_capacity]Model = @splat(.{}),
    sequence: u64 = 0,
    sample_sequence: u64 = 0,
    instance: [16]u8 = @splat(0),
    initialized: bool = false,
    pause_sequence: u64 = 0,
    pause_id: ?u64 = null,
    uncertain: bool = false,

    // Entropy is supplied by native startup OUTSIDE this mutex, not by a wire
    // caller. It is source-instance identity, never a management capability.
    pub fn initialize(self: *Tracker, io: std.Io, instance: [16]u8) !void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        if (self.initialized or self.sequence != 0 or self.sample_sequence != 0 or std.mem.allEqual(u8, &instance, 0)) {
            self.uncertain = true;
            return error.InvalidInstance;
        }
        self.instance = instance;
        self.initialized = true;
    }
    // Close the same mutex-protected reservation edge used by enter(). Work
    // already owning ingress is NOT cancelled. No clock/manager death resumes
    // admission, and zero owners here is NOT a device/quiescence proof.
    pub fn pauseAdmissions(self: *Tracker, io: std.Io) !AdmissionPause {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        if (!self.initialized) {
            self.uncertain = true;
            return error.InvalidInstance;
        }
        if (self.pause_id != null) return error.Maintenance;
        if (self.pause_sequence == std.math.maxInt(u64)) {
            self.uncertain = true;
            return error.SequenceExhausted;
        }
        self.pause_sequence += 1;
        self.pause_id = self.pause_sequence;
        return .{ .instance = self.instance, .sequence = self.pause_sequence };
    }
    pub fn resumeAdmissions(self: *Tracker, io: std.Io, pause: AdmissionPause) !void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        if (self.pause_id == null or self.pause_id.? != pause.sequence or
            !std.mem.eql(u8, &self.instance, &pause.instance))
        {
            self.uncertain = true;
            return error.InvalidPause;
        }
        self.pause_id = null;
    }
    pub fn fence(self: *Tracker, io: std.Io) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        self.uncertain = true;
    }
    pub fn enter(self: *Tracker, io: std.Io) !Token {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        if (self.pause_id != null) return error.Maintenance;
        if (self.sequence == std.math.maxInt(u64)) {
            self.uncertain = true;
            return error.SequenceExhausted;
        }
        for (&self.slots, 0..) |*slot, index| {
            if (slot.phase == .vacant) {
                self.sequence += 1;
                slot.* = .{ .sequence = self.sequence, .phase = .ingress, .references = 1 };
                return .{ .slot = index, .sequence = self.sequence, .instance = self.instance };
            }
        }
        self.uncertain = true;
        return error.Capacity;
    }
    fn checked(self: *Tracker, token: Token) !*Slot {
        if (token.slot >= capacity or self.slots[token.slot].phase == .vacant or
            self.slots[token.slot].sequence != token.sequence or self.slots[token.slot].references == 0 or
            !std.mem.eql(u8, &token.instance, &self.instance))
        {
            self.uncertain = true;
            return error.InvalidToken;
        }
        return &self.slots[token.slot];
    }
    fn addModelLocked(self: *Tracker, slot: *Slot, id: []const u8) !u6 {
        if (id.len == 0 or id.len > model_limit or !std.unicode.utf8ValidateSlice(id) or
            std.mem.indexOfScalar(u8, id, 0) != null)
        {
            self.uncertain = true;
            return error.InvalidModel;
        }
        var free: ?usize = null;
        var found: ?usize = null;
        for (&self.models, 0..) |*model, index| {
            if (model.owners == 0) {
                if (free == null) free = index;
            } else if (std.mem.eql(u8, model.id[0..model.len], id)) {
                found = index;
                break;
            }
        }
        const index = found orelse free orelse {
            self.uncertain = true;
            return error.ModelCapacity;
        };
        const key: u6 = @intCast(index);
        const mask = @as(u64, 1) << key;
        if (slot.models & mask != 0) return key;
        const model = &self.models[index];
        if (model.owners == 0) {
            @memcpy(model.id[0..id.len], id);
            model.len = id.len;
        }
        model.owners += 1; // At most one per each of the 256 request slots.
        slot.models |= mask;
        return key;
    }
    pub fn bind(self: *Tracker, io: std.Io, token: Token, model: []const u8) !void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        const slot = try self.checked(token);
        if (slot.phase != .ingress) {
            self.uncertain = true;
            return error.InvalidPhase;
        }
        if (self.primary_guard) {
            if (!self.initialized or self.uncertain) return error.CoverageUncertain;
            // Check and commit under the same mutex, BEFORE any caller can
            // prepare/load/evict. Keep preparing/active/responding and retained
            // owners; a completed newer request never releases an older one.
            for (self.slots) |other| {
                const primary = other.primary orelse continue;
                if (other.phase == .vacant) continue;
                const identity = &self.models[primary];
                if (!std.mem.eql(u8, identity.id[0..identity.len], model)) return error.ModelConflict;
            }
        }
        slot.primary = try self.addModelLocked(slot, model);
        slot.phase = .preparing;
    }
    pub fn bindAuxiliary(self: *Tracker, io: std.Io, token: Token, model: []const u8) !void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        const slot = try self.checked(token);
        if (slot.primary == null or (slot.phase != .preparing and slot.phase != .active)) {
            self.uncertain = true;
            return error.InvalidPhase;
        }
        _ = try self.addModelLocked(slot, model);
    }
    fn advance(self: *Tracker, io: std.Io, token: Token, from: Phase, to: Phase) !void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        const slot = try self.checked(token);
        if (slot.phase != from) {
            self.uncertain = true;
            return error.InvalidPhase;
        }
        slot.phase = to;
    }
    pub fn active(self: *Tracker, io: std.Io, token: Token) !void {
        try self.advance(io, token, .preparing, .active);
    }
    pub fn responding(self: *Tracker, io: std.Io, token: Token) !void {
        try self.advance(io, token, .active, .responding);
    }
    pub fn retain(self: *Tracker, io: std.Io, token: Token) !void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        const slot = try self.checked(token);
        if (slot.references == std.math.maxInt(u32)) {
            self.uncertain = true;
            return error.ReferenceOverflow;
        }
        slot.references += 1;
    }
    pub fn leave(self: *Tracker, io: std.Io, token: Token) !void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        const slot = try self.checked(token);
        if (slot.references > 1) {
            slot.references -= 1;
            return;
        }
        var remaining = slot.models;
        while (remaining != 0) {
            const index: u6 = @intCast(@ctz(remaining));
            remaining &= remaining - 1;
            const model = &self.models[index];
            if (model.owners == 0) {
                self.uncertain = true;
                return error.InvalidModelOwnership;
            }
            model.owners -= 1;
            if (model.owners == 0) model.* = .{};
        }
        // Clear identity without clearing the uncertainty fence or allowing replay.
        slot.* = .{};
    }
    pub fn snapshot(self: *Tracker, io: std.Io) Snapshot {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        if (self.sample_sequence == maximum_sample_sequence) {
            self.uncertain = true;
        } else self.sample_sequence += 1;
        var result: Snapshot = .{ .sequence = self.sequence, .sample_sequence = self.sample_sequence, .uncertain = self.uncertain,
            .instance = self.instance, .initialized = self.initialized,
            .admissions_closed = self.pause_id != null,
            .admission_pause = self.pause_id orelse 0 };
        var indices: [model_capacity]?usize = @splat(null);
        for (self.models, 0..) |model, index| {
            if (model.owners == 0) continue;
            indices[index] = result.model_count;
            result.models[result.model_count] = .{ .id = model.id, .len = model.len };
            result.model_count += 1;
        }
        for (self.slots) |slot| {
            switch (slot.phase) {
                .vacant => continue,
                .ingress => result.ingress += 1,
                .preparing => result.preparing += 1,
                .active => result.active += 1,
                .responding => result.responding += 1,
            }
            var remaining = slot.models;
            while (remaining != 0) {
                const index: u6 = @intCast(@ctz(remaining));
                remaining &= remaining - 1;
                const target = indices[index] orelse {
                    self.uncertain = true;
                    continue;
                };
                const model = &result.models[target];
                switch (slot.phase) {
                    .preparing => model.preparing += 1,
                    .active => model.active += 1,
                    .responding => model.responding += 1,
                    else => self.uncertain = true,
                }
            }
        }
        for (self.models, 0..) |model, index| {
            if (model.owners == 0) continue;
            const row = result.models[indices[index].?];
            if (row.preparing + row.active + row.responding != model.owners) self.uncertain = true;
        }
        result.uncertain = self.uncertain;
        result.owned = result.ingress + result.preparing + result.active + result.responding;
        return result;
    }
};
