const std = @import("std");
const ownership = @import("request_ownership.zig");
const io = std.testing.io;

test "preparation refuses stale parents and sequence exhaustion without clearing existing owners" {
    var tracker: ownership.Tracker = .{ .primary_guard = true };
    try tracker.initialize(io, @splat(26));
    const old = try tracker.enter(io);
    try tracker.bind(io, old, "model-a");
    try tracker.active(io, old);
    try tracker.responding(io, old);
    try std.testing.expectError(error.InvalidPhase, tracker.reservePreparation(io, old, "model-a"));
    try tracker.leave(io, old);
    const newer = try tracker.enter(io);
    try tracker.bind(io, newer, "model-a");
    try std.testing.expectError(error.InvalidToken, tracker.reservePreparation(io, old, "model-a"));
    try std.testing.expectEqual(@as(usize, 1), tracker.snapshot(io).owned);
    try std.testing.expectError(error.CoverageUncertain, tracker.reservePreparation(io, newer, "model-a"));
    try tracker.leave(io, newer);
    var exhausted: ownership.Tracker = .{ .primary_guard = true };
    try exhausted.initialize(io, @splat(27));
    const retained = try exhausted.enter(io);
    try exhausted.bind(io, retained, "model-a");
    exhausted.sequence = std.math.maxInt(u64);
    try std.testing.expectError(error.SequenceExhausted, exhausted.reservePreparation(io, retained, "model-a"));
    try std.testing.expectEqual(@as(usize, 1), exhausted.snapshot(io).owned);
    try exhausted.leave(io, retained);
    try std.testing.expect(exhausted.snapshot(io).uncertain);
}

test "load preparation guards direct callers and preserves exact parent identity" {
    var tracker: ownership.Tracker = .{ .primary_guard = true };
    try tracker.initialize(io, @splat(24));
    const direct = try tracker.reservePreparation(io, null, "model-a");
    const incoming = try tracker.enter(io);
    try std.testing.expectError(error.ModelConflict, tracker.bind(io, incoming, "model-b"));
    try tracker.bind(io, incoming, "model-a");
    try tracker.bindAuxiliary(io, incoming, "aux-a");
    const auxiliary = try tracker.reservePreparation(io, incoming, "aux-a");
    try std.testing.expectError(error.ModelConflict, tracker.reservePreparation(io, incoming, "unbound-aux"));
    try tracker.leave(io, direct);
    try tracker.leave(io, incoming);
    try std.testing.expectError(error.ModelOwned, tracker.beginModelMutation(io, "model-a"));
    try std.testing.expectError(error.ModelOwned, tracker.beginModelMutation(io, "aux-a"));
    try tracker.leave(io, auxiliary);
    try std.testing.expectEqual(@as(usize, 0), tracker.snapshot(io).owned);
    try std.testing.expect(!tracker.snapshot(io).uncertain);
}

test "pre-fence preparation continues but new direct preparation stays closed" {
    var tracker: ownership.Tracker = .{ .primary_guard = true };
    try tracker.initialize(io, @splat(25));
    const ingress = try tracker.enter(io);
    const pause = try tracker.pauseAdmissions(io);
    try std.testing.expectError(error.Maintenance, tracker.reservePreparation(io, null, "model-a"));
    const continuing = try tracker.reservePreparation(io, ingress, "model-a");
    try tracker.leave(io, continuing);
    // The original admin/load connection retains identity after preparation,
    // including a slow response; child completion cannot release it.
    try std.testing.expectEqual(@as(usize, 1), tracker.snapshot(io).owned);
    try std.testing.expectError(error.ModelOwned, tracker.beginModelMutation(io, "model-a"));
    try tracker.leave(io, ingress);
    try std.testing.expect(tracker.snapshot(io).admissions_closed);
    try tracker.resumeAdmissions(io, pause);
    const mutation = try tracker.beginModelMutation(io, "model-a");
    try std.testing.expectError(error.ModelTransition, tracker.reservePreparation(io, null, "model-a"));
    try std.testing.expectEqual(@as(usize, 0), tracker.snapshot(io).owned);
    try tracker.endModelMutation(io, mutation);
    const final = try tracker.reservePreparation(io, null, "model-b");
    try tracker.leave(io, final);
    try std.testing.expect(!tracker.snapshot(io).uncertain);
}

test "model transition and request binding cannot both reserve the same identity" {
    const Work = struct {
        fn run(tracker: *ownership.Tracker, token: ownership.Token, bound: *bool) void {
            tracker.bind(io, token, "model-a") catch return;
            bound.* = true;
        }
    };
    var tracker: ownership.Tracker = .{};
    try tracker.initialize(io, @splat(19));
    const owner = try tracker.enter(io);
    var bound = false;
    const thread = try std.Thread.spawn(.{}, Work.run, .{ &tracker, owner, &bound });
    const result = tracker.beginModelMutation(io, "model-a");
    thread.join();
    const mutation = result catch |err| blocked: {
        try std.testing.expectEqual(error.ModelOwned, err);
        break :blocked null;
    };
    try std.testing.expect(bound != (mutation != null));
    if (mutation) |ticket| try tracker.endModelMutation(io, ticket);
    try tracker.leave(io, owner);
    try std.testing.expect(!tracker.snapshot(io).uncertain);
}

