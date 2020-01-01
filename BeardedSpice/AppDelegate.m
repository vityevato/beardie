//
//  AppDelegate.m
//  BeardedSpice
//
//  Created by Tyler Rhodes on 12/8/13.
//  Copyright (c) 2013 Tyler Rhodes / Jose Falcon. All rights reserved.
//

#include <IOKit/hidsystem/ev_keymap.h>

#import "AppDelegate.h"

#import "BSNativeAppTabAdapter.h"

#import "BSSharedResources.h"
#import "BeardedSpiceControllersProtocol.h"

#import "BSPreferencesWindowController.h"
#import "GeneralPreferencesViewController.h"
#import "ShortcutsPreferencesViewController.h"
#import "BSStrategiesPreferencesViewController.h"
#import "NSString+Utils.h"
#import "BSTimeout.h"

#import "BSActiveTab.h"

#import "BSStrategyCache.h"
#import "BSTrack.h"
#import "BSStrategyVersionManager.h"
#import "BSCustomStrategyManager.h"

#import "runningSBApplication.h"

#import "SPMediaKeyTap.h"
#import "BSVolumeWindowController.h"
#import "BSVolumeControlProtocol.h"

#import "BSBrowserExtensionsController.h"
#import "BSWebTabAdapter.h"
#import "BSNativeAppTabsController.h"

#define VOLUME_RELAXING_TIMEOUT             2 //seconds

typedef enum{

    SwithPlayerNext = 1,
    SwithPlayerPrevious

} SwithPlayerDirectionType;

BOOL accessibilityApiEnabled = NO;

@implementation AppDelegate {
    
    NSUInteger  statusMenuCount;
    NSStatusItem *statusItem;
    
    NSMutableArray *playingTabs;

    NSWindowController *_preferencesWindowController;
    
    NSMutableSet    *openedWindows;
    
    dispatch_queue_t workingQueue;
    
    NSXPCConnection *_connectionToService;
    
    BSBrowserExtensionsController *_browserExtensionsController;
    BSNativeAppTabsController *_nativeAppTabsController;
    
    BOOL _AXAPIEnabled;
    
    NSDate *_volumeButtonLastPressed;
}



- (void)dealloc{

    [self removeSystemEventsCallback];
}

/////////////////////////////////////////////////////////////////////////
#pragma mark Application Delegates
/////////////////////////////////////////////////////////////////////////

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification
{
//    // Insert code here to initialize your application
//    // Register defaults for the whitelist of apps that want to use media keys
//    NSMutableDictionary *registeredDefaults = [NSMutableDictionary dictionaryWithObjectsAndKeys:
//                        [SPMediaKeyTap defaultMediaKeyUserBundleIdentifiers], kMediaKeyUsingBundleIdentifiersDefaultsKey,
//                        nil];

    NSDictionary *appDefaults = [NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"BeardedSpiceUserDefaults" ofType:@"plist"]];
    if (appDefaults)
        [[NSUserDefaults standardUserDefaults] registerDefaults:appDefaults];

    // Create serial queue for user actions
    workingQueue = dispatch_queue_create("com.beardedspice.working.serial", DISPATCH_QUEUE_SERIAL);
    _volumeButtonLastPressed = [NSDate date];
    
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(interfaceThemeChanged:) name:@"AppleInterfaceThemeChangedNotification" object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(prefChanged:) name: BSStrategiesPreferencesNativeAppChangedNoticiation object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(prefChanged:) name: GeneralPreferencesAutoPauseChangedNoticiation object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(prefChanged:) name: GeneralPreferencesUsingAppleRemoteChangedNoticiation object:nil];

    [[NSNotificationCenter defaultCenter] addObserver: self selector:@selector(receivedWillCloseWindow:) name: NSWindowWillCloseNotification object:nil];

    [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];

    // Application notifications
    [self setupSystemEventsCallback];

    BSStrategyCache *strategyCache = [BSStrategyCache new];
    [strategyCache loadStrategies];

    self.versionManager = [[BSStrategyVersionManager alloc] initWithStrategyCache:strategyCache];

    self.activeApp = [BSActiveTab new];

    // setup default media strategy
    MediaStrategyRegistry *registry = [MediaStrategyRegistry singleton];
    [registry setUserDefaults:BeardedSpiceActiveControllers strategyCache:strategyCache];

    [self shortcutsBind];
    [self newConnectionToControlService];

#if !DEBUG_STRATEGY
    /* Check for strategy updates from the master github repo */
    if ([[NSUserDefaults standardUserDefaults] boolForKey:BeardedSpiceUpdateAtLaunch])
        [self checkForUpdates:self];
#endif
}

