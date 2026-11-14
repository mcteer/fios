const std = @import("std");
const config = @import("config.zig");

// Build the existing renderer from declared CPP inputs. One archive is shared
// by the graph; this adds no model, runtime operation or native permission.
pub fn create(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, host: config.Host, sources: std.Build.LazyPath) *std.Build.Step.Compile {
    const frameworks = host.frameworks orelse @panic("Jinja source build needs an explicit Apple SDK");
    const suffix = "/System/Library/Frameworks";
    if (!std.mem.endsWith(u8, frameworks, suffix) or frameworks.len <= suffix.len)
        @panic("Jinja source SDK framework path is invalid");
    const sdk = frameworks[0 .. frameworks.len - suffix.len];
    if (!std.fs.path.isAbsolute(sdk)) @panic("Jinja source SDK must be absolute");
    const module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = false,
    });
    module.addIncludePath(sources);
    module.addIncludePath(.{ .cwd_relative = b.fmt("{s}/usr/include/c++/v1", .{sdk}) });
    for ([_][]const u8{ "jinja_wrapper.cpp", "caps.cpp", "lexer.cpp", "parser.cpp", "runtime.cpp", "jinja_string.cpp", "value.cpp" }) |name| {
        module.addCSourceFile(.{
            .file = sources.path(b, name),
            .flags = &.{ "-std=c++17", "-DNDEBUG", "-isysroot", sdk },
        });
    }
    return b.addLibrary(.{ .name = "fios-jinja-source", .linkage = .static, .root_module = module });
}
