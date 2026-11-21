// Ordinary fixed readonly frame/identity/unavailable semantics only.
const std = @import("std");
const protocol = @import("control_protocol.zig");
const ownership = @import("request_ownership.zig");
test "fios backend fence readonly frame preserves source and partial values" {
    const io = std.testing.io;
    var tracker: ownership.Tracker = .{};
    try tracker.initialize(io, @splat(7));
    var request: [32]u8 = @splat(0);
    @memcpy(request[0..4], "FIB9");request[4] = 1;
    @memcpy(request[8..24], &(@as([16]u8, @splat(7))));
    const Hook = struct {
        var calls: u32 = 0;
        fn read() protocol.BackendFenceReadings {
            calls += 1;
            return .{ .mimo_warm_uncertain = true, .ds4_metal_uncertainty = 17, .ds4_host_uncertainty = 3 };
        }
    };
    const unavailable = protocol.dispatchBackendFences(&tracker, io, &request, null);
    try std.testing.expectEqualSlices(u8, "FIF9", unavailable[0..4]);
    try std.testing.expectEqual(@as(u8, 1), unavailable[4]);
    try std.testing.expectEqual(@as(u8, 0), unavailable[5]);
    try std.testing.expectEqual(@as(u8, 0), unavailable[6]);
    const value = protocol.dispatchBackendFences(&tracker, io, &request, &Hook.read);
    try std.testing.expectEqual(@as(u8, 7), value[6]);
    try std.testing.expectEqual(@as(u8, 1), value[7]);
    try std.testing.expectEqualSlices(u8, &(@as([16]u8, @splat(7))), value[8..24]);
    try std.testing.expect(std.mem.readInt(u64, value[24..32], .big) > std.mem.readInt(u64, unavailable[24..32], .big));
    try std.testing.expect(std.mem.readInt(u64, value[32..40], .big) > 0);
    try std.testing.expectEqual(@as(u32, 17), std.mem.readInt(u32, value[40..44], .big));
    try std.testing.expectEqual(@as(u32, 3), std.mem.readInt(u32, value[44..48], .big));
    try std.testing.expect(std.mem.allEqual(u8, value[48..64], 0));
    request[8] = 9;
    const changed = protocol.dispatchBackendFences(&tracker, io, &request, &Hook.read);
    try std.testing.expectEqual(@intFromEnum(protocol.Status.wrong_instance), changed[5]);
    try std.testing.expectEqual(@as(u32, 1), Hook.calls);
    const current = tracker.snapshot(io);
    try std.testing.expect(!current.admissions_closed and !current.uncertain and current.owned == 0);
    std.debug.print("PASS: readonly backend frame binds source/clock/sequence and distinct unavailable partial values without admission changes\n", .{});
}