- (void)awakeFromNib
{
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:24.0];
    [statusItem setMenu:statusMenu];

    [self interfaceThemeChanged:nil];
    [statusItem setHighlightMode:YES];

    // Get initial count of menu items
    statusMenuCount = statusMenu.itemArray.count;

    // check accessibility enabled
    [self checkAccessibilityTrusted];

    [self resetStatusMenu:0];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    
    _nativeAppTabsController = BSNativeAppTabsController.singleton;
    _browserExtensionsController = BSBrowserExtensionsController.singleton;
    [_browserExtensionsController start];
    
    [self checkFirstRun];
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename{

    [[BSCustomStrategyManager singleton] importFromPath:filename];
    return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender{

    BSStrategyWebSocketServer *server = _browserExtensionsController.webSocketServer;
    if (server.started) {
        
        [server stopWithComletion:^{
            [sender terminate:self];
        }];
        return NSTerminateLater;
    }
    if (_connectionToService) {
        [[_connectionToService remoteObjectProxy] prepareForClosingConnectionWithCompletion:^{
            [self->_connectionToService invalidate];
            [sender replyToApplicationShouldTerminate:YES];
        }];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(COMMAND_EXEC_TIMEOUT * NSEC_PER_SEC)), workingQueue, ^{
            [self->_connectionToService invalidate];
            [sender replyToApplicationShouldTerminate:YES];
        });
        return NSTerminateLater;
    }
    
    return NSTerminateNow;
}

- (void)checkFirstRun {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:BeardedSpiceFirstRun]) {
        //when `first run` operations completed
        dispatch_block_t completion = ^(){[[NSUserDefaults standardUserDefaults] setBool:NO forKey:BeardedSpiceFirstRun];};
        
        dispatch_async(workingQueue, ^{
            [self->_browserExtensionsController firstRunPerformWithCompletion:completion];
        });
    }
}

/////////////////////////////////////////////////////////////////////////
#pragma mark Delegate methods
/////////////////////////////////////////////////////////////////////////

- (void)menuNeedsUpdate:(NSMenu *)menu{
    __weak typeof(self) wself = self;
    dispatch_async(workingQueue, ^{
        [wself autoSelectTabWithForceFocused:NO];

        dispatch_sync(dispatch_get_main_queue(), ^{
            [wself setStatusMenuItemsStatus];
        });
    });
}

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification {
    return YES;
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification{
    if ([kBSTrackNameIdentifier isEqualToString:notification.identifier]) {
        [self activatePlayingTab];
    }
}


/////////////////////////////////////////////////////////////////////////
#pragma mark BeardedSpiceHostAppProtocol methods
/////////////////////////////////////////////////////////////////////////

- (void)playPauseToggle {
    __weak typeof(self) wself = self;
    dispatch_async(workingQueue, ^{
        __strong typeof(wself) sself = self;
        [sself autoSelectTabWithForceFocused:YES];
        [sself.activeApp toggle];
    });
}
- (void)nextTrack {
    __weak typeof(self) wself = self;
    dispatch_async(workingQueue, ^{
        __strong typeof(wself) sself = self;
        [sself autoSelectTabWithForceFocused:NO];
        [sself.activeApp next];
    });
}

- (void)previousTrack {
    __weak typeof(self) wself = self;
    dispatch_async(workingQueue, ^{
        __strong typeof(wself) sself = self;
        [sself autoSelectTabWithForceFocused:NO];
        [sself.activeApp previous];
    });
}

- (void)favorite {
    __weak typeof(self) wself = self;
    dispatch_async(workingQueue, ^{
        __strong typeof(wself) sself = self;
        [sself autoSelectTabWithForceFocused:NO];
        [sself.activeApp favorite];
    });
}

- (void)activeTab {
    __weak typeof(self) wself = self;
    dispatch_async(workingQueue, ^{
        __strong typeof(wself) sself = self;
        [sself refreshTabs:self];
        [sself setActiveTabShortcut];
    });
}

- (void)notification{
    __weak typeof(self) wself = self;
    dispatch_async(workingQueue, ^{
        __strong typeof(wself) sself = self;
        [sself autoSelectTabWithForceFocused:NO];
        [sself.activeApp showNotificationUsingFallback:YES];
    });
}

- (void)activatePlayingTab{
    __weak typeof(self) wself = self;
    dispatch_async(workingQueue, ^{
        __strong typeof(wself) sself = self;
        [sself autoSelectTabWithForceFocused:NO];
        [sself.activeApp activatePlayingTab];
    });
}

- (void)playerNext{
    [self switchPlayerWithDirection:SwithPlayerNext];
}

- (void)playerPrevious{
    [self switchPlayerWithDirection:SwithPlayerPrevious];
}

- (void)volumeUp{
    
    __weak typeof(self) wself = self;
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:BeardedSpiceCustomVolumeControl]) {
        
        dispatch_async(workingQueue, ^{
            
            __strong typeof(wself) sself = self;
            [sself autoSelectTabForVolumeButtons];
            BSVolumeControlResult result = BSVolumeControlNotSupported;
            if ((result = [sself.activeApp volumeUp]) == BSVolumeControlNotSupported
                ) {
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(wself) sself = self;
                    [sself pressKey:NX_KEYTYPE_SOUND_UP];
                });
            }
            else {
                
                BSVWType vwType = [self convertVolumeResult:(BSVolumeControlResult)result];
                [[BSVolumeWindowController singleton] showWithType:vwType title:sself.activeApp.displayName];
            }
        });
    }
    else
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) sself = self;
            [sself pressKey:NX_KEYTYPE_SOUND_UP];
        });
}