test "model transition table exhaustion and foreign release retain uncertainty and ownership" {
    var tracker: ownership.Tracker = .{};
    try tracker.initialize(io, @splat(20));
    var tickets: [ownership.model_capacity]ownership.ModelMutation = undefined;
    for (&tickets, 0..) |*ticket, index| {
        var buffer: [32]u8 = undefined;
        ticket.* = try tracker.beginModelMutation(io, try std.fmt.bufPrint(&buffer, "model-{d}", .{index}));
    }
    try std.testing.expectError(error.ModelCapacity, tracker.beginModelMutation(io, "overflow"));
    try std.testing.expectEqual(ownership.model_capacity, tracker.snapshot(io).model_mutations);
    var foreign = tickets[0];
    foreign.instance = @splat(21);
    try std.testing.expectError(error.InvalidMutation, tracker.endModelMutation(io, foreign));
    for (tickets) |ticket| try tracker.endModelMutation(io, ticket);
    try std.testing.expect(tracker.snapshot(io).uncertain);
    try std.testing.expectEqual(@as(usize, 0), tracker.snapshot(io).model_mutations);
}

test "model transition reservation excludes primary and auxiliary binding until exact release" {
    var tracker: ownership.Tracker = .{ .primary_guard = true };
    try tracker.initialize(io, @splat(17));
    const transition = try tracker.beginModelMutation(io, "model-b");
    try std.testing.expectEqual(@as(usize, 1), tracker.snapshot(io).model_mutations);
    try std.testing.expectError(error.ModelTransition, tracker.beginModelMutation(io, "model-b"));
    const first = try tracker.enter(io);
    try std.testing.expectError(error.ModelTransition, tracker.bind(io, first, "model-b"));
    try tracker.bind(io, first, "model-a");
    try std.testing.expectError(error.ModelTransition, tracker.bindAuxiliary(io, first, "model-b"));
    try tracker.endModelMutation(io, transition);
    try tracker.bindAuxiliary(io, first, "model-b");
    try std.testing.expectError(error.ModelOwned, tracker.beginModelMutation(io, "model-a"));
    try std.testing.expectError(error.ModelOwned, tracker.beginModelMutation(io, "model-b"));
    try tracker.active(io, first);
    try tracker.responding(io, first);
    try tracker.leave(io, first);
}

test "retained owner prevents transition and stale transition release cannot clear a newer one" {
    var tracker: ownership.Tracker = .{};
    try tracker.initialize(io, @splat(18));
    const owner = try tracker.enter(io);
    try tracker.bind(io, owner, "model-a");
    try tracker.active(io, owner);
    try tracker.responding(io, owner);
    try tracker.retain(io, owner);
    try tracker.leave(io, owner);
    try std.testing.expectError(error.ModelOwned, tracker.beginModelMutation(io, "model-a"));
    try tracker.leave(io, owner);
    const first = try tracker.beginModelMutation(io, "model-a");
    try tracker.endModelMutation(io, first);
    const second = try tracker.beginModelMutation(io, "model-a");
    try std.testing.expectError(error.InvalidMutation, tracker.endModelMutation(io, first));
    try std.testing.expectEqual(@as(usize, 1), tracker.snapshot(io).model_mutations);
    try std.testing.expect(tracker.snapshot(io).uncertain);
    try tracker.endModelMutation(io, second);
    try std.testing.expect(tracker.snapshot(io).uncertain);
    try std.testing.expectError(error.CoverageUncertain, tracker.beginModelMutation(io, "model-a"));
}

test "guarded primary binding rejects conflicts without releasing or fencing the existing owner" {
    var tracker: ownership.Tracker = .{ .primary_guard = true };
    try tracker.initialize(io, @splat(14));
    const first = try tracker.enter(io);
    try tracker.bind(io, first, "primary-a");
    const peer = try tracker.enter(io);
    try tracker.bind(io, peer, "primary-a");
    const conflicting = try tracker.enter(io);
    try std.testing.expectError(error.ModelConflict, tracker.bind(io, conflicting, "primary-b"));
    try tracker.active(io, first);
    try std.testing.expectError(error.ModelConflict, tracker.bind(io, conflicting, "primary-b"));
    try tracker.responding(io, first);
    try tracker.retain(io, first);
    try tracker.leave(io, first);
    try tracker.leave(io, peer);
    try std.testing.expectError(error.ModelConflict, tracker.bind(io, conflicting, "primary-b"));
    try std.testing.expect(!tracker.snapshot(io).uncertain);
    try tracker.leave(io, first);
    try tracker.bind(io, conflicting, "primary-b");
    try tracker.leave(io, conflicting);
    try std.testing.expectEqual(@as(usize, 0), tracker.snapshot(io).owned);
}

test "guarded primary ignores its own auxiliary identities but not a foreign primary" {
    var tracker: ownership.Tracker = .{ .primary_guard = true };
    try tracker.initialize(io, @splat(15));
    const first = try tracker.enter(io);
    try tracker.bind(io, first, "primary-a");
    try tracker.bindAuxiliary(io, first, "component-b");
    const same = try tracker.enter(io);
    try tracker.bind(io, same, "primary-a");
    const foreign = try tracker.enter(io);
    try std.testing.expectError(error.ModelConflict, tracker.bind(io, foreign, "component-b"));
    try std.testing.expect(!tracker.snapshot(io).uncertain);
    try tracker.leave(io, first);
    try tracker.leave(io, same);
    try tracker.bind(io, foreign, "component-b");
    try tracker.leave(io, foreign);
    const old = try tracker.enter(io);
    try std.testing.expectError(error.InvalidToken, tracker.bind(io, first, "primary-a"));
    try std.testing.expectError(error.CoverageUncertain, tracker.bind(io, old, "primary-a"));
    try tracker.leave(io, old);
}

