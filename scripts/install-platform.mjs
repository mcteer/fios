#!/usr/bin/env node
// Read-only installation/state review. Never executes privileged/native commands.
import {validatePlatformRelease} from './lib/platform-release.mjs';
import {platformStatePlan} from './lib/platform-state-plan.mjs';
const args=process.argv.slice(2);
function failure(){console.error('Platform installation review refused; no changes made.');process.exitCode=1;}
try{
  const sizes={'plan':7,'plan-backup':11,'plan-restore':13};
  if(args.length!==sizes[args[0]]||args[1]!=='--release'||args[3]!=='--sha256'||args[5]!=='--host')throw Error('arguments');
  const verified=validatePlatformRelease(args[2],args[4]);
  if(!verified.manifest.native_inventory.hosts.includes(args[6]))throw Error('host');
  if(args[0]!=='plan'){
    const backup=args[0]==='plan-backup';
    if(backup?(args[7]!=='--state'||args[9]!=='--to'):(args[7]!=='--backup'||args[9]!=='--backup-sha256'||args[11]!=='--to'))throw Error('arguments');
    const plan=platformStatePlan({operation:backup?'backup':'restore',release:args[2],verified,host:args[6],source:args[8],
      destination:args[backup?10:12],backupSHA256:backup?undefined:args[10]});
    console.log(JSON.stringify(plan,null,2));
  }else{
    const manifest=verified.manifest;
    const blockers=[];
    if(!manifest.package_complete)blockers.push('incomplete_release_tree');
    if(!manifest.python.immutable_tree_enrolled)blockers.push('interpreter_not_enrolled');
    if(!manifest.native_inventory.enrolled)blockers.push('native_profile_not_enrolled');
    if(manifest.native_inventory.all_client_coverage!=='complete')blockers.push('authoritative_native_coverage_unproven');
    if(!manifest.activation.launchd_installation)blockers.push('installation_not_authorized');
    console.log(JSON.stringify({version:1,operation:'install_review',host:args[6],manifest_sha256:verified.manifestSHA256,
      state:blockers.length?'blocked':'review_required',blockers,privileged_commands:[],changes_made:false,
      preserves:['native_inference_uncertainty','platform_exports','unrelated_runtime_objects','fios_database','legacy_volume'],
      next_steps:['complete_reviewed_release_and_host_enrollment','obtain_separate_installation_approval','stop_supervisor_and_manager_before_backup','back_up_journal_and_exports_before_upgrade','execute_reviewed_privileged_commands_manually_one_host_at_a_time']},null,2));
  }
}catch{failure();}
