import {lstatSync,realpathSync} from 'node:fs';
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
