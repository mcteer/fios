import Foundation

enum SessionOperation:String,Codable { case launch, quit }
enum SessionPlan:Equatable {
    case launchApplication(path:String)
    case quitApplication(bundle:String)
    static func fixed(service:ManagedService,operation:SessionOperation)->SessionPlan {
        switch (service,operation) {
        case (.mlx,.launch):return .launchApplication(path:"/Applications/MLX-Serve.app")
        case (.orbstack,.launch):return .launchApplication(path:"/Applications/OrbStack.app")
        case (.mlx,.quit):return .quitApplication(bundle:"com.dalcu.mlx-core")
        case (.orbstack,.quit):return .quitApplication(bundle:"dev.kdrag0n.MacVirt")
        }
    }
}
