// Isolated source-fixture ownership only. Not production singleton authority,
// native terminality, backend readiness, or permission to launch an application.
const std = @import("std");
const c = std.c;
extern "c" fn acl_get_fd_np(fd: c_int, kind: c_int) ?*anyopaque;
extern "c" fn acl_free(value: *anyopaque) c_int;
extern "c" fn __error() *c_int;

pub const Guard = struct {
    fd: c_int,
    pub fn start(version: []const u8) !?Guard {
        const flag = c.getenv("FIOS_NATIVE_STARTUP") orelse return null;
        if (!std.mem.eql(u8, std.mem.span(flag), "isolated-source-fixture") or
            !std.mem.endsWith(u8, version, "-fios-source-fixture") or
            c.getuid() == 0 or c.getuid() != c.geteuid()) return error.StartupGuardUnavailable;
        const home = c.getenv("HOME") orelse return error.StartupGuardUnavailable;
        if (home[0] != '/') return error.StartupGuardUnavailable;
        const home_fd = c.openat(c.AT.FDCWD, home, .{ .DIRECTORY = true, .NOFOLLOW = true, .CLOEXEC = true });
        if (home_fd < 0) return error.StartupGuardUnavailable;
        defer _ = c.close(home_fd);
        if (!private(home_fd, c.S.IFDIR, 0o700, false)) return error.StartupGuardUnavailable;
        _ = c.mkdirat(home_fd, ".fios-native-startup", @as(c.mode_t, 0o700));
        const directory = c.openat(home_fd, ".fios-native-startup", .{ .DIRECTORY = true, .NOFOLLOW = true, .CLOEXEC = true });
        if (directory < 0) return error.StartupGuardUnavailable;
        defer _ = c.close(directory);
        if (!private(directory, c.S.IFDIR, 0o700, false)) return error.StartupGuardUnavailable;
        const fd = c.openat(directory, "server.lock", .{ .ACCMODE = .RDWR, .CREAT = true, .NOFOLLOW = true, .CLOEXEC = true, .NONBLOCK = true }, @as(c.mode_t, 0o600));
        if (fd < 0) return error.StartupGuardUnavailable;
        errdefer _ = c.close(fd);
        if (!private(fd, c.S.IFREG, 0o600, true) or c.flock(fd, c.LOCK.EX | c.LOCK.NB) != 0)
            return error.StartupGuardUnavailable;
        return .{ .fd = fd };
    }
    pub fn close(self: *Guard) void {
        _ = c.close(self.fd);
        // Never unlink: another process may already hold this same inode.
    }
    fn private(fd: c_int, kind: c.mode_t, mode: c.mode_t, single: bool) bool {
        var info: c.Stat = undefined;
        if (c.fstat(fd, &info) != 0 or info.uid != c.getuid() or
            (info.mode & c.S.IFMT) != kind or (info.mode & 0o7777) != mode or
            (single and info.nlink != 1)) return false;
        __error().* = 0;
        const acl = acl_get_fd_np(fd, 0x100);
        if (acl) |value| {
            _ = acl_free(value);
            return false;
        }
        return __error().* == @intFromEnum(c.E.NOENT);
    }
};
