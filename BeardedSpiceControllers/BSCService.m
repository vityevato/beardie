//
//  BSCService.m
//  BeardedSpice
//
//  Created by Roman Sokolov on 05.03.16.
//  Copyright © 2016  GPL v3 http://www.gnu.org/licenses/gpl.html
//

#import "BSCService.h"
#import "BSSharedResources.h"
#import "BeardedSpiceHostAppProtocol.h"
#import "BeardieControllers-Swift.h"

//#include <IOKit/hid/IOHIDUsageTables.h>

#import "SPMediaKeyTap.h"
#import "DDHidAppleMikey.h"

#import "EHSystemUtils.h"
#import "NSString+Utils.h"
#import "EHExecuteBlockDelayed.h"

#define MIKEY_REPEAT_TIMEOUT                0.6  //seconds
#define RCD_SERVICE_PLIST                   @"/System/Library/LaunchAgents/com.apple.rcd.plist"

@interface BSCService ()
- (void)handleShortcutAction:(BSShortcutAction)action;
@end

@implementation BSCService{

    SPMediaKeyTap *_keyTap;
    NSMutableArray *_mikeys;
    NSMutableArray *_appleRemotes;
    BSHeadphoneStatusListener *_hpuListener;

    NSMutableDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *_shortcuts;
    BSShortcutEventTap *_shortcutEventTap;

    BOOL _remoteControlDaemonEnabled;
    NSArray *_mediaKeysSupportedApps;

    dispatch_queue_t workingQueue;

    NSMutableArray *_connections;

    BOOL _enabled;
    BOOL _shortcutsRegistrationEnabled;

    EHExecuteBlockDelayed *_miKeyCommandBlock;
}

static BSCService *bscSingleton;

- (id)init{

    if (self == bscSingleton) {
        self = [super init];
        if (self) {

            [[NSUserDefaults standardUserDefaults] registerDefaults:@{kMediaKeyUsingBundleIdentifiersDefaultsKey: [SPMediaKeyTap defaultMediaKeyUserBundleIdentifiers]}];
            
            _connections = [NSMutableArray arrayWithCapacity:1];
            _shortcuts = [NSMutableDictionary dictionary];
            _shortcutsRegistrationEnabled = YES;
            _remoteControlDaemonEnabled = NO;

            _shortcutEventTap = [BSShortcutEventTap new];
            __weak typeof(self) weakSelf = self;
            _shortcutEventTap.actionHandler = ^(BSShortcutAction action) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf handleShortcutAction:action];
                });
            };

            workingQueue = dispatch_queue_create("BeardedSpiceControllerService", DISPATCH_QUEUE_SERIAL);

            _hpuListener = [[BSHeadphoneStatusListener alloc] initWithDelegate:self listenerQueue:workingQueue];
            _keyTap = [[SPMediaKeyTap alloc] initWithDelegate:self];


            // System notifications
            [[[NSWorkspace sharedWorkspace] notificationCenter]
             addObserver: self
             selector: @selector(refreshAllControllers:)
             name: NSWorkspaceScreensDidWakeNotification
             object: NULL];

            NSDistributedNotificationCenter *center = [NSDistributedNotificationCenter defaultCenter];
            [center
             addObserver: self
             selector: @selector(refreshAllControllers:)
             name: @"com.apple.screenIsUnlocked"
             object: NULL];

            [center
             addObserver: self
             selector: @selector(refreshAllControllers:)
             name: @"com.apple.screensaver.didstop"
             object: NULL];
            //--------------------------------------------

        }
        return self;
    }

    return nil;
}

+ (BSCService *)singleton{

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{

        bscSingleton = [BSCService alloc];
        bscSingleton = [bscSingleton init];
    });

    return bscSingleton;
}

#pragma mark - Public Methods

- (void)setShortcuts:(NSDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *)shortcuts{

    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {

            self->_shortcuts = shortcuts ? [shortcuts mutableCopy] : [NSMutableDictionary dictionary];
            [self refreshShortcutMonitor];
        }
    });
}

- (void)setShortcutsRegistrationEnabled:(BOOL)enabled{

    dispatch_async(dispatch_get_main_queue(), ^{
        self->_shortcutsRegistrationEnabled = enabled;
        [self refreshShortcutMonitor];
    });
}

- (void)setMediaKeysSupportedApps:(NSArray <NSString *>*)bundleIds{
    dispatch_async(dispatch_get_main_queue(), ^{

        self->_keyTap.blackListBundleIdentifiers = [bundleIds copy];
        DDLogDebug(@"Refresh Key Tab Black List.");
    });
}

