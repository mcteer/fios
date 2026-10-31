const std = @import("std");
const startup = @import("startup_guard.zig");
extern "c" fn alarm(seconds: c_uint) c_uint;

pub fn main(init: std.process.Init) !void {
    _ = init;
    _ = alarm(30);
    var guard = try startup.Guard.start("26.10.3-fios-source-fixture");
    if (guard) |*held| {
        defer held.close();
        _ = std.c.write(std.c.STDOUT_FILENO, "READY\n", 6);
        var byte: u8 = 0;
        _ = std.c.read(std.c.STDIN_FILENO, @ptrCast(&byte), 1);
    } else {
        _ = std.c.write(std.c.STDOUT_FILENO, "DISABLED\n", 9);
    }
}