test "concurrent different-primary binding selects exactly one owner before loading" {
    const Work = struct {
        const Result = enum { success, conflict, unexpected };
        fn run(tracker: *ownership.Tracker, token: ownership.Token, model: []const u8, result: *Result) void {
            tracker.bind(io, token, model) catch |err| {
                result.* = if (err == error.ModelConflict) .conflict else .unexpected;
                return;
            };
            result.* = .success;
        }
    };
    var tracker: ownership.Tracker = .{ .primary_guard = true };
    try tracker.initialize(io, @splat(16));
    const first = try tracker.enter(io);
    const second = try tracker.enter(io);
    var a: Work.Result = .unexpected;
    var b: Work.Result = .unexpected;
    const thread = try std.Thread.spawn(.{}, Work.run, .{ &tracker, first, "primary-a", &a });
    Work.run(&tracker, second, "primary-b", &b);
    thread.join();
    try std.testing.expect((a == .success and b == .conflict) or (b == .success and a == .conflict));
    const snapshot = tracker.snapshot(io);
    try std.testing.expectEqual(@as(usize, 1), snapshot.preparing);
    try std.testing.expectEqual(@as(usize, 1), snapshot.ingress);
    try std.testing.expect(!snapshot.uncertain);
    try tracker.leave(io, first);
    try tracker.leave(io, second);
}

test "capture sequence advances independently of request allocation and fences exhaustion" {
    var tracker: ownership.Tracker = .{};
    try tracker.initialize(io, @splat(11));
    const first = tracker.snapshot(io);
    const second = tracker.snapshot(io);
    try std.testing.expectEqual(@as(u64, 1), first.sample_sequence);
    try std.testing.expectEqual(@as(u64, 2), second.sample_sequence);
    try std.testing.expectEqual(@as(u64, 0), second.sequence);
    const request = try tracker.enter(io);
    try tracker.leave(io, request);
    const third = tracker.snapshot(io);
    try std.testing.expectEqual(@as(u64, 3), third.sample_sequence);
    try std.testing.expectEqual(@as(u64, 1), third.sequence);
    tracker.sample_sequence = ownership.maximum_sample_sequence - 1;
    try std.testing.expectEqual(ownership.maximum_sample_sequence, tracker.snapshot(io).sample_sequence);
    try std.testing.expect(!tracker.uncertain);
    const exhausted = tracker.snapshot(io);
    try std.testing.expectEqual(ownership.maximum_sample_sequence, exhausted.sample_sequence);
    try std.testing.expect(exhausted.uncertain);
    try std.testing.expect(tracker.snapshot(io).uncertain);
    var late: ownership.Tracker = .{};
    _ = late.snapshot(io);
    try std.testing.expectError(error.InvalidInstance, late.initialize(io, @splat(12)));
}

test "concurrent captures have unique ordered sequence without allocating requests" {
    var tracker: ownership.Tracker = .{};
    try tracker.initialize(io, @splat(13));
    const Sampler = struct {
        fn run(source: *ownership.Tracker, result: *[32]u64) void {
            for (result) |*value| value.* = source.snapshot(io).sample_sequence;
        }
    };
    var first: [32]u64 = undefined;
    var second: [32]u64 = undefined;
    const thread = try std.Thread.spawn(.{}, Sampler.run, .{ &tracker, &first });
    Sampler.run(&tracker, &second);
    thread.join();
    var seen: [64]bool = @splat(false);
    for ([_][32]u64{ first, second }) |series| {
        var previous: u64 = 0;
        for (series) |value| {
            try std.testing.expect(value > previous and value <= seen.len);
            try std.testing.expect(!seen[@intCast(value - 1)]);
            seen[@intCast(value - 1)] = true;
            previous = value;
        }
    }
    try std.testing.expectEqual(@as(u64, 0), tracker.sequence);
}

test "even empty tracker renders unknown coverage with bounded valid JSON" {
    var tracker: ownership.Tracker = .{};
    var buffer: [1024]u8 = undefined;
    const body = try ownership.renderSnapshot(tracker.snapshot(io), &buffer);
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, body, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("unknown", parsed.value.object.get("coverage").?.string);
    try std.testing.expect(parsed.value.object.get("observer_included").?.bool);
    try std.testing.expectEqual(@as(i64, 0), parsed.value.object.get("owned_requests").?.integer);
    var tiny: [8]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, ownership.renderSnapshot(tracker.snapshot(io), &tiny));
}

test "native source instances bind tokens and cannot be replaced after startup" {
    var a: ownership.Tracker = .{};
    var b: ownership.Tracker = .{};
    try a.initialize(io, @splat(1));
    try b.initialize(io, @splat(2));
    const first = try a.enter(io);
    const other = try b.enter(io);
    try std.testing.expectError(error.InvalidToken, b.retain(io, first));
    try std.testing.expect(b.snapshot(io).uncertain);
    try b.leave(io, other);
    try std.testing.expectError(error.InvalidInstance, a.initialize(io, @splat(1)));
    try a.leave(io, first);
    try std.testing.expect(a.snapshot(io).uncertain);
    var invalid: ownership.Tracker = .{};
    try std.testing.expectError(error.InvalidInstance, invalid.initialize(io, @splat(0)));
    try std.testing.expect(invalid.snapshot(io).uncertain);
}