- (void)volumeDown{
    
    __weak typeof(self) wself = self;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:BeardedSpiceCustomVolumeControl]) {
        
        dispatch_async(workingQueue, ^{
            
            __strong typeof(wself) sself = self;
            [sself autoSelectTabForVolumeButtons];
            BSVolumeControlResult result = BSVolumeControlNotSupported;
            if (
                (result = [sself.activeApp volumeDown]) == BSVolumeControlNotSupported
                ) {
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(wself) sself = self;
                    [sself pressKey:NX_KEYTYPE_SOUND_DOWN];
                });
            }
            else {
                
                BSVWType vwType = [self convertVolumeResult:(BSVolumeControlResult)result];
                [[BSVolumeWindowController singleton] showWithType:vwType title:sself.activeApp.displayName];
            }
        });
    }
    else
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) sself = self;
            [sself pressKey:NX_KEYTYPE_SOUND_DOWN];
        });
}

- (void)volumeMute{
    
    __weak typeof(self) wself = self;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:BeardedSpiceCustomVolumeControl]) {
        
        dispatch_async(workingQueue, ^{
            
            __strong typeof(wself) sself = self;
            [sself autoSelectTabForVolumeButtons];
            BSVolumeControlResult result = BSVolumeControlNotSupported;
            if (
                (result = [sself.activeApp volumeMute]) == BSVolumeControlNotSupported
                ) {
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(wself) sself = self;
                    [sself pressKey:NX_KEYTYPE_MUTE];
                });
            }
            else {
                
                BSVWType vwType = [self convertVolumeResult:(BSVolumeControlResult)result];
                [[BSVolumeWindowController singleton] showWithType:vwType title:sself.activeApp.displayName];
            }
        });
    }
    else
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) sself = self;
            [sself pressKey:NX_KEYTYPE_MUTE];
        });
}

- (void)headphoneUnplug{
    __weak typeof(self) wself = self;
    dispatch_async(workingQueue, ^{
        __strong typeof(wself) sself = self;
        [sself.activeApp pauseActiveTab];
    });
}

/////////////////////////////////////////////////////////////////////////
#pragma mark Actions
/////////////////////////////////////////////////////////////////////////

- (IBAction)checkForUpdates:(id)sender
{
    // MainMenu.xib has this menu item tag set as 256
    NSMenuItem *item = [statusMenu itemWithTag:256];
    // quietly exit because this shouldn't have happened...
    if (!item)
        return;

    statusMenu.autoenablesItems = NO;
    item.enabled = NO;
    item.title = BSLocalizedString(@"Checking...", @"Menu Titles");

    BOOL checkFromMenu = (sender != self);
    __weak typeof(self) wself = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,0), ^{
        __strong typeof(wself) sself = wself;

        NSUInteger updateCount = [sself.versionManager performSyncUpdateCheck];
        NSString *message = [NSString stringWithFormat:BSLocalizedString(@"There were %u compatibility updates.", @"Notification Titles"), updateCount];
        
        if (updateCount == 0){
            if (checkFromMenu) {
                [sself sendUpdateNotificationWithString:message];
            }
        }
        else
        {
            [sself refreshTabs:nil];
            [sself sendUpdateNotificationWithString:message];
        }

        dispatch_sync(dispatch_get_main_queue(), ^{
            item.title = BSLocalizedString(@"Check for Compatibility Updates", @"Menu Titles");
            item.enabled = YES;
        });
    });
}

- (IBAction)openPreferences:(id)sender
{
    [self windowWillBeVisible:self.preferencesWindowController.window];
    [self.preferencesWindowController showWindow:self];
}

- (IBAction)clickAboutFromStatusMenu:(id)sender {
    [NSApp orderFrontStandardAboutPanel:sender];
    [self windowWillBeVisible:NSApp.keyWindow];
}

- (IBAction)exitApp:(id)sender
{
    [NSApp terminate: nil];
}

- (void)updateActiveTabFromMenuItem:(id) sender
{
    __weak typeof(self) wself = self;
    dispatch_async(workingQueue, ^{
        __strong typeof(wself) sself = self;
        [sself.activeApp updateActiveTab:[sender representedObject]];
        dispatch_sync(dispatch_get_main_queue(), ^{
            [wself setStatusMenuItemsStatus];
        });
    });
}

