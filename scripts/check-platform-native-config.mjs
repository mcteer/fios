#!/usr/bin/env node
// Ordinary CPU-only parsing of one reviewed Studio configuration. No weights,
// tensors, native server, model request or installed service is used.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync,readFileSync,writeFileSync,readdirSync,lstatSync,realpathSync,unlinkSync} from 'node:fs';
import {createHash,randomUUID} from 'node:crypto';
import {join,isAbsolute} from 'node:path';
const args=process.argv.slice(2);
assert([9,13].includes(args.length)&&args[0]==='--isolated'&&args[1]==='--source'&&args[3]==='--zig'&&args[5]==='--config'&&args[7]==='--sha256',
 'Usage: --isolated --source ABS_PRIVATE_SOURCE --zig ABS_ZIG --config ABS_CONFIG --sha256 REVIEWED_CONFIG_SHA256 [--index ABS_INDEX --index-sha256 REVIEWED_INDEX_SHA256]');
assert.equal(process.platform,'darwin');assert.notEqual(process.getuid(),0);
assert([args[2],args[4],args[6]].every(isAbsolute));
const source=realpathSync(args[2]),zig=realpathSync(args[4]),config=readFileSync(args[6]);
assert(source.startsWith('/private/tmp/'));assert.equal(lstatSync(source).uid,process.getuid());
assert(config.length>0&&config.length<=65536);
const hash=data=>createHash('sha256').update(data).digest('hex');
let index=null;
if(args.length===13){
 assert.equal(args[9],'--index');assert.equal(args[11],'--index-sha256');assert(isAbsolute(args[10]));
 index=readFileSync(args[10]);assert(index.length>0&&index.length<=16*1024*1024);
 assert.equal(args[12],'bc41d6bbdfd3c215d50d66ced0f2dfab12bcd52ec6e0da4d0fed93f453bf9964');
 assert.equal(hash(index),args[12]);
}
assert.equal(args[8],'3b75deecf2341a23fdd46e0eb36c9ff3c4f4f9d3ff89656c5c5cca142c0824a7');
assert.equal(hash(config),args[8]);
assert.equal(hash(readFileSync(zig)),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
assert.equal(hash(readFileSync(join(source,'src/model.zig'))),'7d0a1759ce907cd7c0294279ffa1d587a3dfbab606c61c12da0baa11ef86c6e4');
const directory=mkdtempSync('/private/tmp/fios-009-native-config-');
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',DEVELOPER_DIR:'/Applications/Xcode.app/Contents/Developer',
 GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const git=spawnSync('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,'rev-parse','HEAD'],{env,encoding:'utf8',timeout:5000});
assert.equal(git.status,0);assert.equal(git.stdout.trim(),'046b647686419df06c6c7132fb1d15d76185c3e5');
function inputs(){
 const rows=[];
 function walk(relative){
  for(const name of readdirSync(join(source,relative)).sort()){
   const file=join(relative,name),entry=lstatSync(join(source,file));
   if(entry.isDirectory())walk(file);
   else if(name.endsWith('.zig')){assert(entry.isFile());rows.push([file,hash(readFileSync(join(source,file)))]);}
  }
 }
 walk('src');walk('lib/sushi/src');return rows;
}
const before=inputs(),tag=randomUUID(),helper=join(source,'src',`fios-config-${tag}.zig`),data=join(source,'src',`fios-config-${tag}.json`);
// Normalized JSON from the separately observed 368-byte sidecar header.
// The numeric file extent is observed metadata, not an allocated weight map.
const tableHeader=readFileSync(new URL('../platform/studio/Tests/NativeFixtures/QwenLargeTableHeader.json.fixture',import.meta.url),'utf8');
assert.equal(hash(tableHeader),'8e31b3b0df6e198471c0e45994254922f1a509d4bb93ff02d5e903950586aa78');
const fixture=`const std = @import("std");
pub const mlx = @import("mlx.zig");
pub const log = @import("log.zig");
pub const io_util = @import("io_util.zig");
test "fios ordinary reviewed configuration" {
 var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
 defer arena.deinit();
 const value = try @import("model.zig").parseConfigFromJson(arena.allocator(), @embedFile("fios-config-${tag}.json"));
 try std.testing.expectEqualStrings("qwen4_exp",value.model_type);
 try std.testing.expectEqual(@as(u32,48),value.num_hidden_layers);
 try std.testing.expectEqual(@as(u32,2560),value.hidden_size);
 try std.testing.expectEqual(@as(u32,24),value.num_attention_heads);
 try std.testing.expectEqual(@as(u32,2),value.num_key_value_heads);
 try std.testing.expectEqual(@as(u32,256),value.head_dim);
 try std.testing.expectEqual(@as(u32,512),value.num_experts);
 try std.testing.expectEqual(@as(u32,10),value.num_experts_per_tok);
 try std.testing.expectEqual(@as(u32,8),value.quant_bits);
 try std.testing.expectEqual(@as(u32,64),value.quant_group_size);
 try std.testing.expectEqual(@as(u32,4),value.hc_count);
 try std.testing.expectEqual(@as(u32,320),value.hc_lowrank);
 try std.testing.expectEqual(@as(i32,1),value.ple_layer_idx);
 try std.testing.expectEqual(@as(u32,2560),value.ple_embed_dim);
 try std.testing.expectEqual(@as(u32,128),value.split_ngram_parts);
 try std.testing.expect(value.ssm_state_f32);
 try std.testing.expect(value.ngram_table_path == null);
 const table_spec = try @import("model.zig").qwen4EmbeddedSpec(&value);
 try std.testing.expectEqual(@as(u64,320001536),table_spec.rows);
 try std.testing.expectEqual(@as(u32,160),table_spec.dim);
 try std.testing.expectEqual(@as(u32,128),table_spec.shards);
 const table_header = try std.json.parseFromSliceLeaky(std.json.Value,arena.allocator(),${JSON.stringify(tableHeader)},.{});
 const metadata = table_header.object.get("__metadata__").?.object;
 try std.testing.expectEqualStrings("mlx-serve-ngram",metadata.get("format").?.string);
 const table_bits = try std.fmt.parseInt(u32,metadata.get("bits").?.string,10);
 const table_group = try std.fmt.parseInt(u32,metadata.get("group_size").?.string,10);
 try std.testing.expectEqual(@as(u32,8),table_bits);
 try std.testing.expectEqual(@as(u32,32),table_group);
 const region_parser = @import("qwen4_ple.zig");
 const weight = try region_parser.headerRegion(table_header.object,"weight","U32",4,57600276856,376,.matrix);
 const scales = try region_parser.headerRegion(table_header.object,"scales","BF16",2,57600276856,376,.matrix);
 const biases = try region_parser.headerRegion(table_header.object,"biases","BF16",2,57600276856,376,.matrix);
 try std.testing.expectEqual(table_spec.rows,weight.rows);
 try std.testing.expectEqual(weight.rows,scales.rows);
 try std.testing.expectEqual(weight.rows,biases.rows);
 try std.testing.expectEqual(@as(u64,table_spec.dim),weight.cols*32/table_bits);
 try std.testing.expectEqual(@as(u64,table_spec.dim),scales.cols*table_group);
 try std.testing.expectEqual(scales.cols,biases.cols);
 try std.testing.expectEqual(@as(u64,57600276856),biases.end+376);
 ${index ? `const embedded = try @import("qwen4_exp.zig").inspectEmbedded("${directory}", table_spec);
 try std.testing.expect(embedded == null);` : ''}
}
`;
writeFileSync(join(directory,'fixture.zig'),fixture,{mode:0o600});
writeFileSync(join(directory,'config.json'),config,{mode:0o600});
if(index)writeFileSync(join(directory,'model.safetensors.index.json'),index,{mode:0o600});
let helperWritten=false,dataWritten=false,result;
try{
 writeFileSync(helper,fixture,{flag:'wx',mode:0o600});helperWritten=true;
 writeFileSync(data,config,{flag:'wx',mode:0o600});dataWritten=true;
 result=spawnSync(zig,['test','-OReleaseSafe','-lc','--test-filter','fios ordinary reviewed configuration',
  '--cache-dir',join(directory,'cache'),'--dep','sushi_exl3',`-Mmlx_host=${helper}`,
  '--dep','mlx_host',`-Msushi_exl3=${join(source,'lib/sushi/src/exl3/root.zig')}`],
  {cwd:source,env,encoding:'utf8',timeout:180000,maxBuffer:2<<20});
 writeFileSync(join(directory,'compile-run.log'),(result.stdout??'')+(result.stderr??''),{mode:0o600});
}finally{
 if(dataWritten)unlinkSync(data);if(helperWritten)unlinkSync(helper);
 assert.deepEqual(inputs(),before,'Declared source inputs changed during the parser check');
}
assert.equal(result.status,0,`Actual configuration parser failed; retain ${directory}`);
assert.match((result.stdout??'')+(result.stderr??''),/All 1 tests passed\./);
const receipt={ok:true,source_base:git.stdout.trim(),config_sha256:args[8],fixture_sha256:hash(fixture),
 source_scope:'declared_src_and_sushi_zig_inventory_not_whole_repository_or_native_provenance',source_inputs:before,
 tests:1,parser:'parseConfigFromJson',index_sha256:index?hash(index):null,embedded_inspector:index?'no_embedded_table':'not_run',
 derived_table_geometry:{rows:320001536,dimension:160,split_parts:128},
 normalized_table_header_sha256:hash(tableHeader),table_payload_validated:false,
 sidecar_quantization:{bits:8,group_size:32},
 sidecar_path_selected:false,weight_files_read:0,model_requests:0,
 installed_service_actions:0,model_fit_proven:false,native_authority:false,review_directory:directory};
writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});
console.log(JSON.stringify({...receipt,source_inputs:before.length}));
