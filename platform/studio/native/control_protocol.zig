// Finite native-private control protocol. Transport must authenticate its peer.
// No shell, PID selection, force/quit, device-terminal or coverage authority.
const std = @import("std");
const ownership = @import("request_ownership.zig");
const device = @import("device_owner.zig");
pub const OwnerBarrier = struct { context: *anyopaque, probe: *const fn (*anyopaque) device.Reading };
pub const request_size = 32;
pub const response_size = 64;
pub const Status = enum(u8) { ok, invalid, maintenance, wrong_instance };

pub fn dispatch(tracker: *ownership.Tracker, io: std.Io, request: *const [request_size]u8) [response_size]u8 {
    return dispatchWithBarrier(tracker, io, request, null);
}
pub fn dispatchWithBarrier(tracker: *ownership.Tracker, io: std.Io, request: *const [request_size]u8, barrier: ?OwnerBarrier) [response_size]u8 {
    var status: Status = .ok;
    var reading: device.Reading = .{ .outcome = .not_requested };
    const op = request[5];
    const sequence = std.mem.readInt(u64, request[8..16], .big);
    const before = tracker.snapshot(io);
    if (!std.mem.eql(u8, request[0..4], "FIC9") or request[4] != 2 or
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
    const snapshot = tracker.snapshot(io);
    if (op == 3 and reading.outcome == .owner_streams_synchronized and
        (!snapshot.admissions_closed or snapshot.admission_pause != sequence or snapshot.owned != 0 or snapshot.uncertain or reading.streams > 256)) reading = .{};
    var response: [response_size]u8 = @splat(0);
    @memcpy(response[0..4], "FIR9");
    response[4] = 2;
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
