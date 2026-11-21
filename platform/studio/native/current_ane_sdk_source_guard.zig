//! Negative-only private ANE seam fence. It never issues native completion.
const options = @import("build_options");
extern fn msv_ane_source_uncertainty() u32;
pub fn known() bool {
    if (!@hasDecl(options, "fios_source_ane")) return false;
    if (!options.fios_source_ane) return false;
    return msv_ane_source_uncertainty() != 0;
}
pub fn requireCertain() error{FiosAneSourceUncertain}!void {
    if (known()) return error.FiosAneSourceUncertain;
}
pub fn fallback(ctx: anytype, x: anytype) !@typeInfo(@TypeOf(ctx.full(x))).error_union.payload {
    return fallbackWith(known, ctx, x);
}
pub fn fallbackWith(comptime negative: fn () bool, ctx: anytype, x: anytype) !@typeInfo(@TypeOf(ctx.full(x))).error_union.payload {
    if (negative()) return error.FiosAneSourceUncertain;
    return ctx.full(x);
}

// Ordinary metadata callback spy: no model, ANE API or GPU operation.
const std = @import("std");
const FallbackSpy = struct {
    calls: *usize,
    pub fn full(self: @This(), x: usize) !usize {
        self.calls.* += 1;
        return x + 1;
    }
};
fn metadataBlocked() bool {
    return true;
}
fn metadataHealthy() bool {
    return false;
}
test "fios current ANE seam refuses fallback after independent uncertainty" {
    var calls: usize = 0;
    const result = fallbackWith(metadataBlocked, FallbackSpy{ .calls = &calls }, @as(usize, 3));
    if (result) |_| {
        std.debug.print("FIO_CURRENT_ANE_FALLBACK_AFTER_KNOWN_UNCERTAINTY\n", .{});
        try std.testing.expect(false);
    } else |err| try std.testing.expectEqual(error.FiosAneSourceUncertain, err);
    try std.testing.expectEqual(@as(usize, 0), calls);
}
test "fios current ANE seam preserves legacy healthy fallback callback" {
    var calls: usize = 0;
    const result = try fallbackWith(metadataHealthy, FallbackSpy{ .calls = &calls }, @as(usize, 3));
    try std.testing.expectEqual(@as(usize, 4), result);
    try std.testing.expectEqual(@as(usize, 1), calls);
}