test "native admission pause closes new ingress without revoking existing work" {
    var tracker: ownership.Tracker = .{};
    try tracker.initialize(io, @splat(3));
    const existing = try tracker.enter(io);
    const pause = try tracker.pauseAdmissions(io);
    try std.testing.expectError(error.Maintenance, tracker.enter(io));
    try std.testing.expectError(error.Maintenance, tracker.pauseAdmissions(io));
    // Pre-fence ingress is already owned; it may finish, not be replayed.
    try tracker.bind(io, existing, "org/draining");
    try tracker.active(io, existing);
    try tracker.bindAuxiliary(io, existing, "org/auxiliary");
    try std.testing.expect(tracker.snapshot(io).admissions_closed);
    try std.testing.expectEqual(@as(usize, 1), tracker.snapshot(io).owned);
    try tracker.leave(io, existing);
    try std.testing.expect(tracker.snapshot(io).admissions_closed);
    try std.testing.expect(!tracker.snapshot(io).uncertain);
    var foreign = pause;
    foreign.instance[0] += 1;
    try std.testing.expectError(error.InvalidPause, tracker.resumeAdmissions(io, foreign));
    try std.testing.expect(tracker.snapshot(io).admissions_closed);
    var wrong = pause;
    wrong.sequence += 1;
    try std.testing.expectError(error.InvalidPause, tracker.resumeAdmissions(io, wrong));
    try std.testing.expect(tracker.snapshot(io).admissions_closed);
    try tracker.resumeAdmissions(io, pause);
    try std.testing.expect(tracker.snapshot(io).uncertain); // resume never clears certainty
    try std.testing.expectError(error.InvalidPause, tracker.resumeAdmissions(io, pause));
    const next = try tracker.enter(io);
    try tracker.leave(io, next);
    const second = try tracker.pauseAdmissions(io);
    try std.testing.expect(second.sequence > pause.sequence);
    try std.testing.expectError(error.InvalidPause, tracker.resumeAdmissions(io, pause));
    try std.testing.expect(tracker.snapshot(io).admissions_closed);
    try tracker.resumeAdmissions(io, second);
}

test "concurrent native admission cannot cross the paused reservation edge" {
    const Work = struct {
        fn run(tracker: *ownership.Tracker, failed: *std.atomic.Value(bool)) void {
            for (0..128) |_| {
                const token = tracker.enter(io) catch |err| {
                    if (err != error.Maintenance) failed.store(true, .release);
                    return;
                };
                tracker.leave(io, token) catch {
                    failed.store(true, .release);
                    return;
                };
            }
        }
    };
    var tracker: ownership.Tracker = .{};
    try tracker.initialize(io, @splat(4));
    var failed: std.atomic.Value(bool) = .init(false);
    var threads: [8]std.Thread = undefined;
    var count: usize = 0;
    defer for (threads[0..count]) |thread| thread.join();
    for (&threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, Work.run, .{ &tracker, &failed });
        count += 1;
    }
    const pause = try tracker.pauseAdmissions(io);
    const boundary = tracker.snapshot(io).sequence;
    for (threads[0..count]) |thread| thread.join();
    count = 0;
    try std.testing.expect(!failed.load(.acquire));
    try std.testing.expectEqual(boundary, tracker.snapshot(io).sequence);
    try std.testing.expectEqual(@as(usize, 0), tracker.snapshot(io).owned);
    try std.testing.expect(tracker.snapshot(io).admissions_closed);
    try std.testing.expect(!tracker.snapshot(io).uncertain);
    try tracker.resumeAdmissions(io, pause);
}

test "ingress stays owned until response drain and stale release fences forever" {
    var tracker: ownership.Tracker = .{};
    const a = try tracker.enter(io);
    try std.testing.expectEqual(@as(usize, 1), tracker.snapshot(io).ingress);
    try tracker.bind(io, a, "org/exact-model");
    try std.testing.expectEqual(@as(usize, 1), tracker.snapshot(io).preparing);
    try tracker.active(io, a);
    try std.testing.expectEqual(@as(usize, 1), tracker.snapshot(io).active);
    try tracker.responding(io, a);
    try std.testing.expectEqual(@as(usize, 1), tracker.snapshot(io).responding);
    try tracker.leave(io, a);
    try std.testing.expectEqual(@as(usize, 0), tracker.snapshot(io).owned);
    const b = try tracker.enter(io);
    try std.testing.expectError(error.InvalidToken, tracker.leave(io, a));
    try std.testing.expect(tracker.snapshot(io).uncertain);
    try tracker.leave(io, b);
    try std.testing.expect(tracker.snapshot(io).uncertain);
}

test "bounded overflow never becomes idle after holders leave" {
    var tracker: ownership.Tracker = .{};
    var tokens: [ownership.capacity]ownership.Token = undefined;
    for (&tokens) |*token| token.* = try tracker.enter(io);
    try std.testing.expectError(error.Capacity, tracker.enter(io));
    for (tokens) |token| try tracker.leave(io, token);
    try std.testing.expect(tracker.snapshot(io).uncertain);
}

test "model identity is exact bounded owned storage and phases cannot rewind" {
    var tracker: ownership.Tracker = .{};
    const token = try tracker.enter(io);
    var id = [_]u8{ 'a', '/', 'b' };
    try tracker.bind(io, token, &id);
    id[0] = 'x';
    const index = tracker.slots[token.slot].primary.?;
    try std.testing.expectEqualStrings("a/b", tracker.models[index].id[0..3]);
    try tracker.active(io, token);
    try std.testing.expectError(error.InvalidPhase, tracker.bind(io, token, "other"));
    try std.testing.expect(tracker.snapshot(io).uncertain);
    try tracker.leave(io, token);
    try std.testing.expectEqual(@as(usize, 0), tracker.models[index].len);
    for (tracker.models[index].id) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
}

