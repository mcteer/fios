import Foundation

func runTaskOwnerTests() throws {
    let token=TaskOwner.newToken(),other=TaskOwner.newToken()
    let owner=try TaskOwner(token:token,peerUID:501)
    guard owner.hash.count==64,try TaskOwner(token:token,peerUID:501).hash==owner.hash,
          try TaskOwner(token:token,peerUID:502).hash != owner.hash,
          try TaskOwner(token:other,peerUID:501).hash != owner.hash else {fatalError("Owner credential lost UID/token binding")}
    for malformed in ["",owner.hash,token+"=",String(repeating:"A",count:43),token+"\n"] {
        do {_=try TaskOwner(token:malformed,peerUID:501);fatalError("Malformed owner credential accepted")} catch ControlError.unauthorized {}
    }
    print("PASS: canonical256-bit task-owner credential, UID-bound content-free durable digest and malformed/forged-owner rejection")
}