/////////////////////////////////////////////////////////////////////
#pragma mark Windows control methods
/////////////////////////////////////////////////////////////////////

-(void)windowWillBeVisible:(id)window{

    if (window == nil)
        return;

    @synchronized(openedWindows) {

        if (!openedWindows)
            openedWindows = [NSMutableSet set];

        if (!openedWindows.count) {
            [[NSApplication sharedApplication] setActivationPolicy:NSApplicationActivationPolicyRegular];
        }
        [self activateApp];
        [openedWindows addObject:window];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSApplication sharedApplication] arrangeInFront:self];
        });
    }
}

-(void)activateApp {
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
}

-(void)removeWindow:(id)obj {

    if (obj == nil)
        return;

    @synchronized(openedWindows){

        [openedWindows removeObject:obj];
        if (![openedWindows count]){
            [[NSApplication sharedApplication] setActivationPolicy:NSApplicationActivationPolicyAccessory];
        }
    }
}

/////////////////////////////////////////////////////////////////////////
#pragma mark System Key Press Methods
/////////////////////////////////////////////////////////////////////////

- (void)pressKey:(NSUInteger)keytype {
    [self keyEvent:keytype state:0xA];  // key down
    [self keyEvent:keytype state:0xB];  // key up
}

- (void)keyEvent:(NSUInteger)keytype state:(NSUInteger)state {
    NSEvent *event = [NSEvent otherEventWithType:NSEventTypeSystemDefined
                                        location:NSZeroPoint
                                   modifierFlags:(state << 2)
                                       timestamp:0
                                    windowNumber:0
                                         context:nil
                                         subtype:0x8
                                           data1:(keytype << 16) | (state << 8)
                                           data2:SPPassthroughEventData2Value];

    CGEventPost(0, [event CGEvent]);
}

/////////////////////////////////////////////////////////////////////////
#pragma mark Helper methods
/////////////////////////////////////////////////////////////////////////

- (BOOL)setActiveTabShortcut{

    @try {
        NSArray <TabAdapter *> *tabs = _browserExtensionsController.webSocketServer.tabs;
        tabs = [tabs arrayByAddingObjectsFromArray:_nativeAppTabsController.tabs];

        for (TabAdapter *tab in tabs) {
            if (tab.frontmost) {
                return [_activeApp updateActiveTab:tab];
            }
        }

        return NO;
    } @catch (NSException *exception) {
        BSLog(BSLOG_ERROR, @"(%s) Exception occured: %@", __FUNCTION__, exception);
    }
}


-(BOOL)setStatusMenuItemsStatus{

    @autoreleasepool {
        NSInteger count = statusMenu.itemArray.count;
        for (int i = 0; i < (count - statusMenuCount); i++) {

            NSMenuItem *item = [statusMenu itemAtIndex:i];
            TabAdapter *tab = [item representedObject];
            BOOL isEqual = [_activeApp hasEqualTabAdapter:tab];

            [item setState:(isEqual ? NSControlStateValueOn : NSControlStateValueOff)];
        }

        return NO;
    }
}

// must be invoked not on main queue
- (void)refreshTabs:(id) sender
{
    NSLog(@"Refreshing tabs...");
    __weak typeof(self) wself = self;
    @autoreleasepool {
        
        NSMutableArray *newItems = [NSMutableArray array];
        
        playingTabs = [NSMutableArray array];
        
        if (accessibilityApiEnabled) {
            
            NSMutableArray <TabAdapter *> *tabs = [NSMutableArray new];
            [tabs addObjectsFromArray:_browserExtensionsController.webSocketServer.tabs];
            [tabs addObjectsFromArray:_nativeAppTabsController.tabs];
            
            for (TabAdapter *tab in tabs) {
                @try {
                    NSMenuItem *menuItem = [[NSMenuItem alloc]
                                            initWithTitle:[tab.title trimToLength:40]
                                            action:@selector(updateActiveTabFromMenuItem:)
                                            keyEquivalent:@""];
                    if (menuItem) {
                        
                        [newItems addObject:menuItem];
                        [menuItem setRepresentedObject:tab];
                        
                        if ([tab isPlaying])
                            [playingTabs addObject:tab];
                    }
                } @catch (NSException *exception) {
                    BSLog(BSLOG_ERROR, @"(%s) Exception occured: %@", __FUNCTION__, exception);
                }
            }
            if (![tabs containsObject:_activeApp.activeTab]) {
                _activeApp.activeTab = nil;
            }
        }
        
        dispatch_sync(dispatch_get_main_queue(), ^{
            [wself resetStatusMenu:newItems.count];
            
            if (newItems.count) {
                for (NSMenuItem *item in [newItems reverseObjectEnumerator]) {
                    [self->statusMenu insertItem:item atIndex:0];
                }
            }
        });
    }
}

