// The same unit marker and shared-state path the upstream engine uses.
pub const mlx_serve_unit = true;
const std = @import("std");
const native = @import("native");
const owners = native.ownership;
extern fn fios_fixture_host_group_size() usize;
fn ledger() *owners.Tracker {
    return if (@hasDecl(owners, "ledger_storage")) owners.shared() else &owners.shared;
}
fn current() *?owners.Token {
    return if (@hasDecl(owners, "ledger_storage")) owners.current() else &owners.current;
}
fn group() *?[]const owners.Token {
    return if (@hasDecl(owners, "ledger_storage")) owners.current_group() else &owners.current_group;
}
pub export fn fios_fixture_unit_ledger() *anyopaque {return @ptrCast(ledger());}
pub export fn fios_fixture_unit_sequence() u64 {return if (current().*) |token| token.sequence else 0;}
pub export fn fios_fixture_unit_group_size() usize {return if (group().*) |value| value.len else 0;}
pub export fn fios_fixture_unit_worker(raw_io: *const anyopaque, raw_origin: *const anyopaque) c_int {
    const io = @as(*const std.Io, @ptrCast(@alignCast(raw_io))).*;
    const origin: *const owners.Retained = @ptrCast(@alignCast(raw_origin));
    var scope = native.queued.Scope.retain(io, origin) catch return 0;
    scope.enter(io) catch return 0;
    const observed = fios_fixture_host_group_size() == 1 and fios_fixture_unit_group_size() == 1;
    const finished = scope.finish(io);
    return if (observed and finished) 1 else 0;
}
