import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,rmSync,symlinkSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import {readSandboxBaseReview,validateSandboxImage,validateSandboxBase} from '../scripts/lib/platform-sandbox-image.mjs';
const review={version:1,purpose:'sandbox_base_build_review',base_image:'sha256:'+'a'.repeat(64),docker_cli_sha256:'b'.repeat(64),python_version:'3.11.17',platform:'linux/arm64',provenance_sha256:'c'.repeat(64),dockerfile_sha256:'e'.repeat(64),runner_sha256:'f'.repeat(64)};
test('sandbox producer review binds external digest, immutable local base and exact inputs',()=>{
 const directory=mkdtempSync(join(tmpdir(),'fios-image-review-'));
 try{
  const file=join(directory,'review.json');
  const save=value=>{const bytes=Buffer.from(JSON.stringify(value,null,2)+'\n');writeFileSync(file,bytes,{mode:0o600});return createHash('sha256').update(bytes).digest('hex');};
  let hash=save(review);assert.equal(readSandboxBaseReview(file,hash).base_image,review.base_image);
  assert.throws(()=>readSandboxBaseReview(file,'0'.repeat(64)));
  for(const patch of [{base_image:'fios:current'},{platform:'linux/amd64'},{python_version:'3.11.18'},{socket:'unix:///unreviewed'},{purpose:'approved_native_admission'}]){
   hash=save({...review,...patch});assert.throws(()=>readSandboxBaseReview(file,hash));
  }
  hash=save(review);const linked=join(directory,'link.json');symlinkSync(file,linked);assert.throws(()=>readSandboxBaseReview(linked,hash));
  writeFileSync(file,JSON.stringify(review));assert.throws(()=>readSandboxBaseReview(file,createHash('sha256').update(JSON.stringify(review)).digest('hex')));
 }finally{rmSync(directory,{recursive:true,force:true});}
});
test('runner image metadata cannot inherit app credentials, listeners, mounts or health actions',()=>{
 const value={Id:'sha256:'+'d'.repeat(64),Os:'linux',Architecture:'arm64',Config:{User:'65532:65532',WorkingDir:'/workspace',Entrypoint:['/opt/venv/bin/python','-I','-B','/runner.py'],Cmd:null,Env:['PATH=/opt/venv/bin:/usr/bin:/bin','LANG=C','LC_ALL=C','PYTHONDONTWRITEBYTECODE=1']}};
 assert.equal(validateSandboxImage(value,value.Id),value.Id);
 for(const patch of [{User:'root'},{Cmd:['node','server/index.js']},{ExposedPorts:{'3000/tcp':{}}},{Volumes:{'/data':{}}},{Healthcheck:{Test:['CMD','do-work']}},{Env:[...value.Config.Env,'MLX_API_KEY=never-pass']}])assert.throws(()=>validateSandboxImage({...value,Config:{...value.Config,...patch}},value.Id));
 assert.throws(()=>validateSandboxImage({...value,Architecture:'amd64'},value.Id));
});

test('reviewed base cannot execute inherited ONBUILD actions',()=>{
 const value={Id:review.base_image,Os:'linux',Architecture:'arm64',Config:{OnBuild:null}};
 assert.equal(validateSandboxBase(value,review.base_image),review.base_image);
 assert.throws(()=>validateSandboxBase({...value,Config:{OnBuild:['RUN unreviewed-work']}},review.base_image));
});