// Must be invoked in workingQueue
- (void)autoSelectTabWithForceFocused:(BOOL)forceFocused{

    [self refreshTabs:self];

    switch (playingTabs.count) {

        case 1:

            [_activeApp updateActiveTab:playingTabs[0]];
            break;

        default: // null or many

            // try to set active tab to focus
            if ((forceFocused || !_activeApp) && [self setActiveTabShortcut]) {
                return;
            }

            if (_activeApp.activeTab == nil) {
                //try to set active tab to first item of menu
                TabAdapter *tab = [[statusMenu itemAtIndex:0] representedObject];
                if (tab)
                    [_activeApp updateActiveTab:tab];
            }
            break;
    }
}

- (void)checkAccessibilityTrusted{

    NSDictionary *options = @{CFBridgingRelease(kAXTrustedCheckOptionPrompt): @(YES)};
    accessibilityApiEnabled = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef _Nullable)(options));
    NSLog(@"AccessibilityApiEnabled %@", (accessibilityApiEnabled ? @"YES":@"NO"));

    if (!accessibilityApiEnabled) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(COMMAND_EXEC_TIMEOUT * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self checkAXAPIEnabled];
        });
    }
}

- (void)checkAXAPIEnabled{

    _AXAPIEnabled = AXIsProcessTrusted();
    NSLog(@"AXAPIEnabled %@", (_AXAPIEnabled ? @"YES":@"NO"));
    if (_AXAPIEnabled){
        NSAlert * alert = [NSAlert new];
        alert.alertStyle = NSAlertStyleCritical;
        alert.informativeText = BSLocalizedString(@"Once you enable access in System Preferences, you must restart BeardedSpice.", @"Explanation that we need to restart app");
        alert.messageText = BSLocalizedString(@"You must restart BeardedSpice.", @"Title that we need to restart app");
        [alert addButtonWithTitle:BSLocalizedString(@"Ok", @"Restart button")];

        [self windowWillBeVisible:alert];

        [alert runModal];

        [self removeWindow:alert];
    }
    else{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(COMMAND_EXEC_TIMEOUT * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self checkAXAPIEnabled];
        });
    }
}

- (void)setupSystemEventsCallback
{
    [[[NSWorkspace sharedWorkspace] notificationCenter]
     addObserver: self
     selector: @selector(receiveSleepNote:)
     name: NSWorkspaceWillSleepNotification object: NULL];

    [[[NSWorkspace sharedWorkspace] notificationCenter]
     addObserver:self
     selector:@selector(switchUserHandler:)
     name:NSWorkspaceSessionDidResignActiveNotification
     object:nil];
}

- (void)removeSystemEventsCallback{

    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
}

- (NSWindowController *)preferencesWindowController
{
    if (_preferencesWindowController == nil)
    {
        NSViewController *generalViewController = [GeneralPreferencesViewController new];
        NSViewController *shortcutsViewController = [ShortcutsPreferencesViewController new];
        NSViewController *strategiesViewController = [BSStrategiesPreferencesViewController new];
        NSArray *controllers = @[generalViewController, shortcutsViewController, strategiesViewController];

        NSString *title = BSLocalizedString(@"Preferences", @"Common title for Preferences window");
        _preferencesWindowController = [[BSPreferencesWindowController alloc] initWithViewControllers:controllers title:title];
    }
    return _preferencesWindowController;
}


- (void)switchPlayerWithDirection:(SwithPlayerDirectionType)direction {

    __weak typeof(self) wself = self;
    dispatch_async(workingQueue, ^{
        @autoreleasepool {

            [wself autoSelectTabWithForceFocused:YES];

            NSUInteger size = self->statusMenu.itemArray.count - self->statusMenuCount;
            if (size < 2) {
                return;
            }

            TabAdapter *tab = [[self->statusMenu itemAtIndex:0] representedObject];
            TabAdapter *prevTab = [[self->statusMenu itemAtIndex:(size - 1)] representedObject];
            TabAdapter *nextTab = [[self->statusMenu itemAtIndex:1] representedObject];

            for (int i = 0; i < size; i++) {
                if ([wself.activeApp hasEqualTabAdapter:tab]) {
                    if (direction == SwithPlayerNext) {
                        [wself.activeApp updateActiveTab:nextTab];
                    } else {
                        [wself.activeApp updateActiveTab:prevTab];
                    }

//                    [wself.activeApp activateTab];

                    NSUserNotification *notification = [NSUserNotification new];
                    notification.identifier = @"BSSwitchPlayerNotification";
                    notification.title = [wself.activeApp displayName];
                    notification.informativeText = [wself.activeApp title];

                    NSUserNotificationCenter *notifCenter = [NSUserNotificationCenter defaultUserNotificationCenter];
                    [notifCenter removeDeliveredNotification:notification];
                    [notifCenter deliverNotification:notification];

                    return;
                }
                prevTab = tab;
                tab = nextTab;
                nextTab = (i < (size - 2)) ? [[self->statusMenu itemAtIndex:(i + 2)] representedObject] : [[self->statusMenu itemAtIndex:0] representedObject];
            }
        }
    });
}