test "native cleanup retains ownership after the socket owner leaves" {
    var tracker: ownership.Tracker = .{};
    const token = try tracker.enter(io);
    try tracker.bind(io, token, "org/model");
    try tracker.active(io, token);
    try tracker.retain(io, token);
    try tracker.responding(io, token);
    try tracker.leave(io, token);
    try std.testing.expectEqual(@as(usize, 1), tracker.snapshot(io).owned);
    try std.testing.expectEqual(@as(usize, 1), tracker.snapshot(io).responding);
    try tracker.leave(io, token);
    try std.testing.expectEqual(@as(usize, 0), tracker.snapshot(io).owned);
    try std.testing.expect(!tracker.snapshot(io).uncertain);
    try std.testing.expectError(error.InvalidToken, tracker.retain(io, token));
    try std.testing.expect(tracker.snapshot(io).uncertain);
}

test "auxiliary identities are exact bounded and retained with the parent owner" {
    var tracker: ownership.Tracker = .{};
    const a = try tracker.enter(io);
    try tracker.bind(io, a, "org/asr");
    try tracker.active(io, a);
    try tracker.bindAuxiliary(io, a, "org/aligner");
    try tracker.bindAuxiliary(io, a, "org/aligner"); // no duplicate owner
    try tracker.bindAuxiliary(io, a, "org/\u{e9}");
    try tracker.bindAuxiliary(io, a, "org/e\u{301}"); // byte-distinct, not an alias
    const b = try tracker.enter(io);
    try tracker.bind(io, b, "org/aligner");
    const snapshot = tracker.snapshot(io);
    try std.testing.expectEqual(@as(usize, 4), snapshot.model_count);
    var found = false;
    for (snapshot.models[0..snapshot.model_count]) |model| {
        if (std.mem.eql(u8, model.id[0..model.len], "org/aligner")) {
            try std.testing.expectEqual(@as(usize, 1), model.active);
            try std.testing.expectEqual(@as(usize, 1), model.preparing);
            found = true;
        }
    }
    try std.testing.expect(found);
    try tracker.retain(io, a);
    try tracker.leave(io, a);
    try std.testing.expectEqual(@as(usize, 4), tracker.snapshot(io).model_count);
    try tracker.leave(io, a);
    try std.testing.expectEqual(@as(usize, 1), tracker.snapshot(io).model_count);
    try tracker.leave(io, b);
    try std.testing.expectEqual(@as(usize, 0), tracker.snapshot(io).model_count);
    for (tracker.models) |model| {
        for (model.id) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
    }
}

test "auxiliary protocol errors and contradictory model counts fence permanently" {
    var tracker: ownership.Tracker = .{};
    const token = try tracker.enter(io);
    try std.testing.expectError(error.InvalidPhase, tracker.bindAuxiliary(io, token, "org/aux"));
    try tracker.bind(io, token, "org/main");
    try std.testing.expectError(error.InvalidModel, tracker.bindAuxiliary(io, token, "bad\x00id"));
    try tracker.active(io, token);
    try tracker.responding(io, token);
    try std.testing.expectError(error.InvalidPhase, tracker.bindAuxiliary(io, token, "org/aux"));
    try tracker.leave(io, token);
    try std.testing.expect(tracker.snapshot(io).uncertain);
    var contradiction: ownership.Tracker = .{};
    const other = try contradiction.enter(io);
    try contradiction.bind(io, other, "org/model");
    contradiction.models[contradiction.slots[other.slot].primary.?].owners += 1;
    try std.testing.expect(contradiction.snapshot(io).uncertain);
}

test "more than 64 exact live model identities fences without truncation" {
    var tracker: ownership.Tracker = .{};
    const token = try tracker.enter(io);
    try tracker.bind(io, token, "model-0");
    for (1..64) |n| {
        var bytes: [32]u8 = undefined;
        try tracker.bindAuxiliary(io, token, try std.fmt.bufPrint(&bytes, "model-{d}", .{n}));
    }
    try std.testing.expectEqual(@as(usize, 64), tracker.snapshot(io).model_count);
    try std.testing.expectError(error.ModelCapacity, tracker.bindAuxiliary(io, token, "model-overflow"));
    try tracker.leave(io, token);
    try std.testing.expectEqual(@as(usize, 0), tracker.snapshot(io).model_count);
    try std.testing.expect(tracker.snapshot(io).uncertain);
}

test "borrowed model reference cloning cannot resurrect or overflow" {
    var reference: std.atomic.Value(u32) = .init(1);
    try ownership.retainReference(&reference);
    try std.testing.expectEqual(@as(u32, 2), reference.load(.acquire));
    reference.store(0, .release);
    try std.testing.expectError(error.MissingReference, ownership.retainReference(&reference));
    reference.store(std.math.maxInt(u32), .release);
    try std.testing.expectError(error.ReferenceOverflow, ownership.retainReference(&reference));
    try std.testing.expectEqual(std.math.maxInt(u32), reference.load(.acquire));
}

