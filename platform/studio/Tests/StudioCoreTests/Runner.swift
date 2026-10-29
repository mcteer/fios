import Foundation

@main
struct PolicyTestRunner {
    static func main() throws {
        let checks:[(String,()throws->Void)]=[
            ("mock support",runMockSupportTests),
            ("operator commands",runOperatorServiceCommandTests),
            ("service status",runServiceStatusTests),
            ("service recovery",runServiceRecoveryTests),
            ("service reconciliation",runServiceReconciliationTests),
            ("async session control",runAsyncSessionControlTests),
            ("session endpoint",runSessionEndpointTests),
            ("service recovery backup",runServiceRecoveryBackupTests),
            ("service identity",runServiceIdentityTests),
            ("service health",runServiceHealthTests),
            ("async native control",runAsyncNativeControlTests),
            ("native maintenance",runNativeMaintenanceTests),
            ("native control",runNativeControlTests),
            ("scalars",runScalarTests),
            ("enums",runEnumTests),
            ("shared kernel VM",runSharedKernelVMTests),
            ("VM footprint",runVMHostFootprintTests),
            ("command slots",runCommandSlotTests),
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
            ("security",runSecurityTests),
            ("contracts",runContractTests),
            ("backup",runBackupTests),
            ("task mailbox",runTaskMailboxTests),
            ("composed pressure",runComposedPressureTests),
            ("task commands",runTaskCommandTests),
            ("task owner",runTaskOwnerTests),
            ("async artifacts",runAsyncArtifactTests),
            ("artifact disk admission",runArtifactDiskAdmissionTests),
            ("sandbox stream",runSandboxStreamTests),
            ("Docker VM metadata flow",runDockerVMMetadataFlowTests),
            ("Docker VM metadata",runDockerVMMetadataTests),
            ("Docker attach",runDockerAttachTests),
            ("sandbox executor",runSandboxExecutorTests),
            ("job controller",runJobControllerTests),
            ("sandbox model",runSandboxModelTests),
            ("worker census",runWorkerCensusTests),
            ("worker recovery",runWorkerRecoveryTests),
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
            ("consumer",runConsumerTests),
            ("CPU",runCPUTests),
            ("worker resources",runWorkerResourceTests),
            ("drain",runDrainTests),
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
            ("admission",runAdmissionTests),
            ("admission boundaries",runAdmissionBoundaryTests),
            ("protocol",runProtocolTests),
            ("journal views",runJournalViewTests),
            ("journal",runJournalTests),
            ("journal schema",runJournalSchemaTests),
            ("journal rows",runJournalRowTests),
            ("journal lock",runJournalLockTests),
            ("ownership records",runOwnershipRecordTests),
            ("job lease limits",runJobLeaseLimitTests),
            ("job journal",runJobJournalTests),
            ("watchdog",runWatchdogTests)
        ]
        for (name,check) in checks {
            do {try check()} catch {
                // Suite name only: no SQL, argv, credentials or workload data.
                FileHandle.standardError.write(Data(("Policy suite failed: "+name+"\n").utf8))
                throw error
            }
        }
        ActivityCoherenceTests.run()
        try DetailedObservationTests.run()
        try InferenceScopeTests.run()
        try MigrationTests.run()
        let tests = ActivityTests()
        try tests.testIdleRequiresAuthoritativeAllClientCoverage()
        try tests.testQueuedPreparingAndResponseOwnersAreBusy()
        tests.testStaleFutureAndMalformedSamplesReject()
        try tests.testIdleReplacementIsAllowedButBusySwitchIsNot()
        try tests.testNewerSuccessDoesNotClearEarlierUncertainty()
        try tests.testDuplicateAndUnknownCompletionFailClosed()
        try tests.testOwnershipIsBoundedAndRestartDoesNotRelease()
        print("PASS: 7 activity/ownership policy tests (no native side effects)")
    }
}
