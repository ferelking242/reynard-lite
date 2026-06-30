//
//  Utils.m
//  Reynard
//
//  Created by Minh Ton on 12/4/26.
//

// https://github.com/AngelAuraMC/Amethyst-iOS/blob/ed267f52dafa24219f1166c542294b0e682ebc64/Natives/utils.m
// https://github.com/AngelAuraMC/Amethyst-iOS/blob/00678b07a192ef5c79f8c4a2e4cecf1d7406c8c5/Natives/SurfaceViewController.m
// https://github.com/opa334/TrollStore/blob/88424f683b2a08f34a3f88985f790f97d84ce1df/Shared/TSUtil.m

#import "Utils.h"

#include <string.h>
#include <errno.h>
#include <sys/types.h>
#import <spawn.h>
#import <sys/wait.h>

// ── memorystatus_control commands (from XNU kern/kern_memorystatus.h) ─────────
#define MEMORYSTATUS_CMD_SET_PRIORITY_PROPERTIES  2   // set jetsam priority band
#define MEMORYSTATUS_CMD_SET_JETSAM_TASK_LIMIT    6   // set RSS kill limit

// ── Jetsam priority bands ─────────────────────────────────────────────────────
// Higher value = harder to kill. Band 23 is the "audio & accessory" tier —
// the same level iOS uses for background-audio and accessory apps.
// Normal foreground apps are at band 10; we sit above them so jetsam kills
// other idle apps first and leaves our Gecko session alive.
#define JETSAM_PRIORITY_AUDIO_AND_ACCESSORY  23

// Struct layout mirrors memorystatus_priority_properties_t in XNU.
typedef struct {
    int32_t  priority;
    uint64_t user_data;
} memorystatus_priority_properties_t;

#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1

// ── Low-memory device tuning ──────────────────────────────────────────────────
//
// iPhone 7 has 2 GB physical RAM.  iOS itself + the main process need headroom,
// so we cap the tab-process jetsam limit conservatively:
//
//   • 2 GB  device → 480 MB cap   (enough for Replit, avoids OOM kills)
//   • 3 GB+ device → 640 MB cap
//   • 4 GB+ device → 850 MB cap
//   • 6 GB+ device → 75% of physical (original formula, high-end devices)
//
// These values are intentionally conservative so the OS never force-kills the
// tab process mid-session on low-RAM hardware.
// ─────────────────────────────────────────────────────────────────────────────

static int jetsamLimitMB(void) {
    uint64_t physMB = (uint64_t)(NSProcessInfo.processInfo.physicalMemory >> 20);

    if (physMB <= 2048) {
        return 480;           // iPhone 7 / SE 1st gen (2 GB)
    } else if (physMB <= 3072) {
        return 640;           // iPhone 8 / X (3 GB)
    } else if (physMB <= 4096) {
        return 850;           // iPhone XS / 11 (4 GB)
    } else {
        return (int)(physMB * 0.75);  // 6 GB+ flagships – keep original headroom
    }
}

CFTypeRef SecTaskCopyValueForEntitlement(void *task, NSString *entitlement, CFErrorRef _Nullable *error);
void *SecTaskCreateFromSelf(CFAllocatorRef allocator);
int memorystatus_control(uint32_t command, int32_t pid, uint32_t flags, void *buffer, size_t buffersize);

extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t * __restrict attr, uid_t persona, uint32_t flags);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t * __restrict attr, uid_t uid);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t * __restrict attr, uid_t gid);

BOOL getEntitlementValue(NSString *key) {
    void *secTask = SecTaskCreateFromSelf(NULL);
    if (!secTask) return NO;

    CFTypeRef value = SecTaskCopyValueForEntitlement(secTask, key, nil);
    CFRelease(secTask);
    if (!value) return NO;

    BOOL hasValue = ![(__bridge id)value isKindOfClass:NSNumber.class] || [(__bridge NSNumber *)value boolValue];
    CFRelease(value);
    return hasValue;
}

/// Sets the RSS kill-limit (the threshold at which jetsam terminates the process).
void updateJetsamControl(pid_t pid) {
    if (!getEntitlementValue(@"com.apple.private.memorystatus")) return;

    int limit = jetsamLimitMB();
    if (memorystatus_control(MEMORYSTATUS_CMD_SET_JETSAM_TASK_LIMIT, pid, limit, NULL, 0) == -1) {
        NSLog(@"[Reynard] Failed to set jetsam limit to %d MB for pid %d: %s", limit, pid, strerror(errno));
    } else {
        NSLog(@"[Reynard] Jetsam limit → %d MB for pid %d", limit, pid);
    }
}

/// Elevates the process to the audio/accessory priority band (23).
/// Jetsam evicts processes in ascending priority order, so higher band = last to die.
/// The main app and every Gecko child process should call this once on start.
void updateJetsamPriority(pid_t pid) {
    if (!getEntitlementValue(@"com.apple.private.memorystatus")) return;

    memorystatus_priority_properties_t props = {
        .priority  = JETSAM_PRIORITY_AUDIO_AND_ACCESSORY,
        .user_data = 0,
    };
    if (memorystatus_control(MEMORYSTATUS_CMD_SET_PRIORITY_PROPERTIES, pid, 0, &props, sizeof(props)) == -1) {
        NSLog(@"[Reynard] Failed to set jetsam priority for pid %d: %s", pid, strerror(errno));
    } else {
        NSLog(@"[Reynard] Jetsam priority → %d for pid %d", JETSAM_PRIORITY_AUDIO_AND_ACCESSORY, pid);
    }
}

int spawnRoot(NSString *path, NSArray<NSString *> *args) {
    NSMutableArray<NSString *> *arguments = args.mutableCopy ?: [NSMutableArray new];
    [arguments insertObject:path atIndex:0];

    NSUInteger argCount = arguments.count;
    char **argv = calloc(argCount + 1, sizeof(char *));
    for (NSUInteger index = 0; index < argCount; index++) {
        argv[index] = strdup(arguments[index].UTF8String);
    }

    posix_spawnattr_t attributes;
    posix_spawnattr_init(&attributes);
    posix_spawnattr_set_persona_np(&attributes, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attributes, 0);
    posix_spawnattr_set_persona_gid_np(&attributes, 0);

    pid_t taskPID = 0;
    int spawnError = posix_spawn(&taskPID, path.fileSystemRepresentation, NULL, &attributes, argv, NULL);

    posix_spawnattr_destroy(&attributes);
    for (NSUInteger index = 0; index < argCount; index++) free(argv[index]);
    free(argv);

    if (spawnError != 0) return spawnError;

    int status = 0;
    do {
        if (waitpid(taskPID, &status, 0) == -1) {
            if (errno == EINTR) continue;
            return errno;
        }
    } while (!WIFEXITED(status) && !WIFSIGNALED(status));

    return WEXITSTATUS(status);
}
