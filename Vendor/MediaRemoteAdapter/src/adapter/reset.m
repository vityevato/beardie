// Copyright (c) 2026 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#import "adapter/reset.h"

#import "adapter/globals.h"
#import "adapter/now_playing.h"
#import "utility/helpers.h"

void adapter_reset(void) {
    if (g_mediaRemote.setNowPlayingApplicationOverrideEnabled == NULL) {
        fail(@"Resetting the now playing election is not supported on this "
             @"system");
    }

    // MediaRemote skips setting a value that equals the value this process
    // last set. A fresh process starts at false, so a plain false is ignored.
    g_mediaRemote.setNowPlayingApplicationOverrideEnabled(true);
    g_mediaRemote.setNowPlayingApplicationOverrideEnabled(false);

    // Give the daemon a chance to process both calls before exiting.
    waitForCommandCompletion();
}

extern void adapter_reset_env(void) { adapter_reset(); }
