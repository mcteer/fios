// Actual host provider, opaque payload and original roots; metadata only.
const std = @import("std");
const native = @import("native");
const owners = native.owners;
extern fn fios_cpu_fixture_capture(*anyopaque) c_int;
extern fn fios_cpu_fixture_worker(*anyopaque, *const anyopaque, *const anyopaque) c_int;
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    try owners.shared().initialize(io, @splat(89));
    try native.provider.install();
    for (0..2) |_| {
        const first = try owners.shared().enter(io);
        const second = try owners.shared().enter(io);
        const previous = try owners.shared().enter(io);
        for ([_]owners.Token{ first, second, previous }) |token| try owners.shared().bind(io, token, "fixture/cpu-media-unit");
        const roots = [_]owners.Token{ first, second };
        owners.current_group().* = &roots;
        var payload: native.hooks.Payload = .{};
        if (fios_cpu_fixture_capture(@ptrCast(&payload)) != 1) return error.UnitCaptureMissing;
        owners.current_group().* = null;
        try owners.shared().leave(io, first);
        try owners.shared().leave(io, second);
        if (owners.shared().snapshot(io).owned != 3) return error.OriginalRootsLost;
        const Worker = struct {
            payload: *native.hooks.Payload,
            roots: *const [2]owners.Token,
            previous: *const owners.Token,
            result: c_int = 0,
            fn run(self: *@This()) void {
                self.result = fios_cpu_fixture_worker(@ptrCast(self.payload), @ptrCast(self.roots), @ptrCast(self.previous));
            }
        };
        var worker: Worker = .{ .payload = &payload, .roots = &roots, .previous = &previous };
        const thread = try std.Thread.spawn(.{}, Worker.run, .{&worker});
        thread.join();
        if (worker.result != 1 or owners.shared().snapshot(io).owned != 1) return error.UnitOriginsOrCleanupLost;
        try owners.shared().leave(io, previous);
        if (owners.shared().snapshot(io).owned != 0 or owners.current().* != null or owners.current_group().* != null) return error.LocalCustodyLeaked;
    }
    std.debug.print("PASS: actual host and plugin CPU hooks retain both original roots and restore worker TLS\n", .{});
}
