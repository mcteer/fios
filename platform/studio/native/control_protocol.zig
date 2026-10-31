// Finite native-private control protocol. Transport must authenticate its peer.
// No shell, PID selection, force/quit, device-terminal or coverage authority.
const std = @import("std");
const ownership = @import("request_ownership.zig");
const device = @import("device_owner.zig");
pub const OwnerBarrier = struct { context: *anyopaque, probe: *const fn (*anyopaque) device.Reading };
pub const request_size = 32;
pub const response_size = 64;
pub const timestamped_response_size = 80;
pub const lineage_request_size = 64;
pub const lineage_response_size = 112;
pub const Status = enum(u8) { ok, invalid, maintenance, wrong_instance };

// Separate readonly frame namespace: never reinterpret lineage bytes as an
// ingress action. A missing live lineage is unknown, not terminal/not-sent.
pub fn dispatchLineage(tracker: *ownership.Tracker, io: std.Io, request: *const [lineage_request_size]u8) [lineage_response_size]u8 {
    var response: [lineage_response_size]u8 = @splat(0);
    @memcpy(response[0..4], "FIP9"); response[4] = 1; response[7] = 1;
    @memcpy(response[24..56], request[24..56]);
    if (!std.mem.eql(u8, request[0..4], "FIQ9") or request[4] != 1 or request[5] != 0 or
        request[6] != 0 or request[7] != 0 or !std.mem.allEqual(u8, request[56..64], 0)) {
        response[5] = @intFromEnum(Status.invalid);
        return response;
    }
    const snapshot = tracker.correlationSnapshot(io, request[24..56].*);
    @memcpy(response[8..24], &snapshot.instance);
    std.mem.writeInt(u64, response[56..64], snapshot.sample_sequence, .big);
    if (!std.mem.eql(u8, request[8..24], &snapshot.instance)) {
        response[5] = @intFromEnum(Status.wrong_instance);
        return response;
    }
    response[6] = @intFromBool(snapshot.found);
    response[7] = @intFromBool(snapshot.uncertain);
    std.mem.writeInt(u64, response[64..72], snapshot.root_sequence, .big);
    std.mem.writeInt(u64, response[72..80], snapshot.references, .big);
    inline for (.{snapshot.owners,snapshot.ingress,snapshot.preparing,snapshot.active,snapshot.responding}, 0..) |value,index| {
        std.mem.writeInt(u32, response[80 + index * 4 ..][0..4], @intCast(value), .big);
    }
    return response;
}

pub fn dispatch(tracker: *ownership.Tracker, io: std.Io, request: *const [request_size]u8) [response_size]u8 {
    return dispatchWithBarrier(tracker, io, request, null);
}
pub fn dispatchWithBarrier(tracker: *ownership.Tracker, io: std.Io, request: *const [request_size]u8, barrier: ?OwnerBarrier) [response_size]u8 {
    return dispatchVersion(2, tracker, io, request, barrier);
}
pub fn dispatchTimestamped(tracker: *ownership.Tracker, io: std.Io, request: *const [request_size]u8, barrier: ?OwnerBarrier) [timestamped_response_size]u8 {
    return dispatchVersion(3, tracker, io, request, barrier);
}
fn dispatchVersion(comptime version: u8, tracker: *ownership.Tracker, io: std.Io, request: *const [request_size]u8, barrier: ?OwnerBarrier) [if (version == 3) timestamped_response_size else response_size]u8 {
    var status: Status = .ok;
    var reading: device.Reading = .{ .outcome = .not_requested };
    const op = request[5];
    const sequence = std.mem.readInt(u64, request[8..16], .big);
    const before = tracker.snapshot(io);
    if (!std.mem.eql(u8, request[0..4], "FIC9") or request[4] != version or
        request[6] != 0 or request[7] != 0 or op > 3 or (op < 2 and sequence != 0))
    {
        status = .invalid;
    } else if (op != 0 and (!before.initialized or !std.mem.eql(u8, request[16..32], &before.instance))) {
        status = .wrong_instance;
    } else switch (op) {
        0 => {}, // Observe is not inference ownership or quiescence proof.
        1 => { _ = tracker.pauseAdmissions(io) catch { status = .maintenance; }; },
        2 => tracker.resumeAdmissions(io, .{ .instance = request[16..32].*, .sequence = sequence }) catch { status = .invalid; },
        3 => {
            if (!before.admissions_closed or sequence == 0 or sequence != before.admission_pause) status = .invalid
            else if (barrier) |probe| { reading = probe.probe(probe.context); }
            else reading = .{};
        },
        else => unreachable,
    }
    // Capture the source clock before taking the final coherent tracker
    // snapshot. Serialization/transport cannot refresh this original time.
    const captured_at = if (version == 3) std.Io.Clock.real.now(io).toMilliseconds() else 0;
    const snapshot = tracker.snapshot(io);
    if (op == 3 and reading.outcome == .owner_streams_synchronized and
        (!snapshot.admissions_closed or snapshot.admission_pause != sequence or snapshot.owned != 0 or snapshot.uncertain or reading.streams > 256)) reading = .{};
    var response: [if (version == 3) timestamped_response_size else response_size]u8 = @splat(0);
    @memcpy(response[0..4], "FIR9");
    response[4] = version;
    response[5] = op;
    response[6] = @intFromEnum(status);
    @memcpy(response[8..24], &snapshot.instance);
    std.mem.writeInt(u64, response[24..32], snapshot.admission_pause, .big);
    inline for (.{ snapshot.owned, snapshot.ingress, snapshot.preparing, snapshot.active, snapshot.responding, snapshot.model_count }, 0..) |value, index| {
        std.mem.writeInt(u32, response[32 + index * 4 ..][0..4], @intCast(value), .big);
    }
    response[56] = @intFromBool(snapshot.admissions_closed);
    response[57] = @intFromBool(snapshot.uncertain);
    response[58] = @intFromEnum(reading.outcome);
    std.mem.writeInt(u32, response[60..64], reading.streams, .big);
    if (version == 3) {
        std.mem.writeInt(u64, response[64..72], snapshot.sample_sequence, .big);
        // An unavailable clock is explicit metadata absence, not receipt time.
        const stamp: u64 = if (captured_at > 0 and captured_at <= ownership.maximum_sample_sequence)
            @intCast(captured_at) else std.math.maxInt(u64);
        std.mem.writeInt(u64, response[72..80], stamp, .big);
    }
    return response;
}

