import Foundation
import Darwin

// Reviewed launch data only. Construction neither enrolls configuration nor
// reserves native work. No wire decoder or installed factory is exposed here.
// Keep credential resolution in memory, outside durable recovery metadata.
struct NativeServingLaunchInputs:Sendable {
    let arguments:[String]
    let environment:[String:String]
    let workingDirectory:String
    init(arguments:[String],environment:[String:String],workingDirectory:String)throws {
        // Upstream treats an absent/empty key environment as unauthenticated.
        // Refuse that configuration before handing it to the process primitive.
        var channels=0,index=0,hosts=0,ports=0
        while index<arguments.count {
            let argument=arguments[index]
            if argument=="--api-key" || argument=="--api-key-env" {
                guard index+1<arguments.count else {throw RuntimeError.invalid}
                let value=arguments[index+1]
                guard !value.isEmpty,!value.contains("\0") else {throw RuntimeError.invalid}
                if argument=="--api-key-env" {
                    guard value=="FIOS_MLX_SERVING_API_KEY",let secret=environment[value],
                          !secret.isEmpty,!secret.contains("\0") else {throw RuntimeError.invalid}
                }
                channels+=1;index+=2
            } else if argument=="--host" || argument=="--port" {
                guard index+1<arguments.count else {throw RuntimeError.invalid}
                let value=arguments[index+1]
                if argument=="--host" {
                    var ipv4=in_addr(),ipv6=in6_addr()
                    guard hosts==0,value.utf8.count<=64,!value.contains("\0"),
                          value.withCString({inet_pton(AF_INET,$0,&ipv4)})==1 || value.withCString({inet_pton(AF_INET6,$0,&ipv6)})==1 else {throw RuntimeError.invalid}
                    hosts+=1
                } else {
                    guard ports==0,let port=UInt16(value),port>0,String(port)==value else {throw RuntimeError.invalid}
                    ports+=1
                }
                index+=2
            } else {
                // The pinned native parser accepts the two-token forms only.
                guard !argument.hasPrefix("--api-key="),!argument.hasPrefix("--api-key-env="),
                      !argument.hasPrefix("--host="),!argument.hasPrefix("--port=") else {throw RuntimeError.invalid}
                index+=1
            }
        }
        // Never infer the native CLI's wildcard/default port as preserved configuration.
        guard channels==1,hosts==1,ports==1 else {throw RuntimeError.invalid}
        self.arguments=arguments;self.environment=environment;self.workingDirectory=workingDirectory
    }
}
