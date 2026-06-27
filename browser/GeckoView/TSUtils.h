//
//  TSUtils.h
//  GeckoView
//
//  Created by Minh Ton on 1/2/26.
//

#ifndef TSUtils_h
#define TSUtils_h

#import <Foundation/Foundation.h>
#include <sys/types.h>

NS_ASSUME_NONNULL_BEGIN

BOOL getEntitlementValue(NSString *key);
void updateJetsamControl(pid_t pid);

NS_ASSUME_NONNULL_END

#endif /* TSUtils_h */