test "concurrent owners never lose a live reservation" {
    const Work = struct {
        fn run(tracker: *ownership.Tracker, failed: *std.atomic.Value(bool)) void {
            for (0..64) |_| {
                const token = tracker.enter(io) catch {
                    failed.store(true, .release);
                    return;
                };
                tracker.bind(io, token, "org/shared-model") catch {
                    failed.store(true, .release);
                    return;
                };
                tracker.active(io, token) catch {
                    failed.store(true, .release);
                    return;
                };
                tracker.responding(io, token) catch {
                    failed.store(true, .release);
                    return;
                };
                tracker.leave(io, token) catch {
                    failed.store(true, .release);
                    return;
                };
            }
        }
    };
    var tracker: ownership.Tracker = .{};
    var failed: std.atomic.Value(bool) = .init(false);
    var threads: [8]std.Thread = undefined;
    var count: usize = 0;
    defer for (threads[0..count]) |thread| thread.join();
    for (&threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, Work.run, .{ &tracker, &failed });
        count += 1;
    }
    for (threads[0..count]) |thread| thread.join();
    count = 0;
    try std.testing.expect(!failed.load(.acquire));
    const snapshot = tracker.snapshot(io);
    try std.testing.expectEqual(@as(usize, 0), snapshot.owned);
    try std.testing.expect(!snapshot.uncertain);
    try std.testing.expectEqual(@as(u64, 512), snapshot.sequence);
}

test "empty or oversized models and sequence exhaustion fence rather than truncate" {
    var tracker: ownership.Tracker = .{};
    const token = try tracker.enter(io);
    try std.testing.expectError(error.InvalidModel, tracker.bind(io, token, ""));
    const oversized: [ownership.model_limit + 1]u8 = @splat('x');
    try std.testing.expectError(error.InvalidModel, tracker.bind(io, token, &oversized));
    try std.testing.expectError(error.InvalidModel, tracker.bind(io, token, "a\x00b"));
    const invalid_utf8 = [_]u8{ 0xff, 0xfe };
    try std.testing.expectError(error.InvalidModel, tracker.bind(io, token, &invalid_utf8));
    try std.testing.expect(tracker.snapshot(io).uncertain);
    tracker.sequence = std.math.maxInt(u64);
    try std.testing.expectError(error.SequenceExhausted, tracker.enter(io));
    try tracker.leave(io, token);
}

test "opaque request correlation follows retained lineage and missing is always unknown" {
    var tracker: ownership.Tracker = .{ .primary_guard = true };
    try tracker.initialize(io, @splat(28));
    const id = try ownership.parseCorrelationHex("29fc52e328d588a1afee500c96d67ccc1045a873a328efccec3dc9ddfaef2cf5");
    try std.testing.expectEqualStrings("29fc52e328d588a1afee500c96d67ccc1045a873a328efccec3dc9ddfaef2cf5", &std.fmt.bytesToHex(id, .lower));
    const missing = tracker.correlationSnapshot(io, id);
    try std.testing.expect(!missing.found and missing.uncertain);
    const root = try tracker.enter(io);
    try tracker.associate(io, root, id);
    try tracker.bind(io, root, "test/model");
    const child = try tracker.reservePreparation(io, root, "test/model");
    try tracker.retain(io, root);
    var observed = tracker.correlationSnapshot(io, id);
    try std.testing.expect(observed.found and !observed.uncertain);
    try std.testing.expectEqual(root.sequence, observed.root_sequence);
    try std.testing.expectEqual(@as(usize, 2), observed.owners);
    try std.testing.expectEqual(@as(u64, 3), observed.references);
    try std.testing.expectEqual(@as(usize, 2), observed.preparing);
    try std.testing.expect(observed.sample_sequence > missing.sample_sequence);
    const duplicate = try tracker.enter(io);
    try std.testing.expectError(error.DuplicateCorrelation, tracker.associate(io, duplicate, id));
    try std.testing.expectError(error.InvalidCorrelationState, tracker.associate(io, root, id));
    try tracker.leave(io, duplicate);
    try tracker.leave(io, root);
    try tracker.active(io, root);
    try tracker.responding(io, root);
    observed = tracker.correlationSnapshot(io, id);
    try std.testing.expectEqual(@as(usize, 1), observed.responding);
    try tracker.leave(io, root);
    observed = tracker.correlationSnapshot(io, id);
    try std.testing.expect(observed.found and !observed.uncertain);
    try std.testing.expectEqual(root.sequence, observed.root_sequence);
    try std.testing.expectEqual(@as(usize, 1), observed.preparing);
    const later = try tracker.enter(io);
    try std.testing.expectError(error.DuplicateCorrelation, tracker.associate(io, later, id));
    try tracker.leave(io, later);
    try tracker.leave(io, child);
    observed = tracker.correlationSnapshot(io, id);
    try std.testing.expect(!observed.found and observed.uncertain);
    const reused = try tracker.enter(io);
    try tracker.associate(io, reused, id);
    observed = tracker.correlationSnapshot(io, id);
    try std.testing.expect(observed.root_sequence != root.sequence); // Never adopt a later ingress as the old request.
    tracker.fence(io);
    try std.testing.expect(tracker.correlationSnapshot(io, id).uncertain);
    try tracker.leave(io, reused);
    for ([_][]const u8{ "", "a", "29FC52e328d588a1afee500c96d67ccc1045a873a328efccec3dc9ddfaef2cf5", "gggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg" }) |invalid| {
        try std.testing.expectError(error.InvalidCorrelation, ownership.parseCorrelationHex(invalid));
    }
}

