// Ordinary native TLS/reference transfer only; no SDK/device completion claim.
const std = @import("std");
const ownership = @import("request_ownership.zig");
const sdk = @import("sdk_request_ownership.zig");
fn require(value: bool) void { if (!value) @panic("native SDK owner context mismatch"); }
test "fios SDK owner context transfers and restores original references" {
    const io = std.testing.io;
    try std.testing.expect(sdk.fios_native_request_owners_capture() == null);
    try ownership.shared.initialize(io, @splat(7));
    try sdk.initialize(io);
    try std.testing.expect(sdk.fios_native_request_owners_capture() == null);
    const root = try ownership.shared.enter(io);
    try ownership.shared.bind(io, root, "fixture/original");
    try ownership.shared.active(io, root);
    const second = try ownership.shared.enter(io);
    try ownership.shared.bind(io, second, "fixture/original");
    try ownership.shared.active(io, second);
    const group = [_]ownership.Token{root, second};
    ownership.current = root;
    ownership.current_group = &group;
    const captured = sdk.fios_native_request_owners_capture() orelse return error.NoCapturedOwner;
    var captured_held = true;
    defer if (captured_held) sdk.fios_native_request_owners_release(captured);
    ownership.current = null;
    ownership.current_group = null;
    try ownership.shared.leave(io, root);
    try ownership.shared.leave(io, second);
    try std.testing.expect(ownership.shared.hasRetainedWork(io));
    const Worker = struct {
        fn run(context: *anyopaque, expected: ownership.Token, expected_second: ownership.Token, child: *?*anyopaque) void {
            require(ownership.current == null and ownership.current_group == null);
            const temporary = ownership.shared.enter(std.testing.io) catch @panic("temporary owner");
            ownership.current = temporary;
            const first = sdk.fios_native_request_owners_enter(context);
            require(first != 0 and ownership.current.?.sequence == expected.sequence);
            require(ownership.current_group.?.len == 2);
            require(ownership.current_group.?[1].sequence == expected_second.sequence);
            child.* = sdk.fios_native_request_owners_capture();
            require(child.* != null);
            const nested = sdk.fios_native_request_owners_enter(child.*);
            require(nested > first);
            require(sdk.fios_native_request_owners_leave(nested) == 0);
            require(ownership.current.?.sequence == expected.sequence);
            require(sdk.fios_native_request_owners_leave(first) == 0);
            require(ownership.current.?.sequence == temporary.sequence and ownership.current_group == null);
            ownership.current = null;
            ownership.shared.leave(std.testing.io, temporary) catch @panic("temporary release");
        }
    };
    var descendant: ?*anyopaque = null;
    const thread = try std.Thread.spawn(.{}, Worker.run, .{ captured, root, second, &descendant });
    thread.join();
    const child = descendant orelse return error.NoDescendant;
    try std.testing.expectEqual(@as(u32, 2), sdk.diagnostic().active_contexts);
    try std.testing.expect(!sdk.diagnostic().uncertain);
    try std.testing.expect(ownership.current == null and ownership.current_group == null);
    ownership.shared.fence(io);
    sdk.fios_native_request_owners_release(child);
    try std.testing.expect(ownership.shared.hasRetainedWork(io));
    try std.testing.expectEqual(@as(u32, 1), sdk.diagnostic().active_contexts);
    try std.testing.expect(ownership.shared.snapshot(io).uncertain);
    sdk.fios_native_request_owners_release(captured);
    captured_held = false;
    try std.testing.expect(!ownership.shared.hasRetainedWork(io));
    try std.testing.expectEqual(@as(u32, 0), sdk.diagnostic().active_contexts);
    try std.testing.expect(ownership.shared.snapshot(io).uncertain);
    std.debug.print("PASS: actual native owner contexts retain original roots across threads and nested TLS scopes, restore prior context and preserve uncertainty\n", .{});
}
