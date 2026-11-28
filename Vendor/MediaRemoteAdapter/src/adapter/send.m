// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#include "private/MediaRemote.h"
#include <limits.h>
#include <unistd.h>

#import <Foundation/Foundation.h>

#import "MediaRemoteAdapter.h"
#import "adapter/commands.h"
#import "adapter/env.h"
#import "adapter/globals.h"
#import "adapter/now_playing.h"
#import "utility/helpers.h"

#define SEND_TIMEOUT_MILLIS 2000

static void validateCommand(int command) {
    dispatch_group_t group = dispatch_group_create();

    __block NSArray *supportedCommands = nil;
    if (g_mediaRemote.copySupportedCommands) {
        dispatch_group_enter(group);
        g_mediaRemote.copySupportedCommands(
            g_serialdispatchQueue, ^(NSArray *commands) {
              supportedCommands = convertSupportedCommandsList(commands);
              dispatch_group_leave(group);
            });
    } else {
        printErr(@"Warning: Unable to verify whether the specified command is "
                 @"supported: This system does not support enumeration of "
                 @"supported commands. Continuing without validation");
        return;
    }

    dispatch_time_t timeout =
        dispatch_time(DISPATCH_TIME_NOW, SEND_TIMEOUT_MILLIS * NSEC_PER_MSEC);
    long waitResult = dispatch_group_wait(group, timeout);
    if (waitResult != 0) {
        printErrf(@"Warning: Validation of the specified command timed out "
                  @"after %d milliseconds. Continuing without validation",
                  SEND_TIMEOUT_MILLIS);
        return;
    }

    bool isSupported = false;
    bool isEnabled = false;
    NSString *commandName = nil;
    for (NSDictionary *supportedCommand in supportedCommands) {
        id identifier = [supportedCommand objectForKey:kMRACommand_Identifier];
        if (identifier == nil || ![identifier isKindOfClass:[NSNumber class]]) {
            continue;
        }
        if ([identifier intValue] != (int)command) {
            continue;
        }
        isSupported = true;
        id enabled = [supportedCommand objectForKey:kMRACommand_Enabled];
        if (enabled != nil && [enabled isKindOfClass:[NSNumber class]]) {
            isEnabled = [enabled boolValue];
        }
        id name = [supportedCommand objectForKey:kMRACommand_Name];
        if ([name isKindOfClass:[NSString class]]) {
            commandName = name;
        }
        break;
    }
    if (!isSupported) {
        failf(@"The specified command is not supported by the current "
              @"now playing application: %d",
              command);
    }
    if (!isEnabled) {
        failf(@"The specified command is disabled with the current now "
              @"playing application: %d%@",
              command,
              commandName ? [NSString stringWithFormat:@" (%@)", commandName]
                          : @"");
    }
}

void adapter_send(int command) {

    // TODO Allow sending a command to a specific application. That's definitely
    //  possible: https://github.com/ungive/mediaremote-adapter/issues/48
    // TODO Allow sending data/parameter values. What data can be sent though?
    //   A good number of real-world examples would be good to have.
    // TODO Can we get a success/failure result from MediaRemote?

    NSString *force_option = getEnvOption(@"force");
    const bool force = force_option != nil;

    if (!force) {
        validateCommand(command);
    }

    bool result = g_mediaRemote.sendCommand((MRCommand)command, nil);
    if (!result) {
        failf(@"Failed to send command %d", command);
    }

    waitForCommandCompletion();
}

static inline int send_0_command() {
    return getEnvFuncParamIntSafe(@"adapter_send", 0, @"command");
}

void adapter_send_env() { adapter_send(send_0_command()); }

// MARK: - Targeted transaction

#define TRANSACTION_DEFAULT_ELECTION_TIMEOUT_MILLIS 1000
#define TRANSACTION_DEFAULT_HOLD_MILLIS 250
#define TRANSACTION_POLL_INTERVAL_MICROS 20000

static NSString *normalizedBundle(NSString *bundle) {
    return [bundle stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]]
        .lowercaseString;
}

static BOOL electedBundleMatches(NSString *elected, NSString *target) {
    NSString *left = normalizedBundle(elected);
    NSString *right = normalizedBundle(target);
    if (left.length == 0 || right.length == 0) {
        return NO;
    }
    if ([left isEqualToString:right]) {
        return YES;
    }
    // A browser may expose its helper bundle as the client while the parent
    // application is the target. This function only runs when the parent was
    // not available, so strip a known helper suffix as a last resort.
    for (NSString *suffix in @[ @".helper", @".renderer", @".gpu", @".plugin" ]) {
        if ([left hasSuffix:suffix]) {
            return [[left stringByDeletingPathExtension] isEqualToString:right];
        }
    }
    return NO;
}

static BOOL waitForElection(NSString *bundleIdentifier,
                            int timeoutMillis) {
    dispatch_time_t deadline =
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)timeoutMillis * NSEC_PER_MSEC);
    while (dispatch_time(DISPATCH_TIME_NOW, 0) < deadline) {
        NSString *elected = mediaRemoteCurrentElectedBundleIdentifier();
        if (electedBundleMatches(elected, bundleIdentifier)) {
            return YES;
        }
        usleep(TRANSACTION_POLL_INTERVAL_MICROS);
    }
    return NO;
}