test "retained groups keep every distinct origin and validate before acquiring" {
    var tracker: ownership.Tracker = .{};
    try tracker.initialize(io, @splat(32));
    const first = try tracker.enter(io);
    const second = try tracker.enter(io);
    const retained = try tracker.retainTokens(io, &.{first,second,first});
    try std.testing.expectEqual(@as(usize, 2), retained.count);
    try tracker.leave(io, first);
    try tracker.leave(io, second);
    try std.testing.expectEqual(@as(usize, 2), tracker.snapshot(io).owned);
    retained.release(io);
    try std.testing.expectEqual(@as(usize, 0), tracker.snapshot(io).owned);
    const live = try tracker.enter(io);
    const before = tracker.slots[live.slot].references;
    try std.testing.expectError(error.InvalidToken, tracker.retainTokens(io, &.{live,first}));
    try std.testing.expectEqual(before, tracker.slots[live.slot].references);
    try std.testing.expect(tracker.snapshot(io).uncertain);
    try tracker.leave(io, live);
    try std.testing.expectError(error.InvalidReferenceGroup, tracker.retainTokens(io, &.{}));
}

test "retirement preserves original correlation after response and final descendant release" {
    var tracker: ownership.Tracker = .{ .primary_guard = true };
    try tracker.initialize(io, @splat(61));
    const root = try tracker.enter(io);
    try tracker.associate(io, root, @splat(62));
    try tracker.bind(io, root, "model-a");
    const child = try tracker.reservePreparation(io, root, "model-a");
    try tracker.active(io, root);
    try tracker.responding(io, root);
    try tracker.leave(io, root);
    try std.testing.expect(!tracker.retirementSnapshot(io, @splat(62), root.sequence).recorded);
    try tracker.leave(io, child);
    const record = tracker.retirementSnapshot(io, @splat(62), root.sequence);
    try std.testing.expect(record.recorded and !record.uncertain);
    try std.testing.expectEqual(root.sequence, record.root_sequence);
    try std.testing.expectEqual(@as(u64, 1), record.retirement_sequence);
    try std.testing.expect(!tracker.correlationSnapshot(io, @splat(62)).found);
    // Ordinary live-lineage absence is still unknown, never native completion.
    try std.testing.expect(tracker.correlationSnapshot(io, @splat(62)).uncertain);
}

test "retirement binds original root through correlation reuse and independent uncertainty" {
    var tracker: ownership.Tracker = .{};
    try tracker.initialize(io, @splat(63));
    const first = try tracker.enter(io);
    try tracker.associate(io, first, @splat(64));
    try tracker.leave(io, first);
    const next = try tracker.enter(io);
    try tracker.associate(io, next, @splat(64));
    try std.testing.expect(!tracker.retirementSnapshot(io, @splat(64), next.sequence).recorded);
    try std.testing.expect(tracker.retirementSnapshot(io, @splat(64), first.sequence).recorded);
    try std.testing.expect(!tracker.retirementSnapshot(io, @splat(65), first.sequence).recorded);
    tracker.fence(io);
    try std.testing.expect(tracker.retirementSnapshot(io, @splat(64), first.sequence).uncertain);
    try tracker.leave(io, next);
    try std.testing.expect(tracker.retirementSnapshot(io, @splat(64), next.sequence).uncertain);
}

test "bounded retirement history eviction remains missing rather than terminal" {
    var tracker: ownership.Tracker = .{};
    try tracker.initialize(io, @splat(66));
    const first = try tracker.enter(io);
    try tracker.associate(io, first, @splat(67));
    try tracker.leave(io, first);
    for (0..ownership.capacity) |_| {
        const request = try tracker.enter(io);
        try tracker.associate(io, request, @splat(68));
        try tracker.leave(io, request);
    }
    const old = tracker.retirementSnapshot(io, @splat(67), first.sequence);
    try std.testing.expect(!old.recorded and old.uncertain);
    try std.testing.expect(!tracker.snapshot(io).uncertain);
}

test "newer release never records retirement for an older retained request" {
    var tracker: ownership.Tracker = .{ .primary_guard = true };
    try tracker.initialize(io, @splat(69));
    const older = try tracker.enter(io);
    try tracker.associate(io, older, @splat(70));
    try tracker.bind(io, older, "model-a");
    try tracker.retain(io, older);
    const newer = try tracker.enter(io);
    try tracker.associate(io, newer, @splat(71));
    try tracker.bind(io, newer, "model-a");
    try tracker.leave(io, newer);
    try std.testing.expect(tracker.retirementSnapshot(io, @splat(71), newer.sequence).recorded);
    try tracker.leave(io, older);
    try std.testing.expect(!tracker.retirementSnapshot(io, @splat(70), older.sequence).recorded);
    try tracker.leave(io, older);
    try std.testing.expect(tracker.retirementSnapshot(io, @splat(70), older.sequence).recorded);
}

test "retirement history counter exhaustion fences rather than wrapping" {
    var tracker: ownership.Tracker = .{};
    try tracker.initialize(io, @splat(72));
    const root = try tracker.enter(io);
    try tracker.associate(io, root, @splat(73));
    tracker.retirement_sequence = std.math.maxInt(u64);
    try tracker.leave(io, root);
    const record = tracker.retirementSnapshot(io, @splat(73), root.sequence);
    try std.testing.expect(!record.recorded and record.uncertain);
    try std.testing.expect(tracker.snapshot(io).uncertain);
}

