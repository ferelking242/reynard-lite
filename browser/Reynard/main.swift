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

let userJS = """
// ── Startup crash prevention ──────────────────────────────────────────────────
user_pref("dom.serviceWorkers.enabled", false);

// ── GPU compositor / WebRender ────────────────────────────────────────────────
// WebRender uses the A9 GPU for compositing instead of the CPU.
// Without it, every scroll frame burns CPU cycles in the rasteriser.
user_pref("gfx.webrender.enabled", true);
user_pref("gfx.webrender.force-enabled", true);
user_pref("layers.acceleration.disabled", false);
user_pref("layers.gpu-process.enabled", true);

// ── Async Pan-Zoom ────────────────────────────────────────────────────────────
// APZ runs scrolling on its own thread; even heavy JS on Replit can't cause
// scroll jank when APZ is active.
user_pref("apz.allow_zooming", true);

// ── JavaScript heap (cap + incremental GC) ────────────────────────────────────
// Without a cap, Gecko can grow the JS heap to 400+ MB on Replit's heavy bundles
// (Monaco, React, etc.) and trigger an OOM kill on 2 GB devices.
// Incremental GC spreads collection work across many 1-2 ms slices instead of
// one big pause, keeping the UI responsive during collection.
user_pref("javascript.options.mem.max", 192);
user_pref("javascript.options.mem.high_water_mark", 128);
user_pref("javascript.options.mem.gc_high_frequency_heap_growth_max", 150);
user_pref("javascript.options.mem.gc_incremental", true);
user_pref("javascript.options.mem.gc_dynamic_mark_slice", true);

// ── Network ───────────────────────────────────────────────────────────────────
// HTTP/3 (QUIC) reduces latency on mobile — avoids TCP head-of-line blocking.
// More parallel connections to replit.com speeds up asset fetches.
// Disable IPv6 — on a typical iPhone 7 SIM the IPv6 path adds RTT.
// Kill disk cache: flash storage on old iPhones is slow; everything in RAM.
user_pref("network.http.http3.enabled", true);
user_pref("network.http.max-persistent-connections-per-server", 8);
user_pref("network.prefetch-next", true);
user_pref("network.dns.disableIPv6", true);
user_pref("network.cache.disk.capacity", 0);
user_pref("network.cache.memory.capacity", 16384);

// ── Image surface cache ───────────────────────────────────────────────────────
// Cap decoded-image RAM to 48 MB; discard off-screen surfaces after 10 s.
// Replit loads many small icons and avatars that would otherwise stay decoded.
user_pref("image.mem.surfacecache.max_size_kb", 49152);
user_pref("image.mem.max_ms_before_discard", 10000);

// ── Telemetry / background reporters ─────────────────────────────────────────
// These timers fire repeatedly in background and consume CPU + RAM for nothing.
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("app.shield.optoutstudies.enabled", false);

"""

try? userJS.write(
    to: profileDir.appendingPathComponent("user.js"),
    atomically: true,
    encoding: .utf8
)

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
