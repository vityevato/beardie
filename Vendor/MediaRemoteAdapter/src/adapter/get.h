// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#ifndef MEDIAREMOTEADAPTER_ADAPTER_GET_H
#define MEDIAREMOTEADAPTER_ADAPTER_GET_H

#import <Foundation/Foundation.h>

NSDictionary *internal_get(BOOL isTestMode);

// Returns one payload dictionary for every client registered with MediaRemote.
// Unlike internal_get_for_bundle(), clients without a title or complete
// metadata are still included, so callers can see all registered players.
NSArray *internal_get_all_clients(void);

#endif // MEDIAREMOTEADAPTER_ADAPTER_GET_H
