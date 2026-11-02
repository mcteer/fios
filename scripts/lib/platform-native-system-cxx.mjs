// Private macOS source-build composition only; no installed/runtime authority.
import assert from 'node:assert/strict';
import path from 'node:path';
export function bindNativeSystemCxx(graph,sdk) {
 assert(typeof graph==='string'&&graph.includes('b.createModule(')&&!graph.includes('fiosSystemCxxModule'));
 assert(path.isAbsolute(sdk)&&!sdk.includes('\0')&&path.normalize(sdk)===sdk);
 const headers=JSON.stringify(path.join(sdk,'usr/include/c++/v1'));
 const runtime=JSON.stringify(path.join(sdk,'usr/lib/libc++.1.tbd'));
 const result=graph.replaceAll('b.createModule(', 'fiosSystemCxxModule(b, ')
  .replaceAll('break :blk b.fmt("{s}/System/Library/Frameworks", .{sdk});','break :blk "/System/Library/Frameworks";')
  .replaceAll('test_mod.linkSystemLibrary("c++", .{});','// System C++ is supplied by fiosSystemCxxModule.');
 return result+`\n// Use one Apple C++ ABI with the genuine source SDK, including exceptions.\nfn fiosSystemCxxModule(b: *std.Build, original: std.Build.Module.CreateOptions) *std.Build.Module {\n    var options = original;\n    const macos = if (options.target) |target| target.result.os.tag == .macos else false;\n    const system_cxx = macos and (options.link_libcpp orelse false);\n    if (system_cxx) options.link_libcpp = false;\n    const module = b.createModule(options);\n    if (macos) module.addIncludePath(.{ .cwd_relative = ${headers} });\n    if (system_cxx) {\n        module.addObjectFile(.{ .cwd_relative = ${runtime} });\n    }\n    return module;\n}\n`;
}
