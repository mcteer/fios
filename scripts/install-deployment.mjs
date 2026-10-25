// Explicit macOS installation from clean, checked merged main. No remote runner/listener.
import {mkdirSync,writeFileSync,renameSync,existsSync} from 'node:fs';
import {homedir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execute,greenChecks,runLocked} from './deploy.mjs';

if(process.platform!=='darwin'||!process.argv.includes('--install')){
  console.error('Usage on the authorized macOS application host: node scripts/install-deployment.mjs --install');
  process.exitCode=1;
}else if(!process.argv.includes('--lock-held')){
  const state=join(homedir(),'Library','Application Support','Fios','deploy');
  const code=await runLocked(fileURLToPath(import.meta.url),process.argv.slice(2),state);
  if(code===75){console.error('Installation blocked by an active deployment.');process.exitCode=1;}else process.exitCode=code;
}else{
  try{
    const repo=fileURLToPath(new URL('../',import.meta.url));
    if(await execute('git',['status','--porcelain'],{cwd:repo}))throw new Error('dirty');
    const sha=await execute('git',['rev-parse','HEAD'],{cwd:repo});
    const main=await execute('gh',['api','repos/mcteer/fios/commits/main','--jq','.sha'],{cwd:repo});
    if(sha!==main)throw new Error('not_main');
    const checks=JSON.parse(await execute('gh',['api',`repos/mcteer/fios/commits/${sha}/check-runs?filter=latest&per_page=100`],{cwd:repo}));
    if(!greenChecks(checks.check_runs))throw new Error('not_green');
    const state=join(homedir(),'Library','Application Support','Fios','deploy');
    mkdirSync(join(state,'bin'),{recursive:true,mode:0o700});
    const program=join(state,'bin','deploy.mjs');
    const copy=async(source,destination)=>{
      const content=await execute('git',['show',`${sha}:${source}`],{cwd:repo});
      writeFileSync(destination+'.tmp',content+'\n',{mode:0o600});renameSync(destination+'.tmp',destination);
    };
    await copy('scripts/deploy.mjs',program);
    const observerRoot=join(state,'observer');
    mkdirSync(join(observerRoot,'scripts'),{recursive:true,mode:0o700});
    mkdirSync(join(observerRoot,'src','agent'),{recursive:true,mode:0o700});
    writeFileSync(join(observerRoot,'package.json'),'{"type":"module"}\n',{mode:0o600});
    await copy('scripts/observe-hosts.mjs',join(observerRoot,'scripts','observe-hosts.mjs'));
    await copy('src/agent/availability.js',join(observerRoot,'src','agent','availability.js'));
    const readiness=join(state,'readiness');
    mkdirSync(readiness,{recursive:true,mode:0o755});
    // Change only the observer bind path; never print or change existing credentials.
    const {readFileSync}=await import('node:fs');
    const envFile=join(repo,'.env');
    const original=readFileSync(envFile,'utf8');
    const line='FIOS_READINESS_DIR='+JSON.stringify(readiness);
    const updated=/^FIOS_READINESS_DIR=.*$/m.test(original)?original.replace(/^FIOS_READINESS_DIR=.*$/m,line):original+(original.endsWith('\n')?'':'\n')+line+'\n';
    writeFileSync(envFile+'.deploy-tmp',updated,{mode:0o600});renameSync(envFile+'.deploy-tmp',envFile);
    const agents=join(homedir(),'Library','LaunchAgents');mkdirSync(agents,{recursive:true,mode:0o700});
    const escape=s=>s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
    const node=existsSync('/opt/homebrew/bin/node')?'/opt/homebrew/bin/node':process.execPath;
    const domain='gui/'+process.getuid();
    async function install(label,argv,scheduling){
      const plist=join(agents,label+'.plist');
      const xml=`<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict><key>Label</key><string>${label}</string><key>ProgramArguments</key><array>${argv.map(v=>'<string>'+escape(v)+'</string>').join('')}</array><key>RunAtLoad</key><true/>${scheduling}<key>EnvironmentVariables</key><dict><key>HOME</key><string>${escape(homedir())}</string><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict><key>StandardOutPath</key><string>${escape(join(state,label+'.log'))}</string><key>StandardErrorPath</key><string>${escape(join(state,label+'-error.log'))}</string></dict></plist>\n`;
      writeFileSync(plist,xml,{mode:0o600});
      await execute('plutil',['-lint',plist]);
      await execute('launchctl',['bootout',domain,plist]).catch(()=>{});
      await execute('launchctl',['bootstrap',domain,plist]);
    }
    await install('lab.fios.readiness',[node,join(observerRoot,'scripts','observe-hosts.mjs'),'--repo',repo,'--output',readiness],'<key>KeepAlive</key><true/><key>ThrottleInterval</key><integer>10</integer>');
    await install('lab.fios.deploy',[node,program,'--repo',repo,'--state',state],'<key>StartInterval</key><integer>60</integer>');
    console.log('Installed native read-only readiness observer and outbound-only checked-main delivery agent. No listener or remote runner.');
  }catch{
    console.error('Installation blocked. Require clean checked main, private .env, idle deployment lock, local Docker/GitHub access and an active macOS login session. No credentials were printed.');
    process.exitCode=1;
  }
}
