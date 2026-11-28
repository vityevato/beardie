// Copyright (c) 2026 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#import "adapter/reset.h"

#import <unistd.h>

#import "adapter/globals.h"
#import "adapter/now_playing.h"
#import "utility/helpers.h"

static NSString *firstClientBundleIdentifier(void);
static BOOL waitForElectedBundle(NSString *target, int timeoutMillis);

void adapter_reset(void) {
    if (g_mediaRemote.setNowPlayingApplicationOverrideEnabled == NULL) {
        fail(@"Resetting the now playing election is not supported on this "
             @"system");
    }

    // A previous helper may have died while it held the overridden
    // application. Taking the override over first is required before a fresh
    // process can clear it.
    NSString *takeover = firstClientBundleIdentifier();
    g_mediaRemote.setNowPlayingApplicationOverrideEnabled(true);

    if (takeover.length &&
        g_mediaRemote.setOverriddenNowPlayingApplication != NULL) {
        g_mediaRemote.setOverriddenNowPlayingApplication(
            (__bridge CFStringRef)takeover);
        waitForElectedBundle(takeover, 1000);
        g_mediaRemote.setOverriddenNowPlayingApplication(NULL);
        waitForElectedBundle(nil, 1000);
        usleep(150000);
    }

    g_mediaRemote.setNowPlayingApplicationOverrideEnabled(false);

    // Give the daemon a chance to process the calls before exiting.
    waitForCommandCompletion();
}

static NSString *firstClientBundleIdentifier(void) {
    if (g_mediaRemote.getNowPlayingClients == NULL ||
        g_mediaRemote.nowPlayingClientGetBundleIdentifier == NULL) {
        return nil;
    }

    __block NSArray *clients = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    g_mediaRemote.getNowPlayingClients(g_serialdispatchQueue, ^(NSArray *result) {
      clients = [result copy];
      dispatch_semaphore_signal(semaphore);
    });
    dispatch_time_t timeout =
        dispatch_time(DISPATCH_TIME_NOW, 1000 * NSEC_PER_MSEC);
    if (dispatch_semaphore_wait(semaphore, timeout) != 0) {
        return nil;
    }

    for (id client in clients) {
        NSString *parentBundle = nil;
        if ([client respondsToSelector:@selector(
                                       parentApplicationBundleIdentifier)]) {
            parentBundle = [client
                performSelector:@selector(parentApplicationBundleIdentifier)];
        }
        if (parentBundle.length) {
            return parentBundle;
        }
        NSString *bundle = (__bridge NSString *)
            g_mediaRemote.nowPlayingClientGetBundleIdentifier(client);
        if (bundle.length) {
            return bundle;
        }
    }
    return nil;
}

static BOOL waitForElectedBundle(NSString *target, int timeoutMillis) {
    dispatch_time_t deadline =
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)timeoutMillis * NSEC_PER_MSEC);
    while (dispatch_time(DISPATCH_TIME_NOW, 0) < deadline) {
        NSString *elected = mediaRemoteCurrentElectedBundleIdentifier();
        if (target.length == 0) {
            if (elected == nil) {
                return YES;
            }
        } else if ([elected isEqualToString:target]) {
            return YES;
        }
        usleep(20000);
    }
    return NO;
}

extern void adapter_reset_env(void) { adapter_reset(); }
