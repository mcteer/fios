#!/usr/bin/env node
// Installation/state review and private data preparation; no service actions.
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {validatePlatformRelease} from './lib/platform-release.mjs';
import {platformStatePlan,platformRollbackStatePlan,platformUninstallPlan,platformConfigurationPlan,stagePlatformConfiguration,verifyPlatformConfiguration,proposePlatformConfigurationInstall,proposePlatformConfigurationRemoval} from './lib/platform-state-plan.mjs';
const args=process.argv.slice(2);
const usage=`Usage: node scripts/install-platform.mjs COMMAND --release ABS_RELEASE --sha256 REVIEWED_SHA256 --host HOST [OPTIONS]

Commands:
  plan
  plan-composition     --candidate ABS_COMPOSITION --sha256 REVIEWED_COMPOSITION_SHA --host HOST
  propose-first-install --candidate ABS_COMPOSITION --sha256 REVIEWED_COMPOSITION_SHA --host HOST
  propose-artifact-uninstall --candidate ABS_COMPOSITION --sha256 REVIEWED_COMPOSITION_SHA --host HOST
  propose-python-enrollment --candidate ABS_COMPOSITION --sha256 REVIEWED_COMPOSITION_SHA --host HOST --uid SERVICE_UID --state ABS_STATE --review-sha256 REVIEW_IDENTITY
  stage-python-enrollment --candidate ABS_COMPOSITION --sha256 REVIEWED_COMPOSITION_SHA --host HOST --uid SERVICE_UID --state ABS_STATE --review-sha256 REVIEW_IDENTITY --to ABS_NEW_PRIVATE_BUNDLE
  propose-python-policy-install --candidate ABS_COMPOSITION --sha256 REVIEWED_COMPOSITION_SHA --host HOST --bundle ABS_PRIVATE_BUNDLE --bundle-sha256 REVIEWED_STAGE_RECEIPT_SHA
  propose-python-policy-removal --candidate ABS_COMPOSITION --sha256 REVIEWED_COMPOSITION_SHA --host HOST --bundle ABS_PRIVATE_BUNDLE --bundle-sha256 REVIEWED_STAGE_RECEIPT_SHA
  plan-config          --state ABS_STATE
  stage-config         --state ABS_STATE --to ABS_NEW_PRIVATE_BUNDLE
  propose-config-removal --bundle ABS_BUNDLE --bundle-sha256 REVIEWED_BUNDLE_SHA256
  propose-config-install --bundle ABS_BUNDLE --bundle-sha256 REVIEWED_BUNDLE_SHA256
  verify-config        --bundle ABS_BUNDLE --bundle-sha256 REVIEWED_BUNDLE_SHA256
  plan-backup          --state ABS_STATE --to ABS_NEW_BACKUP
  plan-backup-config   --state ABS_STATE --configuration ABS_CONFIGURATION --to ABS_NEW_BACKUP
  plan-uninstall       --state ABS_STATE --to ABS_NEW_BACKUP
  plan-uninstall-config --state ABS_STATE --configuration ABS_CONFIGURATION --to ABS_NEW_BACKUP
  plan-restore         --backup ABS_BACKUP --backup-sha256 REVIEWED_BACKUP_SHA256 --to ABS_NEW_STATE
  plan-rollback        --previous ABS_PREVIOUS_RELEASE --previous-sha256 REVIEWED_PREVIOUS_SHA256 --backup ABS_BACKUP --backup-sha256 REVIEWED_BACKUP_SHA256 --to ABS_NEW_STATE
  plan-rollback-seven  Same options as plan-rollback; reviews a previous schema7 release only.
  plan-rollback-eight  Same options as plan-rollback; reviews a previous schema8 release only.

HOST: fios-edge-a.lab or fios-edge-b.lab
Reviews, stages or verifies private configuration/state data. Executes no installation or service action.
`;
function failure(){console.error('Platform review/preparation failed; retain any private output for review.');process.exitCode=1;}
if(args.length===1&&['--help','-h'].includes(args[0])){
  console.log(usage);
}else if(['plan-composition','propose-first-install','propose-artifact-uninstall','propose-python-enrollment','stage-python-enrollment','propose-python-policy-install','propose-python-policy-removal'].includes(args[0])){
  try{
    const policyRemoval=args[0]==='propose-python-policy-removal',policyInstall=policyRemoval||args[0]==='propose-python-policy-install';
    const stage=args[0]==='stage-python-enrollment',enrollment=stage||args[0]==='propose-python-enrollment';
    if(args.length!==(policyInstall?11:stage?15:enrollment?13:7)||args[1]!=='--candidate'||args[3]!=='--sha256'||args[5]!=='--host')throw Error('arguments');
    if(enrollment&&(args[7]!=='--uid'||args[9]!=='--state'||args[11]!=='--review-sha256'))throw Error('arguments');
    if(stage&&args[13]!=='--to')throw Error('arguments');
    if(policyInstall&&(args[7]!=='--bundle'||args[9]!=='--bundle-sha256'))throw Error('arguments');
    const python=fileURLToPath(new URL('../.venv/bin/python',import.meta.url));
    const checker=fileURLToPath(new URL('./check-platform-composition.py',import.meta.url));
    const proposal=args[0]!=='plan-composition',uninstall=args[0]==='propose-artifact-uninstall';
    const result=spawnSync(python,['-I','-B',checker,'--candidate',args[2],'--sha256',args[4],'--host',args[6],
      ...(policyInstall?[policyRemoval?'--python-policy-removal-proposal':'--python-policy-install-proposal','--bundle',args[8],'--bundle-sha256',args[10]]:enrollment?[stage?'--stage-python-enrollment':'--python-enrollment-proposal','--uid',args[8],'--state',args[10],'--review-sha256',args[12],...(stage?['--to',args[14]]:[])]:proposal?[uninstall?'--uninstall-proposal':'--first-install-proposal']:[])],
      {encoding:'utf8',timeout:250000,maxBuffer:proposal?8<<20:65536});
    if(result.error||result.status!==0||result.stderr)throw Error('composition');
    const plan=JSON.parse(result.stdout);
    if(stage){
      if(plan.operation!=='private_python_enrollment_stage'||plan.approved!==false||plan.installed_policy_written!==false||plan.installed!==false||plan.activation!==false||plan.native_authority!==false||plan.state_opened!==false||plan.private_files_written!==3||plan.source_rechecked!==true)throw Error('stage');
      console.log(JSON.stringify(plan,null,2));
    }else{
    const operation=policyInstall?(policyRemoval?'python_policy_removal_command_proposal':'python_policy_install_command_proposal'):enrollment?'python_enrollment_configuration_proposal':proposal?(uninstall?'uninstall_command_proposal':'first_install_command_proposal'):'composed_platform_install_review';
    if(plan.operation!==operation||plan.state!=='blocked'||plan.activation!==false||plan.installed!==false||plan.native_authority!==false||plan.privileged_commands.length!==0)throw Error('authority');
    if(proposal&&!enrollment&&!policyInstall&&(plan.commands_authorized!==false||plan.requires_operator_execution!==true||plan.enrollment_written!==false||plan.credentials_written!==false))throw Error('proposal');
    if((enrollment||policyInstall)&&(plan.commands_authorized!==false||plan.approved!==false||plan.policy_written!==false||plan.credentials_written!==false||plan.state_opened!==false))throw Error('enrollment');
    if(policyInstall&&(plan.staged_policy_rechecked!==true||plan.requires_operator_execution!==true||(policyRemoval?plan.proposed_file_removals:plan.proposed_file_commands).length!==1))throw Error('policy');
    if(policyRemoval&&(plan.policy_removed!==false||plan.state_and_exports_retained!==true||plan.credentials_retained!==true))throw Error('removal');
    console.log(JSON.stringify(plan,null,2));
    }
  }catch{failure();}
}else{
try{
  const sizes={'plan':7,'plan-config':9,'stage-config':11,'verify-config':11,'propose-config-install':11,'propose-config-removal':11,'plan-backup':11,'plan-backup-config':13,'plan-uninstall':11,'plan-uninstall-config':13,'plan-restore':13,'plan-rollback':17,'plan-rollback-seven':17,'plan-rollback-eight':17};
  if(args.length!==sizes[args[0]]||args[1]!=='--release'||args[3]!=='--sha256'||args[5]!=='--host')throw Error('arguments');
  const verified=validatePlatformRelease(args[2],args[4]);
  if(!verified.manifest.native_inventory.hosts.includes(args[6]))throw Error('host');
  if(['verify-config','propose-config-install','propose-config-removal'].includes(args[0])){
    if(args[7]!=='--bundle'||args[9]!=='--bundle-sha256')throw Error('arguments');
    const review=args[0]==='propose-config-removal'?proposePlatformConfigurationRemoval:args[0]==='propose-config-install'?proposePlatformConfigurationInstall:verifyPlatformConfiguration;
    console.log(JSON.stringify(review({release:args[2],verified,host:args[6],bundle:args[8],reviewSHA256:args[10]}),null,2));
  }else if(args[0]==='stage-config'){
    if(args[7]!=='--state'||args[9]!=='--to')throw Error('arguments');
    console.log(JSON.stringify(stagePlatformConfiguration({release:args[2],verified,host:args[6],state:args[8],destination:args[10]}),null,2));
  }else if(args[0]==='plan-config'){
    if(args[7]!=='--state')throw Error('arguments');
    console.log(JSON.stringify(platformConfigurationPlan({release:args[2],verified,host:args[6],state:args[8]}),null,2));
  }else if(['plan-rollback','plan-rollback-seven','plan-rollback-eight'].includes(args[0])){
    if(args[7]!=='--previous'||args[9]!=='--previous-sha256'||args[11]!=='--backup'||args[13]!=='--backup-sha256'||args[15]!=='--to')throw Error('arguments');
    const previous=validatePlatformRelease(args[8],args[10],{journalSchema:args[0]==='plan-rollback-seven'?7:args[0]==='plan-rollback-eight'?8:9});
    console.log(JSON.stringify(platformRollbackStatePlan({release:args[2],current:verified,previousRelease:args[8],previous,
      host:args[6],backup:args[12],backupSHA256:args[14],destination:args[16]}),null,2));
  }else if(['plan-backup-config','plan-uninstall-config'].includes(args[0])){
    if(args[7]!=='--state'||args[9]!=='--configuration'||args[11]!=='--to')throw Error('arguments');
    const makePlan=args[0]==='plan-uninstall-config'?platformUninstallPlan:platformStatePlan;
    console.log(JSON.stringify(makePlan({operation:'backup',release:args[2],verified,host:args[6],source:args[8],configuration:args[10],destination:args[12]}),null,2));
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