- (void)setPhoneUnplugActionEnabled:(BOOL)enabled{

    dispatch_async(dispatch_get_main_queue(), ^{
        self->_hpuListener.enabled = enabled;
    });
}

- (BOOL)addConnection:(NSXPCConnection *)connection{
    dispatch_sync(dispatch_get_main_queue(), ^{

        if (connection) {
            if (!_enabled) {
                _enabled = YES;
                // A previous app session may have ended while a recorder was
                // active. Recording state is per-session, so start enabled.
                _shortcutsRegistrationEnabled = YES;
                [self rcdControl];
                [self refreshShortcutMonitor];

                // Media keys need an event tap and may be unavailable without
                // Accessibility/Input Monitoring permission. Global shortcuts
                // use Carbon hot keys and must keep working in that case.
                if ([self refreshAllControllers:nil] == NO) {
                    DDLogError(@"Media keys are unavailable; continuing with global shortcuts only");
                }
            }
            [_connections addObject:connection];
        }
    });
    return _enabled;
}
- (void)removeConnection:(NSXPCConnection *)connection{
    dispatch_sync(dispatch_get_main_queue(), ^{

        if (connection) {
            [_connections removeObject:connection];
            if (!_connections.count && _enabled) {
                _enabled = NO;
                _shortcutsRegistrationEnabled = YES;
                [self rcdControl];
                [self refreshShortcutMonitor];
                [self refreshAllControllers:nil];
            }
        }
    });
}


#pragma mark - Events Handlers

// Performs Pause method
- (void)headphoneUnplugAction{
    DDLogDebug(@"headphoneUnplugAction");
    [self sendMessagesToConnections:@selector(headphoneUnplug) object:nil];
}

- (void)headphonePlugAction
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DDLogDebug(@"headphonePlugAction");
        [self refreshMikeys];
    });
}

-(void)mediaKeyTap:(SPMediaKeyTap*)keyTap receivedMediaKeyEvent:(NSEvent*)event;
{
    NSAssert([event type] == NSEventTypeSystemDefined && [event subtype] == SPSystemDefinedEventMediaKeys, @"Unexpected NSEvent in mediaKeyTap:receivedMediaKeyEvent:");
    // here be dragons...
    int keyCode = (([event data1] & 0xFFFF0000) >> 16);
    int keyFlags = ([event data1] & 0x0000FFFF);
    BOOL keyIsPressed = (((keyFlags & 0xFF00) >> 8)) == 0xA;
    int keyRepeat = (keyFlags & 0x1);

    BS_XPCEvent *xpcEvent = [[BS_XPCEvent alloc] initWithModifierFlags:event.modifierFlags
                                                                 data1:event.data1
                                                                 data2:event.data2
                                                            keyPressed:keyIsPressed];
    NSString *debugString = @"";
    if (keyIsPressed) {
        
        debugString = [NSString stringWithFormat:@"%@", keyRepeat?@", repeated.":@"."];
        switch (keyCode) {
            case NX_KEYTYPE_PLAY:
                debugString = [@"Play/pause pressed" stringByAppendingString:debugString];
                [self sendMessagesToConnections:@selector(playPauseToggle) object:nil];
                break;
            case NX_KEYTYPE_FAST:
            case NX_KEYTYPE_NEXT:
                debugString = [@"Ffwd pressed" stringByAppendingString:debugString];
                [self sendMessagesToConnections:@selector(nextTrack) object:nil];
                break;
            case NX_KEYTYPE_REWIND:
            case NX_KEYTYPE_PREVIOUS:
                debugString = [@"Rewind pressed" stringByAppendingString:debugString];
                [self sendMessagesToConnections:@selector(previousTrack) object:nil];
                break;
            case NX_KEYTYPE_SOUND_UP:
                debugString = [@"Sound Up pressed" stringByAppendingString:debugString];
                [self sendMessagesToConnections:@selector(volumeUp:) object:xpcEvent];
                break;
            case NX_KEYTYPE_SOUND_DOWN:
                debugString = [@"Sound Down pressed" stringByAppendingString:debugString];
                [self sendMessagesToConnections:@selector(volumeDown:) object:xpcEvent];
                break;
            case NX_KEYTYPE_MUTE:
                debugString = [@"Sound Mute pressed" stringByAppendingString:debugString];
                [self sendMessagesToConnections:@selector(volumeMute:) object:xpcEvent];
                break;
            default:
                debugString = [NSString stringWithFormat:@"Key %d pressed%@", keyCode, debugString];
                break;
                // More cases defined in hidsystem/ev_keymap.h
        }
    }
    else {
        switch (keyCode) {
            case NX_KEYTYPE_SOUND_UP:
                debugString = @"Sound Up unpressed";
                [self sendMessagesToConnections:@selector(volumeUp:) object:xpcEvent];
                break;
            case NX_KEYTYPE_SOUND_DOWN:
                debugString = @"Sound Down unpressed";
                [self sendMessagesToConnections:@selector(volumeDown:) object:xpcEvent];
                break;
            case NX_KEYTYPE_MUTE:
                debugString = @"Sound Mute unpressed";
                [self sendMessagesToConnections:@selector(volumeMute:) object:xpcEvent];
                break;
            default:
                debugString = [NSString stringWithFormat:@"Key %d unpressed", keyCode];
                break;
                // More cases defined in hidsystem/ev_keymap.h
        }
        
    }
    DDLogDebug(@"%@", debugString);
}

