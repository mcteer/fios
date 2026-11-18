//! Isolated design fixture; not linked to the server or a receipt issuer.
const std = @import("std");

fn Slots(comptime capacity: usize, comptime Generation: type) type {
    return struct {
        const Self = @This();
        const Slot = struct { generation: Generation = 0, live: bool = false };
        const Handle = struct { epoch: u64, index: usize, generation: Generation };
        epoch: u64,
        slots: [capacity]Slot = @splat(.{}),

        fn allocate(self: *Self) ?Handle {
            for (&self.slots, 0..) |*slot, index| {
                if (slot.live or slot.generation == std.math.maxInt(Generation)) continue;
                slot.generation += 1;
                slot.live = true;
                return .{ .epoch = self.epoch, .index = index, .generation = slot.generation };
            }
            return null;
        }

        fn validate(self: *const Self, handle: Handle) bool {
            if (handle.epoch != self.epoch or handle.index >= capacity) return false;
            const slot = self.slots[handle.index];
            return slot.live and slot.generation == handle.generation;
        }

        // In a tracker this check and allocation belong in one critical
        // section. A failed reservation never consumes the live parent.
        fn reserveChild(self: *Self, parent: Handle) ?Handle {
            if (!self.validate(parent)) return null;
            return self.allocate();
        }

        fn release(self: *Self, handle: Handle) bool {
            if (!self.validate(handle)) return false;
            self.slots[handle.index].live = false;
            return true;
        }
    };
}

fn ScopeStack(comptime Handle: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();
        const Frame = struct { handle: Handle, sequence: u64 };
        frames: [capacity]Frame = undefined,
        depth: usize = 0,
        sequence: u64 = 0,
        fenced: bool = false,

        fn push(self: *Self, handle: Handle) ?u64 {
            if (self.fenced or self.depth == capacity or self.sequence == std.math.maxInt(u64)) return null;
            self.sequence += 1;
            self.frames[self.depth] = .{ .handle = handle, .sequence = self.sequence };
            self.depth += 1;
            return self.sequence;
        }

        fn current(self: *const Self) ?Handle {
            if (self.fenced or self.depth == 0) return null;
            return self.frames[self.depth - 1].handle;
        }

        fn pop(self: *Self, sequence: u64) bool {
            if (self.fenced or self.depth == 0) return false;
            if (self.frames[self.depth - 1].sequence != sequence) {
                self.fenced = true;
                return false;
            }
            self.depth -= 1;
            return true;
        }
    };
}

test "out of order scope exit fences descendant capture instead of restoring an old parent" {
    const Table = Slots(3, u64);
    var table = Table{ .epoch = 1 };
    var stack = ScopeStack(Table.Handle, 2){};
    const outer = table.allocate().?;
    const outer_frame = stack.push(outer).?;
    const inner = table.reserveChild(stack.current().?).?;
    const inner_frame = stack.push(inner).?;
    try std.testing.expect(!stack.pop(outer_frame));
    try std.testing.expect(stack.current() == null);
    try std.testing.expect(!stack.pop(inner_frame));
    try std.testing.expect(stack.push(outer) == null);
    try std.testing.expect(table.validate(outer) and table.validate(inner));
}

test "nested frames of one operation still have distinct scope identities" {
    const Table = Slots(1, u64);
    var table = Table{ .epoch = 1 };
    var stack = ScopeStack(Table.Handle, 2){};
    const operation = table.allocate().?;
    const outer_frame = stack.push(operation).?;
    const inner_frame = stack.push(operation).?;
    try std.testing.expectEqual(outer_frame + 1, inner_frame);
    try std.testing.expect(stack.pop(inner_frame));
    try std.testing.expectEqual(operation, stack.current().?);
    try std.testing.expect(!stack.pop(inner_frame));
    try std.testing.expect(stack.current() == null);
    try std.testing.expect(table.validate(operation));
}

test "generation saturation retires one slot without affecting another" {
    var table = Slots(2, u2){ .epoch = 1 };
    const first = table.allocate().?;
    const held = table.allocate().?;
    try std.testing.expect(table.allocate() == null);
    try std.testing.expect(table.release(first));
    const second = table.allocate().?;
    try std.testing.expect(second.index == first.index and second.generation == 2);
    try std.testing.expect(!table.release(first));
    try std.testing.expect(table.release(second));
    const last = table.allocate().?;
    try std.testing.expect(last.generation == 3);
    try std.testing.expect(table.release(last));
    try std.testing.expect(table.allocate() == null);
    try std.testing.expect(table.validate(held));
    try std.testing.expect(table.release(held));
    const sibling = table.allocate().?;
    try std.testing.expect(sibling.index == held.index);
}

test "worker acknowledgement cannot invalidate a reserved callback" {
    var table = Slots(2, u64){ .epoch = 1 };
    const worker = table.allocate().?;
    const callback = table.reserveChild(worker).?;
    try std.testing.expect(table.reserveChild(worker) == null);
    try std.testing.expect(table.release(worker));
    try std.testing.expect(table.reserveChild(worker) == null);
    const destructor = table.reserveChild(callback).?;
    try std.testing.expect(destructor.index == worker.index);
    try std.testing.expect(destructor.generation != worker.generation);
    try std.testing.expect(table.release(callback));
    try std.testing.expect(table.validate(destructor));
    try std.testing.expect(table.release(destructor));
}

test "previous epoch cannot release coincident live slot" {
    var old = Slots(1, u64){ .epoch = 1 };
    var replacement = Slots(1, u64){ .epoch = 2 };
    const original = old.allocate().?;
    const current = replacement.allocate().?;
    try std.testing.expect(original.index == current.index and original.generation == current.generation);
    try std.testing.expect(!replacement.release(original));
    try std.testing.expect(replacement.release(current));
}
