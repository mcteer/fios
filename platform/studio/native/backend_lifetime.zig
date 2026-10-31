//! Native-object custody only. Caller already owns a stable enclosing reference.
//! No backend I/O, terminal proof, clock expiry, wire issuer or automatic reset.
const std = @import("std");
var next_instance: std.atomic.Value(u64) = .init(0);
pub const Ticket = struct { instance: u64, slot: usize, sequence: u64 };
pub const Close = struct { instance: u64, sequence: u64 };
pub const Lifetime = struct {
    lock: std.atomic.Value(bool) = .init(false),
    instance: u64 = 0,
    sequence: u64 = 0,
    slots: [64]u64 = @splat(0),
    closing: ?u64 = null,
    closed: bool = false,
    uncertain: bool = false,
    pub fn init() !Lifetime {
        var previous = next_instance.load(.acquire);
        while (true) {
            if (previous == std.math.maxInt(u64)) return error.LifetimeExhausted;
            if (next_instance.cmpxchgWeak(previous, previous + 1, .acq_rel, .acquire)) |actual| previous = actual else return .{ .instance = previous + 1 };
        }
    }
    fn acquire(self: *Lifetime) void {
        while (self.lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
    }
    fn unlock(self: *Lifetime) void { self.lock.store(false, .release); }
    fn matches(self: *Lifetime, ticket: Ticket) bool {
        return ticket.instance == self.instance and ticket.instance != 0 and ticket.slot < self.slots.len and ticket.sequence != 0 and self.slots[ticket.slot] == ticket.sequence;
    }
    fn eligible(self: *Lifetime, except: ?Ticket) bool {
        if (self.instance == 0 or self.uncertain or self.closed or self.closing != null) return false;
        if (except) |ticket| { if (!self.matches(ticket)) return false; }
        for (self.slots, 0..) |sequence, index| {
            if (sequence != 0 and (except == null or except.?.slot != index)) return false;
        }
        return true;
    }
    pub fn borrow(self: *Lifetime) !Ticket {
        self.acquire(); defer self.unlock();
        if (self.instance == 0 or self.uncertain or self.closed or self.closing != null) return error.LifetimeUnavailable;
        if (self.sequence == std.math.maxInt(u64)) { self.uncertain = true; return error.LifetimeExhausted; }
        for (&self.slots, 0..) |*slot,index| if (slot.* == 0) {
            self.sequence += 1; slot.* = self.sequence;
            return .{ .instance = self.instance, .slot = index, .sequence = self.sequence };
        };
        return error.LifetimeBusy;
    }
    pub fn release(self: *Lifetime, ticket: Ticket) bool {
        self.acquire(); defer self.unlock();
        if (!self.matches(ticket) or self.closed) { self.uncertain = true; return false; }
        self.slots[ticket.slot] = 0;
        return true; // Never clears independent uncertainty/closing state.
    }
    // Independent backend uncertainty is one-way. Returning a valid local
    // ticket remains possible, but cannot make this object usable/closable.
    pub fn fence(self: *Lifetime) void {
        self.acquire(); defer self.unlock();
        self.uncertain = true;
    }
    pub fn canClose(self: *Lifetime, except: ?Ticket) bool {
        self.acquire(); defer self.unlock(); return self.eligible(except);
    }
    // Reserve the destructive edge before entering backend teardown. One known
    // child may remain, but must release its exact ticket before commitClose.
    pub fn beginClose(self: *Lifetime, except: ?Ticket) !Close {
        self.acquire(); defer self.unlock();
        if (!self.eligible(except)) return error.LifetimeBusy;
        if (self.sequence == std.math.maxInt(u64)) { self.uncertain = true; return error.LifetimeExhausted; }
        self.sequence += 1; self.closing = self.sequence;
        return .{ .instance = self.instance, .sequence = self.sequence };
    }
    pub fn commitClose(self: *Lifetime, claim: Close) bool {
        self.acquire(); defer self.unlock();
        if (self.instance == 0 or self.closed or self.uncertain or claim.instance != self.instance or claim.sequence == 0 or self.closing != claim.sequence) return false;
        for (self.slots) |slot| if (slot != 0) return false;
        self.closed = true;
        return true;
    }
};