test "partial owner-stream probe requires exact paused source and never grants coverage" {
    const Hook = struct {
        fn run(context: *anyopaque) device.Reading {
            const called: *bool = @ptrCast(@alignCast(context));
            called.* = true;
            return .{ .outcome = .owner_streams_synchronized, .streams = 1 };
        }
    };
    const io = std.testing.io;
    var tracker: ownership.Tracker = .{};
    try tracker.initialize(io, @splat(7));
    var request: [request_size]u8 = @splat(0);
    @memcpy(request[0..4], "FIC9"); request[4] = 2; request[5] = 3;
    @memcpy(request[16..32], &(@as([16]u8, @splat(7))));
    std.mem.writeInt(u64, request[8..16], 1, .big);
    var called = false;
    const hook: OwnerBarrier = .{ .context = &called, .probe = &Hook.run };
    var response = dispatchWithBarrier(&tracker, io, &request, hook);
    try std.testing.expectEqual(@intFromEnum(Status.invalid), response[6]);
    try std.testing.expect(!called);
    const pause = try tracker.pauseAdmissions(io);
    response = dispatchWithBarrier(&tracker, io, &request, hook);
    try std.testing.expect(called);
    try std.testing.expectEqual(@intFromEnum(device.Outcome.owner_streams_synchronized), response[58]);
    try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, response[60..64], .big));
    try tracker.resumeAdmissions(io, pause);
}

test "finite private control rejects malformed and cross-instance authority" {
    const io = std.testing.io;
    var tracker: ownership.Tracker = .{};
    try tracker.initialize(io, @splat(7));
    var request: [request_size]u8 = @splat(0);
    @memcpy(request[0..4], "FIC9"); request[4] = 2;
    var response = dispatch(&tracker, io, &request);
    try std.testing.expectEqual(@as(u8, 0), response[6]);
    try std.testing.expectEqualSlices(u8, &(@as([16]u8, @splat(7))), response[8..24]);
    request[5] = 1;
    response = dispatch(&tracker, io, &request);
    try std.testing.expectEqual(@intFromEnum(Status.wrong_instance), response[6]);
    try std.testing.expect(!tracker.snapshot(io).admissions_closed);
    @memcpy(request[16..32], &(@as([16]u8, @splat(7))));
    request[6] = 1;
    response = dispatch(&tracker, io, &request);
    try std.testing.expectEqual(@intFromEnum(Status.invalid), response[6]);
    try std.testing.expect(!tracker.snapshot(io).admissions_closed);
    request[6] = 0;
    response = dispatch(&tracker, io, &request);
    try std.testing.expectEqual(@as(u8, 0), response[6]);
    try std.testing.expectEqual(@as(u8, 1), response[56]);
    const sequence = std.mem.readInt(u64, response[24..32], .big);
    request[5] = 2;
    std.mem.writeInt(u64, request[8..16], sequence, .big);
    response = dispatch(&tracker, io, &request);
    try std.testing.expectEqual(@as(u8, 0), response[56]);
    response = dispatch(&tracker, io, &request);
    try std.testing.expectEqual(@intFromEnum(Status.invalid), response[6]);
    try std.testing.expectEqual(@as(u8, 1), response[57]);
}

