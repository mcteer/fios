#!/usr/bin/env node
// Installation/state review and private data preparation; no service actions.
import {validatePlatformRelease} from './lib/platform-release.mjs';
import {platformStatePlan,platformRollbackStatePlan,platformUninstallPlan,platformConfigurationPlan,stagePlatformConfiguration,verifyPlatformConfiguration} from './lib/platform-state-plan.mjs';
const args=process.argv.slice(2);
const usage=`Usage: node scripts/install-platform.mjs COMMAND --release ABS_RELEASE --sha256 REVIEWED_SHA256 --host HOST [OPTIONS]

Commands:
  plan
  plan-config          --state ABS_STATE
  stage-config         --state ABS_STATE --to ABS_NEW_PRIVATE_BUNDLE
  verify-config        --bundle ABS_BUNDLE --bundle-sha256 REVIEWED_BUNDLE_SHA256
  plan-backup          --state ABS_STATE --to ABS_NEW_BACKUP
  plan-uninstall       --state ABS_STATE --to ABS_NEW_BACKUP
  plan-restore         --backup ABS_BACKUP --backup-sha256 REVIEWED_BACKUP_SHA256 --to ABS_NEW_STATE
  plan-rollback        --previous ABS_PREVIOUS_RELEASE --previous-sha256 REVIEWED_PREVIOUS_SHA256 --backup ABS_BACKUP --backup-sha256 REVIEWED_BACKUP_SHA256 --to ABS_NEW_STATE
  plan-rollback-seven  Same options as plan-rollback; reviews a previous schema7 release only.

HOST: fios-edge-a.lab or fios-edge-b.lab
Creates review proposals or a private configuration bundle. Executes no installation or service action.
`;
function failure(){console.error('Platform review/preparation failed; retain any private output for review.');process.exitCode=1;}
if(args.length===1&&['--help','-h'].includes(args[0])){
  console.log(usage);
}else{
try{
  const sizes={'plan':7,'plan-config':9,'stage-config':11,'verify-config':11,'plan-backup':11,'plan-uninstall':11,'plan-restore':13,'plan-rollback':17,'plan-rollback-seven':17};
  if(args.length!==sizes[args[0]]||args[1]!=='--release'||args[3]!=='--sha256'||args[5]!=='--host')throw Error('arguments');
  const verified=validatePlatformRelease(args[2],args[4]);
  if(!verified.manifest.native_inventory.hosts.includes(args[6]))throw Error('host');
  if(args[0]==='verify-config'){
    if(args[7]!=='--bundle'||args[9]!=='--bundle-sha256')throw Error('arguments');
    console.log(JSON.stringify(verifyPlatformConfiguration({release:args[2],verified,host:args[6],bundle:args[8],reviewSHA256:args[10]}),null,2));
  }else if(args[0]==='stage-config'){
    if(args[7]!=='--state'||args[9]!=='--to')throw Error('arguments');
    console.log(JSON.stringify(stagePlatformConfiguration({release:args[2],verified,host:args[6],state:args[8],destination:args[10]}),null,2));
  }else if(args[0]==='plan-config'){
    if(args[7]!=='--state')throw Error('arguments');
    console.log(JSON.stringify(platformConfigurationPlan({release:args[2],verified,host:args[6],state:args[8]}),null,2));
  }else if(['plan-rollback','plan-rollback-seven'].includes(args[0])){
    if(args[7]!=='--previous'||args[9]!=='--previous-sha256'||args[11]!=='--backup'||args[13]!=='--backup-sha256'||args[15]!=='--to')throw Error('arguments');
    const previous=validatePlatformRelease(args[8],args[10],{journalSchema:args[0]==='plan-rollback-seven'?7:8});
    console.log(JSON.stringify(platformRollbackStatePlan({release:args[2],current:verified,previousRelease:args[8],previous,
      host:args[6],backup:args[12],backupSHA256:args[14],destination:args[16]}),null,2));
  }else if(args[0]!=='plan'){
    const backup=['plan-backup','plan-uninstall'].includes(args[0]);
    if(backup?(args[7]!=='--state'||args[9]!=='--to'):(args[7]!=='--backup'||args[9]!=='--backup-sha256'||args[11]!=='--to'))throw Error('arguments');
    const makePlan=args[0]==='plan-uninstall'?platformUninstallPlan:platformStatePlan;
    const plan=makePlan({operation:backup?'backup':'restore',release:args[2],verified,host:args[6],source:args[8],
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
}
