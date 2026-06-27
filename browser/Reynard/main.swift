import UIKit
  import GeckoView

  // Pre-create the Gecko profile directory and write user.js before Gecko init.
  // ServiceWorkerRegistrar::GetShutdownPhase() MOZ_CRASHes when it tries to
  // acquire nsIAsyncShutdownService before it is ready during early iOS startup.
  // Writing user_pref("dom.serviceWorkers.enabled", false) to user.js disables
  // ServiceWorkerRegistrar entirely — Gecko reads user.js during profile load,
  // before any XPCOM services are initialised, so the pref is in effect when
  // ServiceWorkerParentInterceptEnabled() is evaluated in Init().
  let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
  let profileDir = libraryDir.appendingPathComponent("ReyProfile", isDirectory: true)
  try? FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
  try? "user_pref(\"dom.serviceWorkers.enabled\", false);\n"
      .write(to: profileDir.appendingPathComponent("user.js"), atomically: true, encoding: .utf8)

  // Inject -profile <path> so Gecko uses the directory we prepared above.
  var geckoArgs = CommandLine.arguments + ["-profile", profileDir.path]
  var cArgs: [UnsafeMutablePointer<Int8>?] = geckoArgs.map { strdup($0) }
  cArgs.append(nil)
  cArgs.withUnsafeMutableBufferPointer { ptr in
      // Never returns: nsAppShell::Run calls UIApplicationMain(AppShellDelegate)
      // internally; SceneDelegate creates the window via Info.plist scene config.
      GeckoRuntime.main(argc: Int32(geckoArgs.count), argv: ptr.baseAddress!)
  }
  // Unreachable — satisfies the Swift compiler entry-point check.
  UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil,
                    NSStringFromClass(AppDelegate.self))
  