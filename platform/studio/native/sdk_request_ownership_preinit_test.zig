// Separate executable: SDK initialization and failure are process-lifetime.
const std = @import("std");
const ownership = @import("request_ownership.zig");
const sdk = @import("sdk_request_ownership.zig");

test "an SDK gap before initialization fences the tracker at enrollment" {
    const io = std.testing.io;
    sdk.fios_native_request_owners_uncertain();
    try std.testing.expect(sdk.diagnostic().uncertain);
    try ownership.shared.initialize(io, @splat(7));
    try std.testing.expect(!ownership.shared.knownUncertain(io));
    try std.testing.expectError(error.Unavailable, sdk.initialize(io));
    try std.testing.expect(ownership.shared.knownUncertain(io));
    try std.testing.expect(sdk.fios_native_request_owners_capture() == null);
    try std.testing.expectEqual(@as(u32, 0), sdk.diagnostic().active_contexts);
}