- (void)resetStatusMenu:(NSInteger)menuItemCount{

    NSInteger count = statusMenu.itemArray.count;
    for (int i = 0; i < (count - statusMenuCount); i++) {
        [statusMenu removeItemAtIndex:0];
    }

    if (!menuItemCount) {
        NSMenuItem *item = nil;
        if (accessibilityApiEnabled) {
             item = [statusMenu insertItemWithTitle:BSLocalizedString(@"No applicable tabs open", @"Title on empty menu")
                                                        action:nil
                                                 keyEquivalent:@""
                                                       atIndex:0];
        }
        else if (_AXAPIEnabled){

            item = [statusMenu insertItemWithTitle:BSLocalizedString(@"You must restart BeardedSpice", @"Title on empty menu")
                                                        action:nil
                                                 keyEquivalent:@""
                                                       atIndex:0];
        }
        else{

            item = [statusMenu insertItemWithTitle:BSLocalizedString(@"No access to control of the keyboard", @"Title on empty menu")
                                                        action:nil
                                                 keyEquivalent:@""
                                                       atIndex:0];
        }
        [item setEnabled:NO];
        [item setEnabled:NO];
    }


}

- (void)sendUpdateNotificationWithString:(NSString *)message
{
    NSUserNotification *notification = [NSUserNotification new];
    notification.title = BSLocalizedString(@"Compatibility Updates", @"Notification Titles");
    notification.subtitle = message;
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
}

- (BSVWType)convertVolumeResult:(BSVolumeControlResult)volumeResult {

    BSVWType result = BSVWUnavailable;
    
    switch (volumeResult) {
            
            case BSVolumeControlUp:
            result = BSVWUp;
            break;

            case BSVolumeControlDown:
            result = BSVWDown;
            break;
            
            case BSVolumeControlMute:
            result = BSVWMute;
            break;
            
            case BSVolumeControlUnmute:
            result = BSVWUnmute;
            break;
            
        default:
            break;
    }
    
    return result;
}

- (void)autoSelectTabForVolumeButtons {
    
    if ([_volumeButtonLastPressed timeIntervalSinceNow] * -1 >= VOLUME_RELAXING_TIMEOUT) {
        [self autoSelectTabWithForceFocused:NO];
    }
    _volumeButtonLastPressed = [NSDate date];
}
/////////////////////////////////////////////////////////////////////////
#pragma mark Notifications methods
/////////////////////////////////////////////////////////////////////////

- (void)receivedWillCloseWindow:(NSNotification *)theNotification{
    NSWindow *window = theNotification.object;
    [self removeWindow:window];
}

- (void)receiveSleepNote:(NSNotification *)note
{
    __weak typeof(self) wself = self;
    dispatch_async(workingQueue, ^{
        [wself.activeApp pauseActiveTab];
    });
}

- (void) switchUserHandler:(NSNotification*) notification
{
    __weak typeof(self) wself = self;
    dispatch_async(workingQueue, ^{
        [wself.activeApp pauseActiveTab];
    });
}

- (void) prefChanged:(NSNotification*) notification{

    NSString *name = notification.name;

    if ([name isEqualToString:GeneralPreferencesAutoPauseChangedNoticiation]) {

        [self setHeadphonesListener];
    }
    else if ([name isEqualToString:GeneralPreferencesUsingAppleRemoteChangedNoticiation]) {

        [self setAppleRemotes];
    }
    else if ([name isEqualToString:BSStrategiesPreferencesNativeAppChangedNoticiation])
        [self refreshKeyTapBlackList];
}

-(void)interfaceThemeChanged:(NSNotification *)notif
{
    @autoreleasepool {

        NSDictionary *dict = [[NSUserDefaults standardUserDefaults] persistentDomainForName:NSGlobalDomain];
        id style = [dict objectForKey:@"AppleInterfaceStyle"];
        BOOL isDarkMode = ( style && [style isKindOfClass:[NSString class]] && NSOrderedSame == [style caseInsensitiveCompare:@"dark"] );

        if (statusItem) {
            if (isDarkMode) {
                [statusItem setImage:[NSImage imageNamed:@"icon20x19-alt"]];
                [statusItem setAlternateImage:[NSImage imageNamed:@"icon20x19-alt"]];
            }
            else{
                [statusItem setImage:[NSImage imageNamed:@"icon20x19"]];
                [statusItem setAlternateImage:[NSImage imageNamed:@"icon20x19-alt"]];
            }
        }
    }
}

