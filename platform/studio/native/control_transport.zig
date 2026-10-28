// Source-fixture-only private operator transport. Disabled in ordinary builds.
// UID-authenticated AF_UNIX, one finite frame per connection, no subprocesses.
// No model-facing management route, lifecycle signal or quiescence authority.
const std = @import("std");
const ownership = @import("request_ownership.zig");
const protocol = @import("control_protocol.zig");
pub const OwnerBarrier = protocol.OwnerBarrier;
const c = std.c;
extern "c" fn getpeereid(fd: c_int, uid: *c.uid_t, gid: *c.gid_t) c_int;

pub const Bridge = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    fd: c_int,
    barrier: ?OwnerBarrier,
    path: [256:0]u8,
    identity: c.Stat,
    stopped: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,

    pub fn start(io: std.Io, allocator: std.mem.Allocator, version: []const u8, barrier: ?OwnerBarrier) !?*Bridge {
        const enabled = c.getenv("FIOS_NATIVE_CONTROL");
        if (enabled == null) return null;
        if (!std.mem.eql(u8, std.mem.span(enabled.?), "isolated-source-fixture") or
            !std.mem.endsWith(u8, version, "-fios-source-fixture") or c.getuid() == 0 or c.geteuid() != c.getuid())
            return error.ControlUnavailable;
        const home = c.getenv("HOME");
        if (home == null) return error.ControlUnavailable;
        var directory_buffer: [256]u8 = undefined;
        const directory = try std.fmt.bufPrintSentinel(&directory_buffer, "{s}/.fios-native-control", .{std.mem.span(home.?)}, 0);
        _ = c.mkdir(directory.ptr, 0o700);
        var info: c.Stat = undefined;
        if (c.fstatat(c.AT.FDCWD, directory.ptr, &info, c.AT.SYMLINK_NOFOLLOW) != 0 or info.uid != c.getuid() or
            (info.mode & c.S.IFMT) != c.S.IFDIR or (info.mode & 0o777) != 0o700)
            return error.ControlUnavailable;
        var path_buffer: [256:0]u8 = @splat(0);
        const path = try std.fmt.bufPrintSentinel(&path_buffer, "{s}/control.sock", .{directory}, 0);
        // Never unlink/adopt an existing socket, including stale ones.
        if (c.fstatat(c.AT.FDCWD, path.ptr, &info, c.AT.SYMLINK_NOFOLLOW) == 0) return error.ControlUnavailable;
        var address: c.sockaddr.un = std.mem.zeroes(c.sockaddr.un);
        if (path.len >= address.path.len) return error.ControlUnavailable;
        address.family = c.AF.UNIX;
        address.len = @sizeOf(c.sockaddr.un);
        @memcpy(address.path[0..path.len], path);
        const fd = c.socket(c.AF.UNIX, c.SOCK.STREAM, 0);
        if (fd < 0) return error.ControlUnavailable;
        errdefer _ = c.close(fd);
        if (!secureFD(fd) or c.bind(fd, @ptrCast(&address), @sizeOf(c.sockaddr.un)) != 0)
            return error.ControlUnavailable;
        if (c.chmod(path.ptr, 0o600) != 0 or c.fstatat(c.AT.FDCWD, path.ptr, &info, c.AT.SYMLINK_NOFOLLOW) != 0 or
            info.uid != c.getuid() or (info.mode & c.S.IFMT) != c.S.IFSOCK or
            (info.mode & 0o777) != 0o600 or c.listen(fd, 2) != 0)
            return error.ControlUnavailable;
        const self = try allocator.create(Bridge);
        errdefer allocator.destroy(self);
        self.* = .{ .io = io, .allocator = allocator, .fd = fd, .barrier = barrier, .path = path_buffer, .identity = info };
        self.thread = try std.Thread.spawn(.{}, run, .{self});
        return self;
    }
    pub fn stop(self: *Bridge) void {
        self.stopped.store(true, .release);
        if (self.thread) |thread| thread.join();
        _ = c.close(self.fd);
        // Delete only the exact pathname identity created by this instance.
        var info: c.Stat = undefined;
        if (c.fstatat(c.AT.FDCWD, &self.path, &info, c.AT.SYMLINK_NOFOLLOW) == 0 and info.dev == self.identity.dev and
            info.ino == self.identity.ino and info.uid == self.identity.uid and
            (info.mode & c.S.IFMT) == c.S.IFSOCK) _ = c.unlink(&self.path);
        self.allocator.destroy(self);
    }
    fn secureFD(fd: c_int) bool {
        const flags = c.fcntl(fd, c.F.GETFL);
        const nonblock: c_int = @intCast(@as(u32, @bitCast(c.O{ .NONBLOCK = true })));
        return flags >= 0 and c.fcntl(fd, c.F.SETFL, @as(c_int, flags | nonblock)) == 0 and
            c.fcntl(fd, c.F.SETFD, @as(c_int, c.FD_CLOEXEC)) == 0;
    }
    fn nowMs() ?u64 {
        var value: c.timespec = undefined;
        if (c.clock_gettime(.MONOTONIC, &value) != 0 or value.sec < 0 or value.nsec < 0) return null;
        const seconds = std.math.mul(u64, @intCast(value.sec), 1000) catch return null;
        return std.math.add(u64, seconds, @as(u64, @intCast(value.nsec)) / 1_000_000) catch null;
    }
    fn ready(self: *Bridge, fd: c_int, events: c_short, deadline: u64) bool {
        while (!self.stopped.load(.acquire)) {
            if ((nowMs() orelse return false) >= deadline) return false;
            var poll: c.pollfd = .{ .fd = fd, .events = events, .revents = 0 };
            if (c.poll(@ptrCast(&poll), 1, 100) > 0) return (poll.revents & (events | c.POLL.HUP)) != 0;
        }
        return false;
    }
    fn run(self: *Bridge) void {
        while (!self.stopped.load(.acquire)) {
            const deadline = std.math.add(u64, nowMs() orelse break, 1000) catch break;
            if (!self.ready(self.fd, c.POLL.IN, deadline)) continue;
            const peer = c.accept(self.fd, null, null);
            if (peer < 0) continue;
            self.handle(peer);
            _ = c.close(peer);
        }
    }
    fn handle(self: *Bridge, peer: c_int) void {
        var uid: c.uid_t = 0;
        var gid: c.gid_t = 0;
        var no_sigpipe: c_int = 1;
        if (getpeereid(peer, &uid, &gid) != 0 or uid != c.getuid() or !secureFD(peer) or
            c.setsockopt(peer, c.SOL.SOCKET, c.SO.NOSIGPIPE, &no_sigpipe, @sizeOf(c_int)) != 0) return;
        const deadline = std.math.add(u64, nowMs() orelse return, 2000) catch return;
        // Require a write-half-close: extra/trailing/replayed frames never act.
        var input: [protocol.request_size + 1]u8 = undefined;
        var count: usize = 0;
        while (self.ready(peer, c.POLL.IN, deadline)) {
            const n = c.read(peer, input[count..].ptr, input.len - count);
            if (n < 0) return;
            if (n == 0) break;
            count += @intCast(n);
            if (count > protocol.request_size) return;
        } else return;
        if (count != protocol.request_size) return;
        const response = protocol.dispatchWithBarrier(&ownership.shared, self.io, input[0..protocol.request_size], self.barrier);
        var sent: usize = 0;
        while (sent < response.len and self.ready(peer, c.POLL.OUT, deadline)) {
            const n = c.write(peer, response[sent..].ptr, response.len - sent);
            if (n <= 0) return;
            sent += @intCast(n);
        }
    }
};
