// Actual parent refusal -> fixed negative probe -> original root retention.
const std = @import("std");
const native = @import("native");
const owners = native.owners;
extern fn fios_fixture_llama_parent_busy() c_int;
pub export fn mlx_llama_log(_: bool, _: [*:0]const u8) void {}
fn known() bool { return native.probe.known(false, true); }
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    if (known()) return error.InitialFence;
    owners.shared().primary_guard = false; // Match diagnostic-only host startup.
    try owners.shared().initialize(io, @splat(97));
    try owners.shared().enrollDiagnosticUncertaintyProbe(io, known);
    const root = try owners.shared().enter(io);
    const correlation: owners.CorrelationID = @splat(101);
    try owners.shared().associate(io, root, correlation);
    try owners.shared().bind(io, root, "fixture/llama-parent-root");
    owners.current().* = root;
    const sender = (try owners.retainCurrent(io)).?;
    const Worker = struct {
        io: std.Io,
        scope: native.queue.Scope,
        retained: bool = false,
        fn run(self: *@This()) void {
            self.scope.enter(self.io) catch return;
            if (fios_fixture_llama_parent_busy() != 1) return;
            const released = self.scope.finish(self.io);
            self.retained = !released and owners.current().* == null and owners.current_group().* == null;
        }
    };
    var worker: Worker = .{ .io = io, .scope = try native.queue.Scope.retain(io, &sender) };
    owners.current().* = null;
    try owners.shared().leave(io, root);
    if (!sender.releaseIfCertain(io)) return error.SenderNotReleased;
    const thread = try std.Thread.spawn(.{}, Worker.run, .{&worker});
    thread.join();
    const snapshot = owners.shared().snapshot(io);
    const lineage = owners.shared().correlationSnapshot(io, correlation);
    if (!worker.retained or !snapshot.uncertain or snapshot.owned != 1 or !lineage.found or !lineage.uncertain or lineage.root_sequence != root.sequence or lineage.references != 1)
        return error.OriginalUncertaintyLost;
    std.debug.print("PASS: actual llama parent refusal preserves original lineage through local worker completion\n", .{});
}