- (void) ddhidAppleMikey:(DDHidAppleMikey *)mikey press:(unsigned)usageId upOrDown:(BOOL)upOrDown
{
#if DEBUG
    DDLogDebug(@"Apple Mikey keypress detected: x%X", usageId);
#endif
    if (upOrDown == TRUE) {
        switch (usageId) {
            case kHIDUsage_GD_SystemMenu:
                [self sendMessagesToConnections:@selector(playPauseToggle) object:nil];
                break;
            case kHIDUsage_GD_SystemMenuRight:
                [self sendMessagesToConnections:@selector(nextTrack) object:nil];
                break;
            case kHIDUsage_GD_SystemMenuLeft:
                [self sendMessagesToConnections:@selector(previousTrack) object:nil];
                break;
            case kHIDUsage_GD_SystemMenuUp:
            case kHIDUsage_Csmr_VolumeIncrement:
                [self sendMessagesToConnections:@selector(volumeUp:) object:nil];
                break;
            case kHIDUsage_GD_SystemMenuDown:
            case kHIDUsage_Csmr_VolumeDecrement:
                [self sendMessagesToConnections:@selector(volumeDown:) object:nil];
                break;
            case kHIDUsage_Csmr_PlayOrPause:
                [self catchCommandFromMiKeys];
            default:
                DDLogDebug(@"Unknown key press seen x%X", usageId);
        }
    }
}

#pragma mark - Private Methods

- (BOOL)refreshMediaKeys{

    __block BOOL result = YES;
    [EHSystemUtils callOnMainQueue:^{
        if (self->_enabled) {
            result = [self->_keyTap startWatchingMediaKeys];
        }
        else {
            [self->_keyTap stopWatchingMediaKeys];
        }
    }];

    return result;
}

- (void)catchCommandFromMiKeys {
    static NSInteger counter = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _miKeyCommandBlock  = [[EHExecuteBlockDelayed alloc]
                               initWithTimeout:MIKEY_REPEAT_TIMEOUT
                               leeway:MIKEY_REPEAT_TIMEOUT
                               queue:workingQueue
                               block:^{
                                   switch (counter) {
                                       case 1:
                                           [self sendMessagesToConnections:@selector(playPauseToggle) object:nil];
                                           break;
                                           
                                       case 2:
                                           [self sendMessagesToConnections:@selector(nextTrack) object:nil];
                                           break;
                                           
                                       case 3:
                                           [self sendMessagesToConnections:@selector(previousTrack) object:nil];
                                           break;

                                       default:
                                           break;
                                   }
                                   DDLogDebug(@"%s - Comman Block Running (%ld)", __FUNCTION__, counter);
                                   counter = 0;
                               }];
    });
    
    counter++;
    DDLogDebug(@"%s - counter: %ld", __FUNCTION__, counter);
    [_miKeyCommandBlock executeOnceAfterCalm];
}

- (void)refreshMikeys
{
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {

            DDLogDebug(@"Reset Mikeys");

            if (self->_mikeys != nil) {
                @try {
                    [self->_mikeys makeObjectsPerformSelector:@selector(stopListening)];
                }
                @catch (NSException *exception) {
                    DDLogError(@"Error when stopListening on Apple Mic: %@", exception);
                }
            }

            if (self->_enabled) {
                @try {
                    NSArray *mikeys = [DDHidAppleMikey allMikeys];
                    self->_mikeys = [NSMutableArray arrayWithCapacity:mikeys.count];
                    for (DDHidAppleMikey *item in mikeys) {

                        @try {

                            [item setDelegate:self];
                            [item setListenInExclusiveMode:YES];
                            [item startListening];

                            [self->_mikeys addObject:item];
#if DEBUG
                            DDLogDebug(@"Apple Mic added - %@", item);
#endif
                        }
                        @catch (NSException *exception) {

                            DDLogError(@"Error when startListening on Apple Mic: %@, exception: %@", item, exception);
                        }
                    }
                }
                @catch (NSException *exception) {
                    DDLogError(@"Error of the obtaining Apple Mic divices: %@", [exception description]);
                }
            }
        }
    });
}

