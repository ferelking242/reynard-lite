//
//  Utils.h
//  Reynard
//
//  Created by Minh Ton on 12/4/26.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

BOOL getEntitlementValue(NSString *key);

/// Sets the jetsam RSS kill-limit for a process (requires com.apple.private.memorystatus).
void updateJetsamControl(pid_t pid);

/// Elevates a process to the audio/accessory jetsam priority band so it is
/// killed last under memory pressure (requires com.apple.private.memorystatus).
void updateJetsamPriority(pid_t pid);

int spawnRoot(NSString *path, NSArray<NSString *> *args);

NS_ASSUME_NONNULL_END
