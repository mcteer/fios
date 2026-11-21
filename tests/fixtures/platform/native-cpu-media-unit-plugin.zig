// Actual SDK Shared storage in a separately compiled plugin-shaped object.
pub const mlx_serve_unit = true;
const std = @import("std");
const native = @import("native");
const owners = native.owners;
pub export fn fios_cpu_fixture_capture(raw: *anyopaque) c_int {
    const hooks = native.hooks.current() orelse return 0;
    return if (hooks.capture(@ptrCast(@alignCast(raw))) == .retained) 1 else 0;
}
pub export fn fios_cpu_fixture_worker(raw: *anyopaque, expected_raw: *const anyopaque, previous_raw: *const anyopaque) c_int {
    const payload: *native.hooks.Payload = @ptrCast(@alignCast(raw));
    const expected: *const [2]owners.Token = @ptrCast(@alignCast(expected_raw));
    const previous: *const owners.Token = @ptrCast(@alignCast(previous_raw));
    if (owners.current().* != null or owners.current_group().* != null) return 0;
    owners.current().* = previous.*;
    defer owners.current().* = null;
    const hooks = native.hooks.current() orelse return 0;
    if (!hooks.enter(payload)) return 0;
    var matched = false;
    if (owners.current_group().*) |group| matched = group.len == 2 and std.meta.eql(group[0], expected[0]) and std.meta.eql(group[1], expected[1]);
    hooks.finish(payload);
    const restored = owners.current_group().* == null and owners.current().* != null and std.meta.eql(owners.current().*.?, previous.*);
    return if (matched and restored) 1 else 0;
}
