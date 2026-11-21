// Genuine separately compiled ownership modules; metadata only, no model/SDK.
const std = @import("std");
const native = @import("native");
const owners = native.ownership;
extern fn fios_fixture_unit_ledger() *anyopaque;
extern fn fios_fixture_unit_sequence() u64;
extern fn fios_fixture_unit_group_size() usize;
extern fn fios_fixture_unit_worker(io: *const anyopaque, origins: *const anyopaque) c_int;
fn ledger() *owners.Tracker {
    return if (@hasDecl(owners, "ledger_storage")) owners.shared() else &owners.shared;
}
fn current() *?owners.Token {
    return if (@hasDecl(owners, "ledger_storage")) owners.current() else &owners.current;
}
fn group() *?[]const owners.Token {
    return if (@hasDecl(owners, "ledger_storage")) owners.current_group() else &owners.current_group;
}
pub export fn fios_fixture_host_group_size() usize {
    return if (group().*) |value| value.len else 0;
}
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    if (fios_fixture_unit_ledger() != @as(*anyopaque, @ptrCast(ledger()))) {
        std.debug.print("FIO_NATIVE_LEDGER_PARTITIONED\n", .{});return error.PartitionedLedger;
    }
    try ledger().initialize(io, @splat(11));
    const root = try ledger().enter(io);
    try ledger().bind(io, root, "fixture/unit-origin");try ledger().active(io, root);
    current().* = root;
    const tokens = [_]owners.Token{root};group().* = &tokens;
    if (fios_fixture_unit_sequence() != root.sequence or fios_fixture_unit_group_size() != 1) return error.PartitionedTLS;
    const captured = try ledger().retainTokens(io, &tokens);
    defer captured.release(io);
    const Worker = struct {
        io: *const std.Io,
        origins: *const owners.Retained,
        result: c_int = 0,
        fn run(self: *@This()) void {
            if (current().* != null or group().* != null) return;
            self.result = fios_fixture_unit_worker(@ptrCast(self.io), @ptrCast(self.origins));
            if (current().* != null or group().* != null) self.result = 0;
        }
    };
    var worker: Worker = .{ .io = &io, .origins = &captured };
    const thread = try std.Thread.spawn(.{}, Worker.run, .{&worker});thread.join();
    if (worker.result != 1 or current().*.?.sequence != root.sequence or group().*.?.len != 1) return error.PartitionedWorkerTLS;
    current().* = null;group().* = null;try ledger().leave(io, root);
    std.debug.print("PASS: actual host/unit ledger and per-thread origins share storage across queue scope; no native authority\n", .{});
}