static void clearOverriddenApplication(void) {
    if (g_mediaRemote.setOverriddenNowPlayingApplication != NULL) {
        // Take the override over before clearing it so a helper that was
        // killed while holding it cannot leave the target behind.
        if (g_mediaRemote.setNowPlayingApplicationOverrideEnabled != NULL) {
            g_mediaRemote.setNowPlayingApplicationOverrideEnabled(true);
        }
        g_mediaRemote.setOverriddenNowPlayingApplication(NULL);
        // Let the daemon clear the target before the enabled flag changes.
        usleep(150000);
        if (g_mediaRemote.setNowPlayingApplicationOverrideEnabled != NULL) {
            g_mediaRemote.setNowPlayingApplicationOverrideEnabled(false);
        }
    }
}

static void emitTransactionResult(NSDictionary *result) {
    NSString *serialized = serializeJsonDictionarySafe(result, false);
    if (serialized != nil) {
        printOut(serialized);
    }
}

void adapter_transaction(NSString *bundleIdentifier, int command,
                         int electionTimeoutMillis, int holdMillis) {
    if (bundleIdentifier.length == 0) {
        fail(@"Missing target bundle identifier for the transaction");
    }
    if (g_mediaRemote.setOverriddenNowPlayingApplication == NULL) {
        fail(@"Targeted commands are not supported on this system");
    }
    if (g_mediaRemote.sendCommand == NULL) {
        fail(@"Sending MediaRemote commands is not supported on this system");
    }
    if (g_mediaRemote.getNowPlayingClient == NULL ||
        g_mediaRemote.nowPlayingClientGetBundleIdentifier == NULL) {
        fail(@"Reading the now playing application is not supported on this "
             @"system");
    }

    if (electionTimeoutMillis <= 0) {
        electionTimeoutMillis = TRANSACTION_DEFAULT_ELECTION_TIMEOUT_MILLIS;
    }
    if (holdMillis < 0) {
        holdMillis = TRANSACTION_DEFAULT_HOLD_MILLIS;
    }

    g_mediaRemote.setOverriddenNowPlayingApplication(
        (__bridge CFStringRef)bundleIdentifier);

    if (!waitForElection(bundleIdentifier, electionTimeoutMillis)) {
        NSString *elected = mediaRemoteCurrentElectedBundleIdentifier();
        clearOverriddenApplication();
        failf(@"The target application was not elected within %d "
              @"milliseconds (elected: %@)",
              electionTimeoutMillis, elected ?: @"none");
    }

    BOOL sent = g_mediaRemote.sendCommand((MRCommand)command, nil);
    if (!sent) {
        clearOverriddenApplication();
        failf(@"Failed to send command %d to %@", command, bundleIdentifier);
    }

    // Keep the override in place while the daemon delivers the command. The
    // election is restored as soon as the hold ends.
    if (holdMillis > 0) {
        usleep((useconds_t)holdMillis * 1000);
    }
    clearOverriddenApplication();

    // Give the daemon a chance to process the clear before exiting.
    waitForCommandCompletion();

    emitTransactionResult(@{
        @"target" : bundleIdentifier,
        @"command" : @(command),
        @"elected" : @YES,
        @"sent" : @YES,
    });
}

static int getEnvOptionIntSafe(NSString *name, int fallback) {
    NSNumber *value = getEnvOptionInt(name);
    return value != nil ? value.intValue : fallback;
}

void adapter_transaction_env(void) {
    NSString *bundleIdentifier = getEnvOption(@"bundle-id");
    int command = getEnvOptionIntSafe(@"command", INT_MIN);
    if (command == INT_MIN) {
        fail(@"Missing value for option 'command'");
    }
    int electionTimeoutMillis =
        getEnvOptionIntSafe(@"election-timeout",
                            TRANSACTION_DEFAULT_ELECTION_TIMEOUT_MILLIS);
    int holdMillis = getEnvOptionIntSafe(@"hold",
                                         TRANSACTION_DEFAULT_HOLD_MILLIS);
    adapter_transaction(bundleIdentifier, command, electionTimeoutMillis,
                        holdMillis);
}

void adapter_capabilities(void) {
    BOOL readsClients = g_mediaRemote.getNowPlayingClients != NULL &&
                        g_mediaRemote.getLocalOrigin != NULL &&
                        g_mediaRemote.nowPlayingPlayerPathCreate != NULL;
    BOOL targeted =
        g_mediaRemote.setOverriddenNowPlayingApplication != NULL &&
        g_mediaRemote.sendCommand != NULL &&
        g_mediaRemote.getNowPlayingClient != NULL &&
        g_mediaRemote.nowPlayingClientGetBundleIdentifier != NULL;
    BOOL supportedCommands = g_mediaRemote.getSupportedCommandsForPlayer != NULL;
    BOOL overrideSymbol =
        g_mediaRemote.setOverriddenNowPlayingApplication != NULL;
    emitTransactionResult(@{
        @"readClients" : @(readsClients),
        @"targetedCommands" : @(targeted),
        @"supportedCommands" : @(supportedCommands),
        @"electionOverride" : @(overrideSymbol),
    });
}
