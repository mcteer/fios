// Process startup exclusion only. Never native terminality, backend readiness,
// all-client coverage or permission to launch an application.
const std = @import("std");
const c = std.c;
extern "c" fn acl_get_fd_np(fd: c_int, kind: c_int) ?*anyopaque;
extern "c" fn acl_free(value: *anyopaque) c_int;
extern "c" fn __error() *c_int;

pub const Guard = struct {
    fd: c_int,
    retain_until_exit: bool = false,
    pub fn start(version: []const u8) !?Guard {
        if (std.mem.endsWith(u8, version, "-fios-platform")) {
            if (!std.mem.eql(u8, version, "26.10.3-fios-platform") or c.getenv("FIOS_NATIVE_STARTUP") != null)
                return error.StartupGuardUnavailable;
            return try installed();
        }
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
        // Production ownership lasts until kernel process exit, including
        // after main returns/errors while runtime teardown is still pending.
        if (self.retain_until_exit) return;
        const fd = self.fd;
        self.fd = -1;
        if (fd >= 0) _ = c.close(fd);
        // Never unlink: another process may already hold this same inode.
    }
    // Fixed root-protected installed namespace, independent of HOME/argv.
    // Installer must serialize updates and never replace a held lock inode.
    // FSG9/version1/reserved-zero/UID is a strict12-byte non-secret record.
    fn installed() !Guard {
        if (c.getuid() == 0 or c.getuid() != c.geteuid()) return error.StartupGuardUnavailable;
        var parent = c.openat(c.AT.FDCWD, "/", .{ .DIRECTORY = true, .NOFOLLOW = true, .CLOEXEC = true });
        if (parent < 0) return error.StartupGuardUnavailable;
        defer _ = c.close(parent);
        if (!protectedDirectory(parent)) return error.StartupGuardUnavailable;
        for ([_][*:0]const u8{ "Library", "Application Support", "Fios", "Studio", "native" }) |component| {
            const next = c.openat(parent, component, .{ .DIRECTORY = true, .NOFOLLOW = true, .CLOEXEC = true });
            if (next < 0) return error.StartupGuardUnavailable;
            if (!protectedDirectory(next)) {
                _ = c.close(next);
                return error.StartupGuardUnavailable;
            }
            _ = c.close(parent);
            parent = next;
        }
        const fd = c.openat(parent, "startup.lock", .{ .ACCMODE = .RDONLY, .NOFOLLOW = true, .CLOEXEC = true, .NONBLOCK = true });
        if (fd < 0) return error.StartupGuardUnavailable;
        errdefer _ = c.close(fd);
        var before: c.Stat = undefined;
        if (c.fstat(fd, &before) != 0 or before.uid != 0 or (before.mode & c.S.IFMT) != c.S.IFREG or
            (before.mode & 0o7777 != 0o444 and before.mode & 0o7777 != 0o644) or
            before.nlink != 1 or before.size != 12 or !noACL(fd)) return error.StartupGuardUnavailable;
        var bytes: [13]u8 = undefined;
        var offset: usize = 0;
        while (offset < bytes.len) {
            const count = c.read(fd, bytes[offset..].ptr, bytes.len - offset);
            if (count < 0 and __error().* == @intFromEnum(c.E.INTR)) continue;
            if (count < 0) return error.StartupGuardUnavailable;
            if (count == 0) break;
            offset += @intCast(count);
        }
        if (offset != 12 or !std.mem.eql(u8, bytes[0..4], "FSG9") or bytes[4] != 1 or
            !std.mem.eql(u8, bytes[5..8], &.{ 0, 0, 0 }) or
            std.mem.readInt(u32, bytes[8..12], .big) != c.getuid()) return error.StartupGuardUnavailable;
        if (c.flock(fd, c.LOCK.EX | c.LOCK.NB) != 0) return error.StartupGuardUnavailable;
        var after: c.Stat = undefined;
        var named: c.Stat = undefined;
        if (c.fstat(fd, &after) != 0 or c.fstatat(parent, "startup.lock", &named, c.AT.SYMLINK_NOFOLLOW) != 0 or
            !same(before, after) or !same(after, named) or !noACL(fd)) return error.StartupGuardUnavailable;
        return .{ .fd = fd, .retain_until_exit = true };
    }
    fn same(a: c.Stat, b: c.Stat) bool {
        return a.dev == b.dev and a.ino == b.ino and a.uid == b.uid and a.gid == b.gid and
            a.mode == b.mode and a.nlink == b.nlink and a.size == b.size and
            a.mtimespec.sec == b.mtimespec.sec and a.mtimespec.nsec == b.mtimespec.nsec and
            a.ctimespec.sec == b.ctimespec.sec and a.ctimespec.nsec == b.ctimespec.nsec;
    }
    fn protectedDirectory(fd: c_int) bool {
        var info: c.Stat = undefined;
        return c.fstat(fd, &info) == 0 and info.uid == 0 and (info.mode & c.S.IFMT) == c.S.IFDIR and
            info.mode & 0o7022 == 0 and noACL(fd);
    }
    fn noACL(fd: c_int) bool {
        __error().* = 0;
        const acl = acl_get_fd_np(fd, 0x100);
        if (acl) |value| {
            _ = acl_free(value);
            return false;
        }
        return __error().* == @intFromEnum(c.E.NOENT);
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
