// Fixed original-root metadata for the explicit native handoff path. Neither
// a model selector nor authentication, native admission or completion proof.
const std = @import("std");
pub fn parse(headers: []const u8) !?u64 {
    var result: ?u64 = null;
    var lines = std.mem.splitSequence(u8, headers, "\r\n");
    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        if (!std.ascii.eqlIgnoreCase(line[0..colon], "x-fios-handoff-root")) continue;
        if (result != null) return error.DuplicateHandoffHeader;
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        if (value.len == 0 or value.len > 20 or value[0] == '0') return error.InvalidHandoffHeader;
        for (value) |byte| if (byte < '0' or byte > '9') return error.InvalidHandoffHeader;
        result = std.fmt.parseInt(u64, value, 10) catch return error.InvalidHandoffHeader;
    }
    return result;
}
test "handoff header preserves full-width root and refuses ambiguous values" {
    try std.testing.expectEqual(@as(?u64, null), try parse("Host: localhost\r\n"));
    try std.testing.expectEqual(@as(?u64, std.math.maxInt(u64)), try parse("X-Fios-Handoff-Root:18446744073709551615\r\n"));
    try std.testing.expectEqual(@as(?u64, 7), try parse("x-fios-handoff-root: \t7 \t\r\n"));
    for ([_][]const u8{ "", "0", "01", "+1", "-1", "1 2", "18446744073709551616", "1a" }) |bad| {
        var bytes: [128]u8 = undefined;
        try std.testing.expectError(error.InvalidHandoffHeader, parse(try std.fmt.bufPrint(&bytes, "X-Fios-Handoff-Root:{s}\r\n", .{bad})));
    }
    try std.testing.expectError(error.DuplicateHandoffHeader, parse("X-Fios-Handoff-Root:1\r\nx-fios-handoff-root:2\r\n"));
}
