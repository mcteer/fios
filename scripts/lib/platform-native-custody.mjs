// Supplementary source wiring checks. These are not runtime custody or terminal proofs.
import assert from 'node:assert/strict';
export const custodyEdges = [
 ['native:src/model_registry.zig', /fn fiosMayDeinit\(self: \*LoadedModel\) bool \{[\s\S]*?if \(self\.transformer\) \|xfm\| \{\s*if \(!xfm\.fiosCanDeinit\(\)\)/],
 ['native:src/transformer.zig', /pub fn fiosCanDeinit\(self: \*Transformer\) bool \{\s*return if \(self\.mlx_stream_ext\) \|m\| mlx_stream_mod\.fiosCanClose\(m\) else true;/],
 ['native:src/transformer.zig', /pub fn deinit\(self: \*Transformer\) void \{\s*if \(!self\.fiosCanDeinit\(\)\) return;/],
 ['native:src/arch/mlx_stream.zig', /pub fn close\(m: \*Model\) void \{\s*if \(!fiosCanClose\(m\)\) return;/],
 ['native:src/arch/mlx_stream.zig', /@hasDecl\(Side\(k\)\.arch, "fiosCanDeinit"\)\) Side\(k\)\.arch\.fiosCanDeinit\(b\.module\)/],
 ['plugin:src/arch/mimo_v2/root.zig', /pub fn fiosCanDeinit\(m: \*Module\) bool \{\s*return m\.fiosCanDeinit\(\);/],
 ['plugin:src/arch/mimo_v2/module.zig', /pub fn fiosCanDeinit\(self: \*Module\) bool \{\s*return self\.source\.fiosCanDeinit\(\);/],
 ['plugin:src/arch/mimo_v2/module.zig', /pub fn deinit\(self: \*Module\) void \{\s*if \(!self\.fiosCanDeinit\(\)\) return;/],
 ['plugin:src/arch/mimo_v2/source.zig', /pub fn fiosCanDeinit\(self: \*Source\) bool \{\s*return if \(self\.warm\) \|w\| w\.fiosCanDestroy\(\) else true;/],
 ['plugin:src/arch/mimo_v2/source.zig', /pub fn deinit\(self: \*Source\) void \{\s*if \(!self\.fiosCanDeinit\(\)\) return;/],
];
export function verifyCustodyWiring(sources) {
 for (const [file, edge] of custodyEdges) assert.match(sources[file] ?? '', edge, `Missing known-custody preflight: ${file}`);
}