test "handoff establishes original root before a fast incoming request" {
    var tracker: ownership.Tracker = .{ .primary_guard = true };
    try tracker.initialize(io, @splat(81));
    const registered=try tracker.registerHandoff(io,@splat(82));
    const before=tracker.correlationSnapshot(io,@splat(82));
    try std.testing.expect(before.found and before.root_sequence==registered.root_sequence);
    const incoming=try tracker.enter(io);
    try std.testing.expectError(error.DuplicateCorrelation,tracker.associate(io,incoming,@splat(82)));
    try std.testing.expectError(error.MissingHandoff,tracker.associateHandoff(io,incoming,@splat(82),registered.root_sequence+1));
    try tracker.associateHandoff(io,incoming,@splat(82),registered.root_sequence);
    try tracker.bind(io,incoming,"model-a");
    const during=tracker.correlationSnapshot(io,@splat(82));
    try std.testing.expectEqual(registered.root_sequence,during.root_sequence);
    try std.testing.expectEqual(@as(usize,1),during.owners);
    try std.testing.expectEqual(ownership.HandoffState.handed_off,tracker.cancelHandoff(io,@splat(82),registered.root_sequence));
    try tracker.leave(io,incoming);
    const retired=tracker.retirementSnapshot(io,@splat(82),registered.root_sequence);
    try std.testing.expect(retired.recorded and !retired.uncertain);
}

test "handoff cancellation denies the original late request even after history eviction" {
    var tracker: ownership.Tracker = .{};
    try tracker.initialize(io,@splat(83));
    const registered=try tracker.registerHandoff(io,@splat(84));
    try std.testing.expectEqual(ownership.HandoffState.cancelled,tracker.cancelHandoff(io,@splat(84),registered.root_sequence));
    try std.testing.expectEqual(ownership.HandoffState.cancelled,tracker.cancelHandoff(io,@splat(84),registered.root_sequence));
    const incoming=try tracker.enter(io);
    try std.testing.expectError(error.MissingHandoff,tracker.associateHandoff(io,incoming,@splat(84),registered.root_sequence));
    try tracker.leave(io,incoming);
    for(0..ownership.capacity) |_| {
        const request=try tracker.enter(io);try tracker.associate(io,request,@splat(85));try tracker.leave(io,request);
    }
    try std.testing.expectEqual(ownership.HandoffState.unknown,tracker.cancelHandoff(io,@splat(84),registered.root_sequence));
    const newer=try tracker.registerHandoff(io,@splat(84));
    try std.testing.expect(newer.root_sequence!=registered.root_sequence);
    const late=try tracker.enter(io);
    try std.testing.expectError(error.MissingHandoff,tracker.associateHandoff(io,late,@splat(84),registered.root_sequence));
    try tracker.leave(io,late);
    try std.testing.expectEqual(ownership.HandoffState.cancelled,tracker.cancelHandoff(io,@splat(84),newer.root_sequence));
}

test "handoff pending capacity and independent uncertainty never turn into native admission" {
    var tracker: ownership.Tracker = .{};
    try tracker.initialize(io,@splat(86));
    var registrations:[ownership.handoff_capacity]ownership.HandoffRegistration=undefined;
    for(&registrations,0..) |*registration,index| {
        var id:ownership.CorrelationID=@splat(0);id[0]=@intCast(index);
        registration.*=try tracker.registerHandoff(io,id);
    }
    try std.testing.expectError(error.HandoffCapacity,tracker.registerHandoff(io,@splat(87)));
    try std.testing.expect(!tracker.snapshot(io).uncertain);
    tracker.fence(io);
    try std.testing.expectEqual(ownership.HandoffState.unknown,tracker.cancelHandoff(io,@splat(0),registrations[0].root_sequence));
    try std.testing.expectEqual(ownership.handoff_capacity,tracker.snapshot(io).owned);
}

test "handoff cancellation and incoming association have one atomic winner" {
    const Race=struct {
        tracker:*ownership.Tracker,
        incoming:ownership.Token,
        registration:ownership.HandoffRegistration,
        start:std.atomic.Value(bool)=.init(false),
        associated:bool=false,
        failed:bool=false,
        outcome:ownership.HandoffState=.unknown,
        fn associate(self:*@This())void {
            while(!self.start.load(.acquire))std.atomic.spinLoopHint();
            self.tracker.associateHandoff(io,self.incoming,self.registration.correlation,self.registration.root_sequence) catch |err| {
                if(err!=error.MissingHandoff)self.failed=true;
                return;
            };
            self.associated=true;
        }
        fn cancel(self:*@This())void {
            while(!self.start.load(.acquire))std.atomic.spinLoopHint();
            self.outcome=self.tracker.cancelHandoff(io,self.registration.correlation,self.registration.root_sequence);
        }
    };
    for(0..32) |_| {
        var tracker:ownership.Tracker=.{};
        try tracker.initialize(io,@splat(90));
        const registered=try tracker.registerHandoff(io,@splat(91));
        const incoming=try tracker.enter(io);
        var race:Race=.{.tracker=&tracker,.incoming=incoming,.registration=registered};
        const first=try std.Thread.spawn(.{},Race.associate,.{&race});
        const second=std.Thread.spawn(.{},Race.cancel,.{&race}) catch |err| {
            race.start.store(true,.release);first.join();return err;
        };
        race.start.store(true,.release);first.join();second.join();
        try std.testing.expect(!race.failed);
        if(race.outcome==.cancelled) {
            try std.testing.expect(!race.associated);
            try std.testing.expectError(error.MissingHandoff,tracker.associateHandoff(io,incoming,@splat(91),registered.root_sequence));
        } else {
            try std.testing.expect(race.outcome==.handed_off and race.associated);
            try std.testing.expectEqual(registered.root_sequence,tracker.correlationSnapshot(io,@splat(91)).root_sequence);
        }
        try tracker.leave(io,incoming);
        try std.testing.expectEqual(@as(usize,0),tracker.snapshot(io).owned);
        try std.testing.expect(!tracker.snapshot(io).uncertain);
    }
}
