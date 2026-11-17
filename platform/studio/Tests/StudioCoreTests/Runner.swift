import Foundation
import Darwin

@main
struct PolicyTestRunner {
    static func main() throws {
        let activityTests=ActivityTests()
        let checks:[(String,()throws->Void)]=[
            ("mock support",runMockSupportTests),
            ("operator commands",runOperatorServiceCommandTests),
            ("operator service status",runOperatorServiceStatusTests),
            ("service status",runServiceStatusTests),
            ("service status summary",runServiceStatusSummaryTests),
            ("cleanup status recovery",runCleanupStatusRecoveryTests),
            ("native control diagnostics",runNativeControlDiagnosticsTests),
            ("native control continuity",runNativeControlContinuityTests),
            ("native admission binding",runNativeAdmissionBindingTests),
            ("timestamped native control",runNativeTimestampedControlTests),
            ("model placement",runModelPlacementTests),
            ("workspace configuration",runWorkspaceConfigurationTests),
            ("read-only native observation",runNativeReadOnlyObservationTests),
            ("service recovery status",runServiceRecoveryStatusTests),
            ("service recovery",runServiceRecoveryTests),
            ("serving custody",runServingCustodyTests),
            ("service reconciliation",runServiceReconciliationTests),
            ("async session control",runAsyncSessionControlTests),
            ("session endpoint",runSessionEndpointTests),
            ("service recovery backup",runServiceRecoveryBackupTests),
            ("service identity",runServiceIdentityTests),
            ("service process census",runServiceProcessCensusTests),
            ("service health",runServiceHealthTests),
            ("OrbStack health",runOrbStackHealthTests),
            ("async native control",runAsyncNativeControlTests),
            ("native maintenance",runNativeMaintenanceTests),
            ("native control",runNativeControlTests),
            ("native request lineage",runNativeRequestLineageTests),
            ("native handoff cancellation",runNativeHandoffCancellationTests),
            ("native lineage consumer",runNativeLineageConsumerTests),
            ("durable native lineage",runDurableLineageTests),
            ("native lineage polling",runNativeLineagePollingTests),
            ("native lineage schema migration",runLineageMigrationTests),
            ("scalars",runScalarTests),
            ("enums",runEnumTests),
            ("shared kernel VM",runSharedKernelVMTests),
            ("VM footprint",runVMHostFootprintTests),
            ("command slots",runCommandSlotTests),
            ("Python tree review",runPythonTreeTests),
            ("Python enrollment",runPythonEnrollmentTests),
            ("sandbox enrollment",runSandboxEnrollmentTests),
            ("async VM resources",runAsyncVMResourceTests),
            ("owned VM resources",runOwnedVMResourceTests),
            ("VM probe permission",runVMProbePermissionTests),
            ("model-only VM isolation",runModelOnlyVMIsolationTests),
            ("global host pressure",runGlobalHostPressureTests),
            ("VM controller",runVMControllerTests),
            ("native VM inventory",runNativeVMInventoryTests),
            ("VM envelope",runVMEnvelopeTests),
            ("VM resources",runVMResourceTests),
            ("GPU resources",runGPUResourceTests),
            ("resource observations",runResourceObservationTests),
            ("VM resource enrollment",runVMResourceEnrollmentTests),
            ("VM resource profile reader",runVMResourceProfileReaderTests),
            ("read-only VM resources",runReadOnlyVMResourceTests),
            ("VM running prerequisite",runVMRunningTests),
            ("security",runSecurityTests),
            ("contracts",runContractTests),
            ("backup",runBackupTests),
            ("task mailbox",runTaskMailboxTests),
            ("composed pressure",runComposedPressureTests),
            ("task commands",runTaskCommandTests),
            ("task CLI round trip",runTaskClientTests),
            ("interrupted task completion",runTaskCompletionTests),
            ("task owner",runTaskOwnerTests),
            ("async artifacts",runAsyncArtifactTests),
            ("artifact disk admission",runArtifactDiskAdmissionTests),
            ("sandbox stream",runSandboxStreamTests),
            ("Docker VM metadata flow",runDockerVMMetadataFlowTests),
            ("Docker VM metadata",runDockerVMMetadataTests),
            ("Docker attach",runDockerAttachTests),
            ("sandbox executor",runSandboxExecutorTests),
            ("sandbox removal",runSandboxRemovalTests),
            ("job controller",runJobControllerTests),
            ("sandbox exit proof",runSandboxExitProofTests),
            ("sandbox model",runSandboxModelTests),
            ("worker census",runWorkerCensusTests),
            ("worker recovery",runWorkerRecoveryTests),
            ("worker reap durability",runWorkerReapDurabilityTests),
            ("model broker",runModelBrokerTests),
            ("Python factory",runPythonFactoryTests),
            ("private worker",runPrivateWorkerTests),
            ("model protocol",runModelProtocolTests),
            ("session",runSessionTests),
            ("session operations",runSessionOperationTests),
            ("root policy file",runRootPolicyFileTests),
            ("session enrollment",runSessionEnrollmentTests),
            ("application identity",runApplicationIdentityTests),
            ("application links",runApplicationLinkTests),
            ("sandbox lifecycle",runSandboxLifecycleTests),
            ("sandbox safety",runSandboxSafetyTests),
            ("sandbox journal",runSandboxJournalTests),
            ("observation",runObservationTests),
            ("supervisor path aliases",runSupervisorStatusAliasTests),
            ("consumer",runConsumerTests),
            ("CPU",runCPUTests),
            ("worker resources",runWorkerResourceTests),
            ("drain",runDrainTests),
            ("drain controller",runServiceDrainControllerTests),
            ("force controller",runServiceForceControllerTests),
            ("runtime service scope",runServiceRuntimeScopeTests),
            ("services",runServiceTests),
            ("artifact limits",runArtifactLimitTests),
            ("artifacts",runArtifactTests),
            ("audit",runAuditTests),
            ("transfers",runTransferTests),
            ("framing",runFramingTests),
            ("runtime",runRuntimeTests),
            ("runtime enrollment",runRuntimeEnrollmentTests),
            ("runtime endpoint",runRuntimeEndpointTests),
            ("runtime peer",runRuntimePeerTests),
            ("manager execution",runManagerExecutionTests),
            ("sandbox source identity",runSandboxSourceIdentityTests),
            ("service admission",runServiceAdmissionTests),
            ("admission",runAdmissionTests),
            ("admission boundaries",runAdmissionBoundaryTests),
            ("protocol",runProtocolTests),
            ("journal views",runJournalViewTests),
            ("journal",runJournalTests),
            ("inference record retention",runInferenceRetentionTests),
            ("journal schema",runJournalSchemaTests),
            ("journal rows",runJournalRowTests),
            ("journal lock",runJournalLockTests),
            ("ownership records",runOwnershipRecordTests),
            ("job lease limits",runJobLeaseLimitTests),
            ("job journal",runJobJournalTests),
            ("watchdog",runWatchdogTests),
            ("activity coherence",ActivityCoherenceTests.run),
            ("detailed observations",DetailedObservationTests.run),
            ("inference scopes",InferenceScopeTests.run),
            ("worker RSS breach",runWorkerRSSBreachTests),
            ("async worker start",runAsyncWorkerStartTests),
            ("late worker recovery",runLateWorkerRecoveryTests),
            ("migration",MigrationTests.run),
            ("release staging",runReleaseStagingTests),
            ("activity idle authority",activityTests.testIdleRequiresAuthoritativeAllClientCoverage),
            ("activity owned phases",activityTests.testQueuedPreparingAndResponseOwnersAreBusy),
            ("activity invalid samples",activityTests.testStaleFutureAndMalformedSamplesReject),
            ("activity idle replacement",activityTests.testIdleReplacementIsAllowedButBusySwitchIsNot),
            ("activity independent uncertainty",activityTests.testNewerSuccessDoesNotClearEarlierUncertainty),
            ("activity duplicate completion",activityTests.testDuplicateAndUnknownCompletionFailClosed),
            ("activity bounded restart",activityTests.testOwnershipIsBoundedAndRestartDoesNotRelease)
        ]
        let names=checks.map { $0.0 }
        guard Set(names).count==names.count else {throw PolicyError.invalidObservation}
        let arguments=Array(CommandLine.arguments.dropFirst())
        if arguments==["--list-checks"] {
            print(String(decoding:try JSONSerialization.data(withJSONObject:names),as:UTF8.self));return
        }
        var partition:Int?
        if !arguments.isEmpty {
            guard arguments.count==4,arguments[0]=="--partition",arguments[2]=="--partitions",arguments[3]=="2",
                  let value=Int(arguments[1]),(0..<2).contains(value),
                  ProcessInfo.processInfo.environment["FIOS_PLATFORM_TEST_RECEIPT"] != nil else {throw PolicyError.invalidObservation}
            partition=value
        }
        let selected=checks.enumerated().filter {partition==nil || $0.offset%2==partition!}
        for (_,item) in selected {
            let (name,check)=item
            FileHandle.standardError.write(Data(("Policy suite starting: "+name+"\n").utf8))
            do {try check();fflush(nil)} catch {
                FileHandle.standardError.write(Data(("Policy suite failed: "+name+"\n").utf8))
                throw error
            }
        }
        if let partition,let receipt=ProcessInfo.processInfo.environment["FIOS_PLATFORM_TEST_RECEIPT"] {
            let value:[String:Any]=["version":1,"partition":partition,"partitions":2,
                "checks":selected.map {$0.element.0},"completed":selected.count]
            try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]).write(to:URL(fileURLWithPath:receipt),options:.atomic)
        }
        print("PASS: \(selected.count) selected policy checks")
    }
}
