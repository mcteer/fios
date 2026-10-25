import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {successfulMainRun,github} from '../scripts/deploy.mjs';

test('SearXNG is a pinned nonroot Compose service, isolated from credentials and public ports',()=>{
 const source=readFileSync('compose.yaml','utf8');
 const search=source.split('\n  searxng:')[1].split('\n  deployer:')[0];
 for(const forbidden of ['ports:','docker.sock','fios-data','MLX_API_KEY','SESSION_SECRET','FIOS_PASSWORD'])assert.ok(!search.includes(forbidden));
 for(const required of ['user: "977:977"','read_only: true','cap_drop: [ALL]','networks: [search, search-egress]','driver: none','/healthz','mem_limit: 256m'])assert.ok(search.includes(required));
 assert.match(source,/search:\n    internal: true/);
 assert.match(readFileSync('Dockerfile.searxng','utf8'),/FROM docker.io\/searxng\/searxng@sha256:[a-f0-9]{64}/);
 assert.ok(readFileSync('scripts/check-web-search.mjs','utf8').includes("'--rm','--init'"),'live parser driver must not run Python as PID1');
});
test('latest exact-main push workflow is required, not an older success or PR/manual run',()=>{
  const sha='a'.repeat(40),good={head_sha:sha,head_branch:'main',event:'push',status:'completed',conclusion:'success'};
  assert.equal(successfulMainRun([good],sha),true);
  for(const changed of [{status:'in_progress'},{conclusion:'failure'},{conclusion:'cancelled'},{conclusion:'skipped'}])assert.equal(successfulMainRun([{...good,...changed},good],sha),false);
  for(const changed of [{head_sha:'b'.repeat(40)},{head_branch:'feature'},{event:'pull_request'},{event:'workflow_dispatch'}])assert.equal(successfulMainRun([{...good,...changed}],sha),false);
  assert.equal(successfulMainRun([],sha),false);
});
test('public GitHub discovery is bounded, nonredirecting and credential-free',async()=>{
  const result=await github('repos/mcteer/fios/commits/main',async(url,options)=>{
    assert.equal(url,'https://api.github.com/repos/mcteer/fios/commits/main');assert.equal(options.redirect,'error');assert.ok(!options.headers.Authorization);
    return new Response(JSON.stringify({sha:'a'.repeat(40)}));
  });assert.equal(result.sha,'a'.repeat(40));
  await assert.rejects(()=>github('test',async()=>new Response('private detail',{status:403})),/github_unavailable/);
  await assert.rejects(()=>github('test',async()=>new Response('not json')),/github_invalid_response/);
  await assert.rejects(()=>github('test',async()=>new Response('x'.repeat(3*1024*1024+1))),/github_response_limit/);
});
test('obsolete installer refuses to create native services on every platform',()=>{
  const r=spawnSync(process.execPath,['scripts/install-deployment.mjs','--install'],{encoding:'utf8'});assert.equal(r.status,1);assert.match(r.stderr,/disabled/);assert.ok(!readFileSync('scripts/install-deployment.mjs','utf8').includes('launchctl'));
});
test('support containers have no host checkout/config mounts or listener; only controller has management socket',()=>{
  const source=readFileSync('compose.yaml','utf8');
  const app=source.split('\n  fios:')[1].split('\n  readiness:')[0];
  const observer=source.split('\n  readiness:')[1].split('\n  deployer:')[0];
  const controller=source.split('\n  deployer:')[1].split('\nvolumes:')[0];
  assert.ok(!app.includes('docker.sock'));assert.ok(!observer.includes('docker.sock'));assert.ok(controller.includes('/var/run/docker.sock:/var/run/docker.sock'));
  for(const section of [observer,controller]){assert.ok(!section.includes('ports:'));assert.ok(section.includes('read_only: true'));assert.ok(section.includes('cap_drop: [ALL]'));}
  assert.ok(app.includes('fios-readiness:/run/fios-readiness:ro'));
  assert.ok(!source.includes('FIOS_READINESS_DIR'));assert.ok(!controller.includes('GITHUB_TOKEN'));assert.ok(!controller.includes('.env:'));
  const deployer=readFileSync('Dockerfile.deployer','utf8');assert.match(deployer,/FROM node:24\.15\.0-alpine@sha256:[a-f0-9]{64}/);assert.match(deployer,/git=2\.52\.0-r0/);
});