- (void)refreshShortcutMonitor{

    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {

            BOOL registrationEnabled = self->_enabled && self->_shortcutsRegistrationEnabled;
            [self->_shortcutEventTap setEnabled:registrationEnabled];
            [self->_shortcutEventTap updateShortcuts:[self->_shortcuts copy]];

            DDLogDebug(@"Shortcut event tap active: %@, actions: %lu",
                       self->_shortcutEventTap.isActive ? @"YES" : @"NO",
                       (unsigned long)self->_shortcuts.count);
        }
    });
}

- (void)handleShortcutAction:(BSShortcutAction)action{

    DDLogDebug(@"Shortcut action: %ld", (long)action);

    switch (action) {
        case BSShortcutActionPlayPause:
            [self sendMessagesToConnections:@selector(playPauseToggle) object:nil];
            break;

        case BSShortcutActionNextTrack:
            [self sendMessagesToConnections:@selector(nextTrack) object:nil];
            break;

        case BSShortcutActionPreviousTrack:
            [self sendMessagesToConnections:@selector(previousTrack) object:nil];
            break;

        case BSShortcutActionActiveTab:
            [self refreshMediaKeys];
            [self sendMessagesToConnections:@selector(activeTab) object:nil];
            break;

        case BSShortcutActionFavorite:
            [self sendMessagesToConnections:@selector(favorite) object:nil];
            break;

        case BSShortcutActionNotification:
            [self refreshMediaKeys];
            [self sendMessagesToConnections:@selector(notification) object:nil];
            break;

        case BSShortcutActionActivatePlayingTab:
            [self refreshMediaKeys];
            [self sendMessagesToConnections:@selector(activatePlayingTab) object:nil];
            break;

        case BSShortcutActionPlayerNext:
            [self refreshMediaKeys];
            [self sendMessagesToConnections:@selector(playerNext) object:nil];
            break;

        case BSShortcutActionPlayerPrevious:
            [self refreshMediaKeys];
            [self sendMessagesToConnections:@selector(playerPrevious) object:nil];
            break;
    }
}

- (void)sendMessagesToConnections:(SEL)selector object:(id)object{

    dispatch_async(workingQueue, ^{
        @autoreleasepool {

            for (NSXPCConnection *conn in self->_connections) {

                id<BeardedSpiceHostAppProtocol, NSObject> obj = [conn remoteObjectProxy];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                if (object) {
                    [obj performSelector:selector withObject:object];
                }
                else {
                    [obj performSelector:selector];
                }
#pragma clang diagnostic pop
            }
        }
    });
}

- (void)rcdControl{

    if (_enabled) {
        DDLogDebug(@"rcdControl enabled");
        //checking that rcd is enabled and disabling it
        NSString *cliOutput = NULL;
        if ([EHSystemUtils cliUtil:@"/bin/launchctl" arguments:@[@"list"] output:&cliOutput] == 0) {
            _remoteControlDaemonEnabled = ( [cliOutput contains:@"com.apple.rcd" caseSensitive:YES]);
            if (_remoteControlDaemonEnabled) {
                _remoteControlDaemonEnabled = ([EHSystemUtils cliUtil:@"/bin/launchctl" arguments:@[@"unload", RCD_SERVICE_PLIST] output:&cliOutput] == 0
                                               && [cliOutput containsString:@"error"] == NO);
                DDLogDebug(@"rcdControl unload result: %@", (_remoteControlDaemonEnabled ? @"YES" : @"NO"));
            }
        }
    }
    else{

        DDLogDebug(@"rcdControl disable");
        if (_remoteControlDaemonEnabled) {
            DDLogDebug(@"rcdControl load");
            [EHSystemUtils cliUtil:@"/bin/launchctl" arguments:@[@"load", RCD_SERVICE_PLIST] output:nil];
        }
    }

}

#pragma mark - Notifications

/**
 Method reloads: media keys, apple remote, headphones remote.
 */
- (BOOL)refreshAllControllers:(NSNotification *)note
{
    [self refreshMikeys];
    if ([self refreshMediaKeys] == NO) {
        return NO;
    }
    return YES;
}

@end
