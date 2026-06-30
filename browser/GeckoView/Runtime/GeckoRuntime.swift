//
//  GeckoRuntime.swift
//  Reynard
//
//  Created by Minh Ton on 1/2/26.
//

import Foundation
import UIKit

class GeckoRuntimeImpl: NSObject, SwiftGeckoViewRuntime {
    func runtimeDispatcher() -> any SwiftEventDispatcher {
        return GeckoEventDispatcherWrapper.runtimeInstance
    }
    
    func dispatcher(byName name: UnsafePointer<CChar>!) -> any SwiftEventDispatcher {
        return GeckoEventDispatcherWrapper.lookup(byName: String(cString: name))
    }
    
    @objc(childProcessDidStartWithPID:processType:)
    func childProcessDidStart(withPID pid: Int32, processType: String) {
        // Raise the child's jetsam priority to the audio/accessory band (23)
        // so it survives memory pressure longer than idle background apps.
        updateJetsamPriority(pid)

        // Cap the child's RSS kill-limit to the device-appropriate value.
        updateJetsamControl(pid)
        
        NotificationCenter.default.post(
            name: Notification.Name("GeckoRuntime.ChildProcessDidStart"),
            object: nil,
            userInfo: [
                "pid": NSNumber(value: pid),
                "processType": processType
            ]
        )
    }
}

public class GeckoRuntime {
    static let runtime = GeckoRuntimeImpl()
    
    public static var version: String {
        return GeckoRuntimeBridge.version()
    }
    
    public static func main(
        argc: Int32,
        argv: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>
    ) {
        MainProcessInit(argc, argv, runtime)
    }
    
    public static func childMain(
        xpcConnection: xpc_connection_t,
        process: GeckoProcessExtension
    ) {
        ChildProcessInit(xpcConnection, process, runtime)
    }
}
