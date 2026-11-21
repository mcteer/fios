import Foundation

func runApplicationLinkTests()throws {
    typealias Node=RootPolicyFile.TreeNode
    let base:[String:Node]=["":.directory,"Versions":.directory,"Versions/A":.directory,
        "Versions/A/Binary":.file,"Versions/Current":.link("A"),"Binary":.link("Versions/Current/Binary"),
        "Resources":.directory,"Versions/A/Resources":.link("../../Resources")]
    try RootPolicyFile.verifyApplicationLinks(base,deadline:ProcessInfo.processInfo.systemUptime+2)
    var variants:[[String:Node]]=[]
    for target in ["../outside","/System/Library/elsewhere","missing","Versions/A/Binary/../Resources","Binary"] {
        var value=base;value["Binary"] = .link(target);variants.append(value)
    }
    // Resolve symlinks before '..': lexical normalization would miss this
    // escape because the preceding link resets the actual directory depth.
    var escape=base;escape["Versions/A/root"] = .link("../..");escape["Binary"] = .link("Versions/A/root/../outside");variants.append(escape)
    var cycle=base;cycle["first"] = .link("second");cycle["second"] = .link("first");variants.append(cycle)
    var impossible=base;impossible["Binary/child"] = .file;variants.append(impossible)
    for value in variants {
        do {try RootPolicyFile.verifyApplicationLinks(value,deadline:ProcessInfo.processInfo.systemUptime+2);fatalError("Application link escaped its protected physical tree")}catch ControlError.unauthorized {}
    }
    do {try RootPolicyFile.verifyApplicationLinks(base,deadline:ProcessInfo.processInfo.systemUptime-1);fatalError("Expired application tree accepted")}catch ControlError.unauthorized {}
    print("PASS: framework version/resource relative links, actual symlink-before-parent resolution, escape/absolute/missing/file traversal/cycle/impossible physical hierarchy and deadline refusal; metadata vectors grant no file authority")
}
