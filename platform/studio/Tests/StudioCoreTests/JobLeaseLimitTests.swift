import Foundation

func runJobLeaseLimitTests() throws {
    var lease=try JobLease(created:1000)
    guard lease.deadline==901000,lease.expires==31000 else {fatalError("Default900s lifetime/30s lease changed")}
    try lease.renew(now:11000)
    guard lease.expires==41000 else {fatalError("10s renewal did not extend finite lease")}
    for now in stride(from:Int64(21000),through:891000,by:10000) {try lease.renew(now:now)}
    try lease.renew(now:900999)
    guard lease.expires==901000,!lease.valid(now:901000) else {fatalError("Default deadline was extended")}
    do {try lease.renew(now:900999);fatalError("Expired lease revived by clock rollback")}catch AdmissionError.expired{}
    var maximum=try JobLease(created:1000,lifetime:1800000)
    for now in stride(from:Int64(11000),through:1791000,by:10000) {try maximum.renew(now:now)}
    guard maximum.deadline==1801000,!maximum.valid(now:1801000) else {fatalError("Absolute1800s cap not enforced")}
    for invalid in [Int64(0),-1,1800001] {
        do {_ = try JobLease(created:1000,lifetime:invalid);fatalError("Invalid absolute lifetime admitted")}catch AdmissionError.invalid{}
    }
    var revoked=try JobLease(created:1000);revoked.revoke()
    do {try revoked.renew(now:1001);fatalError("Explicit revocation revived")}catch AdmissionError.expired{}
    var clock=try JobLease(created:1000)
    guard !clock.valid(now:999),!clock.valid(now:1001) else {fatalError("Rollback revocation was reversible")}
    let sequence:[JobState]=[.reserved,.creating,.running,.revoking,.stopping,.removing,.removed]
    for (from,to) in zip(sequence,sequence.dropFirst()) {guard from.permits(to) else {fatalError("Required sandbox lifecycle transition missing")}}
    for next in JobState.allCases {guard !JobState.removed.permits(next) else {fatalError("Removed execution replay permitted")}}
    guard JobState.creating.permits(.reconciling),!JobState.reconciling.permits(.creating),!JobState.reconciling.permits(.running) else {fatalError("Uncertain execution replay permitted")}
    print("PASS:30s/10s lease renewal,900s default/1800s absolute cap, irreversible expiry/revocation/rollback and no lifecycle replay")
}
