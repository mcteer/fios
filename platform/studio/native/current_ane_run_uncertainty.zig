//! Process-wide negative evidence from a reported ANE run outcome only.
//! Success, local cleanup and a new source epoch cannot reset this latch.
//! No device call, callback, allocation or positive terminal/admission claim.
const std = @import("std");
const shared_util = @import("../sdk/util/shared.zig");
const storage = shared_util.Shared(std.atomic.Value(bool), "fios_ane_reported_run_uncertainty", .init(false));
pub fn known() bool { return storage.get().load(.acquire); }
pub fn observeOutcome(success: bool) void {
    if (!success) storage.get().store(true, .release);
}
