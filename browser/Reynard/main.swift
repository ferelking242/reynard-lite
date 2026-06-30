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

// ── Accessibility — disable at runtime (NOT at build time) ───────────────────
// Removing --disable-accessibility from the mozconfig prevents a hard crash:
// when built without accessibility, Gecko's startup sequence still tries to
// load the accessibility chrome CSS files (which are absent), hits
// ErrorLoadingSheet(eCrash), and kills the process.  force_disabled=1 turns
// off the accessibility engine at runtime without removing its chrome assets.
user_pref("accessibility.force_disabled", 1);

// ── GPU compositor / WebRender ────────────────────────────────────────────────
// WebRender uses the A9 GPU for compositing instead of the CPU — every scroll
// frame costs near-zero CPU time.  We enable it but do NOT force a separate
// GPU process: layers.gpu-process spawns an extra ~50-100 MB process at
// startup, which is fatal on 2 GB devices that are already at the OOM edge.
user_pref("gfx.webrender.enabled", true);
user_pref("layers.acceleration.disabled", false);

// ── Async Pan-Zoom ────────────────────────────────────────────────────────────
// APZ runs scrolling on its own thread; even heavy JS on Replit can't cause
// scroll jank when APZ is active.
user_pref("apz.allow_zooming", true);

// ── JavaScript heap (cap + incremental GC) ────────────────────────────────────
// Without a cap, Gecko can grow the JS heap to 400+ MB on Replit's heavy
// bundles (Monaco, React, etc.) and trigger an OOM kill on 2 GB devices.
// Incremental GC spreads collection work across many 1-2 ms slices instead
// of one big pause, keeping the UI responsive during collection.
// A small initial nursery reduces RSS at cold start.
user_pref("javascript.options.mem.max", 192);
user_pref("javascript.options.mem.high_water_mark", 128);
user_pref("javascript.options.mem.gc_high_frequency_heap_growth_max", 150);
user_pref("javascript.options.mem.gc_incremental", true);
user_pref("javascript.options.mem.gc_dynamic_mark_slice", true);
user_pref("javascript.options.mem.nursery.min_size_kb", 256);

// ── Network ───────────────────────────────────────────────────────────────────
// HTTP/3 (QUIC) reduces latency on mobile — avoids TCP head-of-line blocking.
// More parallel connections to replit.com speeds up asset fetches.
// Disable IPv6 — on a typical iPhone 7 SIM the IPv6 path adds RTT.
// Kill disk cache: flash storage on old iPhones is slow; everything in RAM.
// Keep RAM cache at 8 MB — enough for repeat navigations, safe on 2 GB.
user_pref("network.http.http3.enabled", true);
user_pref("network.http.max-persistent-connections-per-server", 8);
user_pref("network.prefetch-next", true);
user_pref("network.dns.disableIPv6", true);
user_pref("network.cache.disk.capacity", 0);
user_pref("network.cache.memory.capacity", 8192);

// ── Image surface cache ───────────────────────────────────────────────────────
// Cap decoded-image RAM to 32 MB; discard off-screen surfaces after 10 s.
// Replit loads many small icons and avatars that would otherwise stay decoded.
user_pref("image.mem.surfacecache.max_size_kb", 32768);
user_pref("image.mem.max_ms_before_discard", 10000);

// ── Telemetry / background reporters ─────────────────────────────────────────
// These initialise at startup and allocate background threads + memory for
// nothing.  Glean (FOG) and the legacy telemetry system are both disabled.
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("telemetry.fog.enabled", false);
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