/////////////////////////////////////////////////////////////////////////
#pragma mark Shortcuts binding
/////////////////////////////////////////////////////////////////////////
- (void)shortcutsBind{

//    NSDictionary *options = @{NSValueTransformerNameBindingOption: NSKeyedUnarchiveFromDataTransformerName};
    NSDictionary *options = @{};

    [self bind:BeardedSpicePlayPauseShortcut
      toObject:[NSUserDefaultsController sharedUserDefaultsController]
   withKeyPath:[@"values." stringByAppendingString:BeardedSpicePlayPauseShortcut]
       options:options];

    [self bind:BeardedSpiceNextTrackShortcut
      toObject:[NSUserDefaultsController sharedUserDefaultsController]
   withKeyPath:[@"values." stringByAppendingString:BeardedSpiceNextTrackShortcut]
       options:options];

    [self bind:BeardedSpicePreviousTrackShortcut
      toObject:[NSUserDefaultsController sharedUserDefaultsController]
   withKeyPath:[@"values." stringByAppendingString:BeardedSpicePreviousTrackShortcut]
       options:options];

    [self bind:BeardedSpiceActiveTabShortcut
      toObject:[NSUserDefaultsController sharedUserDefaultsController]
   withKeyPath:[@"values." stringByAppendingString:BeardedSpiceActiveTabShortcut]
       options:options];

    [self bind:BeardedSpiceFavoriteShortcut
      toObject:[NSUserDefaultsController sharedUserDefaultsController]
   withKeyPath:[@"values." stringByAppendingString:BeardedSpiceFavoriteShortcut]
       options:options];

    [self bind:BeardedSpiceNotificationShortcut
      toObject:[NSUserDefaultsController sharedUserDefaultsController]
   withKeyPath:[@"values." stringByAppendingString:BeardedSpiceNotificationShortcut]
       options:options];

    [self bind:BeardedSpiceActivatePlayingTabShortcut
      toObject:[NSUserDefaultsController sharedUserDefaultsController]
   withKeyPath:[@"values." stringByAppendingString:BeardedSpiceActivatePlayingTabShortcut]
       options:options];

    [self bind:BeardedSpiceActivatePlayingTabShortcut
      toObject:[NSUserDefaultsController sharedUserDefaultsController]
   withKeyPath:[@"values." stringByAppendingString:BeardedSpiceActivatePlayingTabShortcut]
       options:options];

    [self bind:BeardedSpicePlayerNextShortcut
      toObject:[NSUserDefaultsController sharedUserDefaultsController]
   withKeyPath:[@"values." stringByAppendingString:BeardedSpicePlayerNextShortcut]
       options:options];

    [self bind:BeardedSpicePlayerPreviousShortcut
      toObject:[NSUserDefaultsController sharedUserDefaultsController]
   withKeyPath:[@"values." stringByAppendingString:BeardedSpicePlayerPreviousShortcut]
       options:options];
}

- (id)valueForUndefinedKey:(NSString *)key{

    return nil;
}

- (void)setBeardedSpicePlayPauseShortcut:(id)shortcut{

    if (_connectionToService) {
        [[_connectionToService remoteObjectProxy] setShortcuts:@{BeardedSpicePlayPauseShortcut: shortcut}];
    }
}
- (void)setBeardedSpiceNextTrackShortcut:(id)shortcut{

    if (_connectionToService) {
        [[_connectionToService remoteObjectProxy] setShortcuts:@{BeardedSpiceNextTrackShortcut: shortcut}];
    }
}
- (void)setBeardedSpicePreviousTrackShortcut:(id)shortcut{

    if (_connectionToService) {
        [[_connectionToService remoteObjectProxy] setShortcuts:@{BeardedSpicePreviousTrackShortcut: shortcut}];
    }
}
- (void)setBeardedSpiceActiveTabShortcut:(id)shortcut{

    if (_connectionToService) {
        [[_connectionToService remoteObjectProxy] setShortcuts:@{BeardedSpiceActiveTabShortcut: shortcut}];
    }
}
- (void)setBeardedSpiceFavoriteShortcut:(id)shortcut{

    if (_connectionToService) {
        [[_connectionToService remoteObjectProxy] setShortcuts:@{BeardedSpiceFavoriteShortcut: shortcut}];
    }
}
- (void)setBeardedSpiceNotificationShortcut:(id)shortcut{

    if (_connectionToService) {
        [[_connectionToService remoteObjectProxy] setShortcuts:@{BeardedSpiceNotificationShortcut: shortcut}];
    }
}
- (void)setBeardedSpiceActivatePlayingTabShortcut:(id)shortcut{

    if (_connectionToService) {
        [[_connectionToService remoteObjectProxy] setShortcuts:@{BeardedSpiceActivatePlayingTabShortcut: shortcut}];
    }
}
- (void)setBeardedSpicePlayerNextShortcut:(id)shortcut{

    if (_connectionToService) {
        [[_connectionToService remoteObjectProxy] setShortcuts:@{BeardedSpicePlayerNextShortcut: shortcut}];
    }
}
- (void)setBeardedSpicePlayerPreviousShortcut:(id)shortcut{

    if (_connectionToService) {
        [[_connectionToService remoteObjectProxy] setShortcuts:@{BeardedSpicePlayerPreviousShortcut: shortcut}];
    }
}

