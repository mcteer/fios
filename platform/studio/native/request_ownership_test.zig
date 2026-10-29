const std = @import("std");
const ownership = @import("request_ownership.zig");
const io = std.testing.io;

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
