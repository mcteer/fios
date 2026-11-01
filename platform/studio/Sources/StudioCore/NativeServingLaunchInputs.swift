import Foundation

// Reviewed launch data only. Construction neither enrolls configuration nor
// reserves native work. No wire decoder or installed factory is exposed here.
// Keep credential resolution in memory, outside durable recovery metadata.
struct NativeServingLaunchInputs {
    let arguments:[String]
    let environment:[String:String]
    let workingDirectory:String
    init(arguments:[String],environment:[String:String],workingDirectory:String)throws {
        // Upstream treats an absent/empty key environment as unauthenticated.
        // Refuse that configuration before handing it to the process primitive.
        var channels=0,index=0
        while index<arguments.count {
            let argument=arguments[index]
            if argument=="--api-key" || argument=="--api-key-env" {
                guard index+1<arguments.count else {throw RuntimeError.invalid}
                let value=arguments[index+1]
                guard !value.isEmpty,!value.hasPrefix("--"),!value.contains("\0") else {throw RuntimeError.invalid}
                if argument=="--api-key-env" {
                    guard value=="FIOS_MLX_SERVING_API_KEY",let secret=environment[value],
                          !secret.isEmpty,!secret.contains("\0") else {throw RuntimeError.invalid}
                }
                channels+=1;index+=2
            } else {
                // The pinned native parser accepts the two-token forms only.
                guard !argument.hasPrefix("--api-key="),!argument.hasPrefix("--api-key-env=") else {throw RuntimeError.invalid}
                index+=1
            }
        }
        guard channels==1 else {throw RuntimeError.invalid}
        self.arguments=arguments;self.environment=environment;self.workingDirectory=workingDirectory
    }
}
