//! Fixed private-control preparation frames. Authentication belongs to the
//! existing source-fixture-only Unix transport, never to a model-facing route.
const std = @import("std");
const owners = @import("request_ownership.zig");
const leases = @import("preparation_leases.zig");
const Status = @import("control_protocol.zig").Status;
pub const request_size = 1104;
pub const response_size = 88;
pub const Operation = enum(u8) { reserve = 1, withdraw = 2 };
pub const Request = struct {
    operation: Operation,
    instance: [16]u8,
    correlation: owners.CorrelationID,
    root: u64,
    lifetime: u32,
    model: []const u8,
};
pub fn decode(data: *const [request_size]u8) !Request {
    if (!std.mem.eql(u8, data[0..4], "FIP9") or data[4] != 1 or
        !std.mem.allEqual(u8, data[6..8], 0) or !std.mem.allEqual(u8, data[66..68], 0) or
        !std.mem.allEqual(u8, data[72..80], 0)) return error.InvalidPreparationFrame;
    const operation = std.enums.fromInt(Operation, data[5]) orelse return error.InvalidPreparationFrame;
    const length = std.mem.readInt(u16, data[64..66], .big);
    if (length == 0 or length > owners.model_limit or
        !std.mem.allEqual(u8, data[80 + length ..], 0)) return error.InvalidPreparationFrame;
    const model = data[80 .. 80 + length];
    if (!std.unicode.utf8ValidateSlice(model) or std.mem.indexOfScalar(u8, model, 0) != null or
        std.mem.allEqual(u8, data[8..24], 0) or std.mem.allEqual(u8, data[24..56], 0)) return error.InvalidPreparationFrame;
    const root = std.mem.readInt(u64, data[56..64], .big);
    const lifetime = std.mem.readInt(u32, data[68..72], .big);
    if (operation == .reserve and (root != 0 or lifetime == 0 or lifetime > 5000)) return error.InvalidPreparationFrame;
    if (operation == .withdraw and (root == 0 or lifetime != 0)) return error.InvalidPreparationFrame;
    return .{ .operation = operation, .instance = data[8..24].*, .correlation = data[24..56].*, .root = root, .lifetime = lifetime, .model = model };
}
pub const Source = struct {
    context: *anyopaque,
    reserve: *const fn (*anyopaque, []const u8, owners.CorrelationID, u32) anyerror!leases.Handle,
    withdraw: *const fn (*anyopaque, leases.Handle, []const u8) anyerror!void,
};
// Status values deliberately match existing private control status semantics:
// ok0, invalid1, maintenance2, wrong_instance3. An acknowledgement is not a
// positive native completion/non-dispatch receipt or capacity/coverage grant.
pub fn dispatch(tracker: *owners.Tracker, io: std.Io, data: *const [request_size]u8, source: ?Source) [response_size]u8 {
    var response: [response_size]u8 = @splat(0);
    @memcpy(response[0..4], "FIV9");response[4] = 1;response[5] = @intFromEnum(Status.invalid);
    const request = decode(data) catch return response;
    response[6] = @intFromEnum(request.operation);
    _ = tracker.backendKnownUncertain(io);
    const before = tracker.snapshot(io);
    if (!before.initialized or !std.mem.eql(u8, &before.instance, &request.instance)) {response[5] = @intFromEnum(Status.wrong_instance);return response;}
    const provider = source orelse {response[5] = @intFromEnum(Status.maintenance);return response;};
    var root = request.root;
    if (request.operation == .reserve) {
        const handle = provider.reserve(provider.context, request.model, request.correlation, request.lifetime) catch {response[5] = @intFromEnum(Status.maintenance);return response;};
        if (handle.root == 0 or !std.mem.eql(u8, &handle.instance, &request.instance) or !std.mem.eql(u8, &handle.correlation, &request.correlation)) return response;
        root = handle.root;
    } else {
        provider.withdraw(provider.context, .{.instance=request.instance,.correlation=request.correlation,.root=request.root}, request.model) catch {response[5] = @intFromEnum(Status.maintenance);return response;};
    }
    const after = tracker.snapshot(io);
    if (!after.initialized or !std.mem.eql(u8, &after.instance, &request.instance) or after.sample_sequence <= before.sample_sequence or after.sample_sequence > owners.maximum_sample_sequence) return response;
    const stamp = std.Io.Clock.real.now(io).toMilliseconds();
    response[5] = @intFromEnum(Status.ok);
    @memcpy(response[8..24], &after.instance);
    std.mem.writeInt(u64, response[24..32], after.sample_sequence, .big);
    std.mem.writeInt(u64, response[32..40], if (stamp > 0 and stamp <= owners.maximum_sample_sequence) @intCast(stamp) else std.math.maxInt(u64), .big);
    std.mem.writeInt(u64, response[40..48], root, .big);
    @memcpy(response[48..80], &request.correlation);
    std.mem.writeInt(u32, response[80..84], request.lifetime, .big);
    return response;
}