test "readonly lineage frames preserve retained ownership and missing stays unknown" {
    const io = std.testing.io;
    var tracker: ownership.Tracker = .{ .primary_guard = true };
    try tracker.initialize(io, @splat(31));
    var request: [lineage_request_size]u8 = @splat(0);
    @memcpy(request[0..4], "FIQ9"); request[4] = 1;
    @memcpy(request[8..24], &(@as([16]u8, @splat(31))));
    const id = try ownership.parseCorrelationHex("29fc52e328d588a1afee500c96d67ccc1045a873a328efccec3dc9ddfaef2cf5");
    @memcpy(request[24..56], &id);
    var response = dispatchLineage(&tracker, io, &request);
    try std.testing.expectEqual(@as(u8, 0), response[5]);
    try std.testing.expectEqual(@as(u8, 0), response[6]);
    try std.testing.expectEqual(@as(u8, 1), response[7]);
    const first = std.mem.readInt(u64, response[56..64], .big);
    const root = try tracker.enter(io);
    try tracker.associate(io, root, id);
    try tracker.bind(io, root, "test/model");
    const child = try tracker.reservePreparation(io, root, "test/model");
    try tracker.leave(io, root);
    response = dispatchLineage(&tracker, io, &request);
    try std.testing.expectEqual(@as(u8, 1), response[6]);
    try std.testing.expectEqual(@as(u8, 0), response[7]);
    try std.testing.expectEqualSlices(u8, &id, response[24..56]);
    try std.testing.expectEqual(root.sequence, std.mem.readInt(u64, response[64..72], .big));
    try std.testing.expectEqual(@as(u64, 1), std.mem.readInt(u64, response[72..80], .big));
    try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, response[80..84], .big));
    try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, response[88..92], .big));
    try std.testing.expect(std.mem.readInt(u64, response[56..64], .big) > first);
    request[8] ^= 1;
    response = dispatchLineage(&tracker, io, &request);
    try std.testing.expectEqual(@intFromEnum(Status.wrong_instance), response[5]);
    try std.testing.expectEqual(@as(u8, 0), response[6]);
    try std.testing.expectEqual(@as(u8, 1), response[7]);
    request[8] ^= 1; request[56] = 1;
    try std.testing.expectEqual(@intFromEnum(Status.invalid), dispatchLineage(&tracker, io, &request)[5]);
    request[56] = 0;
    try std.testing.expectEqual(@as(usize, 1), tracker.snapshot(io).owned);
    try tracker.leave(io, child);
    response = dispatchLineage(&tracker, io, &request);
    try std.testing.expectEqual(@as(u8, 0), response[6]);
    try std.testing.expectEqual(@as(u8, 1), response[7]);
    try std.testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, response[64..72], .big));
}

test "timestamped control replies carry native capture metadata" {
    const io = std.testing.io;
    var tracker: ownership.Tracker = .{};
    try tracker.initialize(io, @splat(9));
    const token = try tracker.enter(io);
    var request: [request_size]u8 = @splat(0);
    @memcpy(request[0..4], "FIC9"); request[4] = 3;
    const began = std.Io.Clock.real.now(io).toMilliseconds();
    const first = dispatchTimestamped(&tracker, io, &request, null);
    const ended = std.Io.Clock.real.now(io).toMilliseconds();
    try std.testing.expectEqual(@as(usize, 80), first.len);
    try std.testing.expectEqual(@as(u8, 3), first[4]);
    try std.testing.expectEqual(@as(u8, 0), first[6]);
    try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, first[32..36], .big));
    try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, first[36..40], .big));
    const sequence = std.mem.readInt(u64, first[64..72], .big);
    const captured = std.mem.readInt(u64, first[72..80], .big);
    try std.testing.expect(sequence > 0);
    try std.testing.expect(captured >= began and captured <= ended);
    try tracker.leave(io, token);
    const second = dispatchTimestamped(&tracker, io, &request, null);
    try std.testing.expect(std.mem.readInt(u64, second[64..72], .big) > sequence);
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, second[32..36], .big));
    try std.testing.expectEqualSlices(u8, first[8..24], second[8..24]);
    request[4] = 2;
    const legacy = dispatch(&tracker, io, &request);
    try std.testing.expectEqual(@as(usize, 64), legacy.len);
    try std.testing.expectEqual(@as(u8, 2), legacy[4]);
}