/////////////////////////////////////////////////////////////////////////
#pragma mark Controller Service methods
/////////////////////////////////////////////////////////////////////////

- (BOOL)newConnectionToControlService{

    if (_connectionToService) {
        [_connectionToService invalidate];
        _connectionToService = nil;
    }
     _connectionToService = [[NSXPCConnection alloc] initWithServiceName:BS_CONTROLLER_BUNDLE_ID];
     _connectionToService.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(BeardedSpiceControllersProtocol)];

    _connectionToService.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(BeardedSpiceHostAppProtocol)];
    _connectionToService.exportedObject = self;

    id __weak wSelf = self;
    _connectionToService.interruptionHandler = ^{
        [wSelf resetConnectionToControlService];
    };

    if (_connectionToService) {

        [_connectionToService resume];
        [self resetConnectionToControlService];

        return YES;
    }

    return NO;
}

- (void)resetConnectionToControlService{

    [self resetShortcutsToControlService];
    [self refreshKeyTapBlackList];
    [self setHeadphonesListener];
    [self setAppleRemotes];
}

- (void)resetShortcutsToControlService{

    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:9];

    NSData *shortcut  = [[NSUserDefaults standardUserDefaults] objectForKey:BeardedSpicePlayPauseShortcut];
    if (shortcut) {
        [dict setObject:shortcut forKey:BeardedSpicePlayPauseShortcut];
    }

    shortcut  = [[NSUserDefaults standardUserDefaults] objectForKey:BeardedSpiceNextTrackShortcut];
    if (shortcut) {
        [dict setObject:shortcut forKey:BeardedSpiceNextTrackShortcut];
    }

    shortcut  = [[NSUserDefaults standardUserDefaults] objectForKey:BeardedSpicePreviousTrackShortcut];
    if (shortcut) {
        [dict setObject:shortcut forKey:BeardedSpicePreviousTrackShortcut];
    }

    shortcut  = [[NSUserDefaults standardUserDefaults] objectForKey:BeardedSpiceActiveTabShortcut];
    if (shortcut) {
        [dict setObject:shortcut forKey:BeardedSpiceActiveTabShortcut];
    }

    shortcut  = [[NSUserDefaults standardUserDefaults] objectForKey:BeardedSpiceFavoriteShortcut];
    if (shortcut) {
        [dict setObject:shortcut forKey:BeardedSpiceFavoriteShortcut];
    }

    shortcut  = [[NSUserDefaults standardUserDefaults] objectForKey:BeardedSpiceNotificationShortcut];
    if (shortcut) {
        [dict setObject:shortcut forKey:BeardedSpiceNotificationShortcut];
    }

    shortcut  = [[NSUserDefaults standardUserDefaults] objectForKey:BeardedSpiceActivatePlayingTabShortcut];
    if (shortcut) {
        [dict setObject:shortcut forKey:BeardedSpiceActivatePlayingTabShortcut];
    }

    shortcut  = [[NSUserDefaults standardUserDefaults] objectForKey:BeardedSpicePlayerNextShortcut];
    if (shortcut) {
        [dict setObject:shortcut forKey:BeardedSpicePlayerNextShortcut];
    }

    shortcut  = [[NSUserDefaults standardUserDefaults] objectForKey:BeardedSpicePlayerPreviousShortcut];
    if (shortcut) {
        [dict setObject:shortcut forKey:BeardedSpicePlayerPreviousShortcut];
    }

    if (_connectionToService) {
        [[_connectionToService remoteObjectProxy] setShortcuts:dict];
    }
}

- (void)refreshKeyTapBlackList{

    NSMutableArray *keyTapBlackList = [NSMutableArray arrayWithCapacity:5];

    for (Class theClass in [NativeAppTabsRegistry.singleton enabledNativeAppClasses]) {
        [keyTapBlackList addObject:[theClass bundleId]];
    }
    [keyTapBlackList addObject:[[NSBundle mainBundle] bundleIdentifier]];

    if (_connectionToService) {

        [[_connectionToService remoteObjectProxy] setMediaKeysSupportedApps:keyTapBlackList];
    }
    NSLog(@"Refresh Key Tab Black List.");
}

- (void)setHeadphonesListener{

    if (_connectionToService) {
        [[_connectionToService remoteObjectProxy] setPhoneUnplugActionEnabled:[[NSUserDefaults standardUserDefaults] boolForKey:BeardedSpiceRemoveHeadphonesAutopause]];
    }
}

- (void)setAppleRemotes{

    if (_connectionToService) {
        [[_connectionToService remoteObjectProxy] setUsingAppleRemoteEnabled:[[NSUserDefaults standardUserDefaults] boolForKey:BeardedSpiceUsingAppleRemote]];
    }
}

@end
