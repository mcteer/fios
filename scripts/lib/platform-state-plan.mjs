import {lstatSync,realpathSync,readFileSync,mkdirSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {isAbsolute,normalize,dirname,basename,join,resolve} from 'node:path';

const fail=()=>{throw Error('Invalid offline state review');};
function absolute(path){
  if(typeof path!=='string'||!isAbsolute(path)||normalize(path)!==path||path.includes('\0')||Buffer.byteLength(path)>4096)fail();
  return path;
}
function privateDirectory(path){
  absolute(path);
  const info=lstatSync(path);
  if(!info.isDirectory()||info.uid!==process.geteuid()||(info.mode&0o7777)!==0o700)fail();
  return realpathSync.native(path);
}
function newPrivateDestination(path){
  absolute(path);
  try{lstatSync(path);fail();}catch(error){if(error.code!=='ENOENT')throw error;}
  const parent=privateDirectory(dirname(path)),name=basename(path);
  if(!name||name==='.'||name==='..'||Buffer.byteLength(name)>255)fail();
  return join(parent,name);
}

// Proposal data only: NEVER spawn the reviewed CLI, open SQLite, stop a
// writer, copy/restore files, resolve credentials or issue privileged argv.
// Actual studioctl execution independently checks the stopped writer fence,
// FIS9/schema, origin, receipt, links and no-replace destination semantics.
export function platformStatePlan({operation,release,verified,host,source,destination,backupSHA256}){
  if(!['backup','restore'].includes(operation)||!verified.manifest.native_inventory.hosts.includes(host))fail();
  const from=privateDirectory(source),to=newPrivateDestination(destination);
  if(from===to||to.startsWith(from+'/')||from.startsWith(to+'/'))fail();
  if(operation==='restore'&&!/^[a-f0-9]{64}$/.test(backupSHA256))fail();
  const program=join(resolve(release),'bin/studioctl');
  const artifact=verified.manifest.artifacts.find(item=>item.path==='bin/studioctl');
  if(!artifact)fail();
  const command=arguments_=>({program,arguments:arguments_,artifact_sha256:artifact.sha256,execution:'operator_only'});
  const commands=operation==='backup'
    ?[command(['--state',from,'backup-state','--to',to])]
    :[command(['--state',from,'verify-backup','--sha256',backupSHA256]),command(['--state',from,'restore-state','--sha256',backupSHA256,'--to',to])];
  return {version:1,operation:`stopped_state_${operation}_review`,host,manifest_sha256:verified.manifestSHA256,
    state:'operator_review_required',changes_made:false,activation:false,privileged_commands:[],proposed_commands:commands,
    unverified_at_review:operation==='backup'?['source_journal_identity','source_writer_stopped']:['backup_origin','backup_receipt','destination_writer_absent'],
    blockers:['explicit_operator_review_and_execution_required'],
    preserves:['native_inference_uncertainty','platform_exports','unrelated_runtime_objects','fios_database','legacy_volume'],
    limitations:['no_installation_or_service_authority','no_native_inference','no_schema_downgrade_or_overwrite','execute_on_the_originating_host_only']};
}

// A rollback always uses the retained OLD artifact against its own original
// stopped backup. Never downgrade/mutate the new journal or reuse live state.
// Legacy schema7 is accepted only by the explicitly named review operation;
// it cannot enter installation/current release validation or mint authority.
export function platformRollbackStatePlan({release,current,previousRelease,previous,host,backup,destination,backupSHA256}){
  if(resolve(release)===resolve(previousRelease)||current.manifestSHA256===previous.manifestSHA256||
     !current.manifest.native_inventory.hosts.includes(host)||!previous.manifest.native_inventory.hosts.includes(host))fail();
  const plan=platformStatePlan({operation:'restore',release:previousRelease,verified:previous,host,source:backup,destination,backupSHA256});
  return {...plan,operation:'stopped_state_rollback_review',
    current_manifest_sha256:current.manifestSHA256,previous_manifest_sha256:previous.manifestSHA256,
    previous_journal_schema:previous.manifest.journal_schema,
    blockers:['explicit_operator_review_and_execution_required','supervisor_and_manager_must_remain_stopped',
      'installed_artifact_configuration_and_credential_recovery_not_verified'],
    limitations:[...plan.limitations,'restore_original_previous_schema_backup_only','never_downgrade_the_new_journal',
      'no_installed_release_switch_or_uninstall','retain_new_state_and_both_reviewed_artifacts_for_diagnosis']};
}

// Operator workflow review only. Enrollment removal remains a separate step;
// this plan never deletes a release, state, exports or credential configuration.
export function platformUninstallPlan(options){
  const backup=platformStatePlan({...options,operation:'backup'});
  const command=backup.proposed_commands[0];
  return {...backup,operation:'platform_uninstall_review',state:'blocked',uninstall_executed:false,data_removal:false,
    proposed_commands:[{...command,arguments:['--state',command.arguments[1],'status']},command],
    steps:[
      {order:1,action:'review_current_platform_status',command_index:0},
      {order:2,action:'operator_stop_platform_supervisor_and_manager'},
      {order:3,action:'create_stopped_state_backup',command_index:1},
      {order:4,action:'review_installed_enrollment_removal',state:'not_implemented'},
      {order:5,action:'retain_state_exports_credentials_and_release_artifacts'}],
    blockers:['explicit_operator_review_and_execution_required','installed_enrollment_removal_not_implemented'],
    limitations:[...backup.limitations,'no_automatic_service_stop','no_enrollment_removal','no_data_deletion']};
}

function renderConfigurationTemplate(template,stateDirectory){
  absolute(stateDirectory);
  const defaults='/Users/mcteer/Library/Application Support/Fios/Studio';
  const escaped=stateDirectory.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;')
    .replaceAll('"','&quot;').replaceAll("'",'&apos;');
  if(!template.includes(`<string>${defaults}</string>`))fail();
  return template.replaceAll(`<string>${defaults}</string>`,`<string>${escaped}</string>`);
}

// Render reviewed configuration as proposal data. No files are written and no
// launchd/native service operation is executed by this review command.
export function platformConfigurationPlan({release,verified,host,state}){
  if(!verified.manifest.native_inventory.hosts.includes(host))fail();
  const stateDirectory=privateDirectory(state);
  const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
  const files=[['supervisor','/Library/LaunchDaemons'],['session','/Library/LaunchAgents']].map(([kind,directory])=>{
    const name=`lab.fios.studio.${kind}.plist`,path=`launchd/${name}`;
    const artifact=verified.manifest.artifacts.find(item=>item.path===path);
    if(!artifact)fail();
    const bytes=readFileSync(join(resolve(release),path));
    if(sha(bytes)!==artifact.sha256)fail();
    const content=renderConfigurationTemplate(bytes.toString('utf8'),stateDirectory);
    return {destination:join(directory,name),owner:'root:wheel',mode:0o644,
      source_artifact_sha256:artifact.sha256,content_sha256:sha(content),content};
  });
  return {version:1,operation:'platform_configuration_review',host,manifest_sha256:verified.manifestSHA256,
    service_user:'mcteer',state_directory:stateDirectory,installed_release:'/Library/Application Support/Fios/Studio',
    state:'blocked',changes_made:false,activation:false,privileged_commands:[],configuration_files:files,
    startup:{supervisor:'system_boot_as_service_user',session:'approved_user_aqua_session'},
    blockers:['release_and_native_enrollment_incomplete','installation_not_authorized'],
    rollback_steps:['stop_platform_supervisor_and_manager','retain_current_state_exports_and_configuration',
      'restore_previous_reviewed_configuration_and_artifacts','restore_previous_original_backup_to_fresh_state_directory',
      'verify_restored_status_without_inference'],
    limitations:['configuration_proposal_only','no_configuration_written','no_launchd_operation',
      'no_native_service_operation','no_credential_configuration','execute_on_the_selected_host_only']};
}

// Data-only preparation beside the operator's other private review artifacts.
// Installation destinations remain proposal fields, never write targets here.
export function stagePlatformConfiguration(options){
  const plan=platformConfigurationPlan(options),destination=newPrivateDestination(options.destination);
  mkdirSync(destination,{mode:0o700});
  // Keep any partial bundle for diagnosis; never replace or erase a prior one.
  const files=plan.configuration_files.map(file=>{
    const path=basename(file.destination);
    writeFileSync(join(destination,path),file.content,{mode:0o600,flag:'wx'});
    return {path,sha256:file.content_sha256,installation_destination:file.destination,
      installation_owner:file.owner,installation_mode:file.mode};
  });
  const review={...plan,preparation:'private_configuration_bundle',files};
  const bytes=Buffer.from(JSON.stringify(review,null,2)+'\n');
  writeFileSync(join(destination,'review.json'),bytes,{mode:0o600,flag:'wx'});
  return {version:1,operation:'stage_platform_configuration',host:plan.host,destination,
    manifest_sha256:plan.manifest_sha256,review_sha256:createHash('sha256').update(bytes).digest('hex'),
    files:files.length,installed:false,activation:false,state:'review_required'};
}

// Verify saved proposal bytes without opening state, a journal or destinations.
export function verifyPlatformConfiguration({release,verified,host,bundle,reviewSHA256}){
  if(!verified.manifest.native_inventory.hosts.includes(host)||!/^[a-f0-9]{64}$/.test(reviewSHA256))fail();
  const directory=privateDirectory(bundle),sha=bytes=>createHash('sha256').update(bytes).digest('hex');
  function read(name){
    const path=join(directory,name),info=lstatSync(path);
    if(!info.isFile()||info.isSymbolicLink()||info.uid!==process.geteuid()||info.nlink!==1||
       (info.mode&0o077)!==0||info.size<=0||info.size>65536)fail();
    const bytes=readFileSync(path);if(bytes.length!==info.size)fail();return bytes;
  }
  const bytes=read('review.json');if(sha(bytes)!==reviewSHA256)fail();
  const review=JSON.parse(bytes);
  if(review.preparation!=='private_configuration_bundle'||review.host!==host||review.manifest_sha256!==verified.manifestSHA256||
     review.activation!==false||!Array.isArray(review.files)||review.files.length!==2||
     !Array.isArray(review.configuration_files)||review.configuration_files.length!==2)fail();
  for(const [kind,parent] of [['supervisor','/Library/LaunchDaemons'],['session','/Library/LaunchAgents']]){
    const name=`lab.fios.studio.${kind}.plist`,destination=join(parent,name);
    const proposal=review.configuration_files.find(file=>file.destination===destination),file=review.files.find(file=>file.path===name);
    const artifact=verified.manifest.artifacts.find(item=>item.path===`launchd/${name}`);
    if(!proposal||!file||!artifact||proposal.source_artifact_sha256!==artifact.sha256)fail();
    const template=readFileSync(join(resolve(release),artifact.path));if(sha(template)!==artifact.sha256)fail();
    const expected=renderConfigurationTemplate(template.toString('utf8'),review.state_directory);
    const content=read(name);
    if(!content.equals(Buffer.from(expected))||proposal.content!==expected||proposal.content_sha256!==sha(content)||
       file.sha256!==sha(content)||proposal.owner!=='root:wheel'||proposal.mode!==0o644||
       file.installation_destination!==destination||file.installation_owner!=='root:wheel'||file.installation_mode!==0o644)fail();
  }
  return {version:1,operation:'verify_platform_configuration',scope:'declared_configuration_files',host,
    bundle:directory,manifest_sha256:verified.manifestSHA256,review_sha256:reviewSHA256,files:2,
    state:'review_required',installed:false,activation:false,changes_made:false};
}
