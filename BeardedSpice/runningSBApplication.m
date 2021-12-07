//
//  runningApplication.m
//  BeardedSpice
//
//  Created by Roman Sokolov on 07.03.15.
//  Copyright (c) 2015 Tyler Rhodes / Jose Falcon. All rights reserved.
//

@import UserNotifications;

#import "runningSBApplication.h"
#import "EHSystemUtils.h"
#import "NSString+Utils.h"

#define COMMAND_TIMEOUT         3 // 3 second
#define RAISING_WINDOW_DELAY    0.1 //0.1 second

@implementation runningSBApplication {
    pid_t _processIdentifier;
    NSRunningApplication *_runningApplicationForActivate;
    NSCondition *_lockForActivate;
    
}

static NSMutableDictionary *_sharedAppHandler;
static NSRunningApplication *_frontmostApp = nil;
static AXUIElementRef _frontmostAppFocusedWindow = nil;
static BOOL _frontmostAppFocusedWindowFullScreen = NO;

+ (instancetype)sharedApplicationForBundleIdentifier:(NSString *)bundleIdentifier {
    
    if ([NSString isNullOrEmpty:bundleIdentifier]) {
        return nil;
    }
    
    @synchronized(self) {
        @autoreleasepool {
            
            if (_sharedAppHandler == nil) {
                _sharedAppHandler = [NSMutableDictionary dictionary];
            }
            runningSBApplication *app = _sharedAppHandler[bundleIdentifier];
            if (! app) {
                
                app = [[runningSBApplication alloc] initWithApplication:nil bundleIdentifier:bundleIdentifier];
                if ([app runningApplicationCreateFromBundleId:bundleIdentifier]) {
                    return app;
                }
            }
            else {
                BOOL result = (app->_processIdentifier && kill(app->_processIdentifier, 0) == 0);
                if (!result) {
                    DDLogDebug(@"sharedApplicationForBundleIdentifier 2 attempt: %@, %d", app->_bundleIdentifier, app->_processIdentifier);
                    result = [app runningApplication] != nil;
                }
                if (result) {
                    return app;
                }
                DDLogDebug(@"sharedApplicationForBundleIdentifier remove: %@, %d", app->_bundleIdentifier, app->_processIdentifier);
                [_sharedAppHandler removeObjectForKey:bundleIdentifier];
            }
            return nil;
        }
    }
}

- (BOOL)isFullscreenOtherCurrentFrontmost {
    
    NSRunningApplication *frontmostApp = [[NSWorkspace sharedWorkspace] frontmostApplication];
    if (frontmostApp == nil || [frontmostApp.bundleIdentifier isEqualToString:self.bundleIdentifier]) {
        return NO;
    }
    
    BOOL result = NO;
    AXUIElementRef ref = AXUIElementCreateApplication(frontmostApp.processIdentifier);
    
    if (ref) {
        
        AXUIElementRef window = nil;
        if (AXUIElementCopyAttributeValue(ref, (CFStringRef)NSAccessibilityFocusedWindowAttribute, (CFTypeRef *)&window) != kAXErrorSuccess
            || window == nil) {
            if (AXUIElementCopyAttributeValue(ref, (CFStringRef)NSAccessibilityMainWindowAttribute, (CFTypeRef *)&window) != kAXErrorSuccess ) {
                window = nil;
            }
        }
        if (window) {
            
            result = [runningSBApplication isFullscreenUIElementWindow:window];
            CFRelease(window);
        }
        else {
            DDLogDebug(@"Active app main window didn't obtain");
        }
        CFRelease(ref);
    }
    
    return  result;
}

- (instancetype)initWithApplication:(SBApplication *)application bundleIdentifier:(NSString *)bundleIdentifier{
    
    self = [super init];
    if (self) {
        
        _sbApplication = application;
        _bundleIdentifier = bundleIdentifier;
        _processIdentifier = 0;
        _lockForActivate = [NSCondition new];
        
        _sbApplication.timeout = COMMAND_TIMEOUT;
    }
    
    return self;
}

- (BOOL)frontmost{

    __block BOOL result = NO;
    [EHSystemUtils callOnMainQueue:^{
        
        NSRunningApplication *frontmostApp = [[NSWorkspace sharedWorkspace] frontmostApplication];
        result = [frontmostApp.bundleIdentifier isEqualToString:self.bundleIdentifier];
    }];
    
    return result;
}

- (pid_t)processIdentifier{
    
    return [[self runningApplication] processIdentifier];
}


- (BOOL)activateWithHoldFrontmost:(BOOL)hold {
    
    [self->_lockForActivate lock];
    [EHSystemUtils callOnMainQueue:^{
        if (hold || _frontmostApp == nil) {
            [self holdCurrentFrontmost];
        }
        self->_runningApplicationForActivate = [self runningApplication];
        [self->_runningApplicationForActivate addObserver:self
                                        forKeyPath:@"active"
                                           options:NSKeyValueObservingOptionNew context:NULL];
        self->_wasActivated = [self->_runningApplicationForActivate
                               activateWithOptions:(NSApplicationActivateIgnoringOtherApps | NSApplicationActivateAllWindows)];
    }];
    [self->_lockForActivate waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:COMMAND_TIMEOUT]];
    self->_wasActivated = self->_runningApplicationForActivate.active;
    [self->_runningApplicationForActivate removeObserver:self forKeyPath:@"active"];
    self->_runningApplicationForActivate = nil;
    [self->_lockForActivate unlock];
    return _wasActivated;
}

- (BOOL)hide{
    [self repairFrontmost];
    _wasActivated = NO;
    return YES;
}

- (void)makeKeyFrontmostWindow{

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(RAISING_WINDOW_DELAY * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        AXUIElementRef ref = AXUIElementCreateApplication(self.processIdentifier);
        
        if (ref) {
            
            CFIndex count = 0;
            CFArrayRef windowArray = NULL;
            AXError err = AXUIElementGetAttributeValueCount(ref, CFSTR("AXWindows"), &count);
            if (err == kAXErrorSuccess && count) {
                
                err = AXUIElementCopyAttributeValues(ref, CFSTR("AXWindows"), 0, count, &windowArray);
                if (err == kAXErrorSuccess && windowArray) {
                    
                    for ( CFIndex i = 0; i < count; i++){
                        
                        AXUIElementRef window = CFArrayGetValueAtIndex(windowArray, i);
                        if (window) {
                            
                            CFStringRef role;
                            err = AXUIElementCopyAttributeValue(window, CFSTR("AXRole"), (CFTypeRef *)&role);
                            if (err == kAXErrorSuccess && role){
                                
                                if (CFStringCompare(role, CFSTR("AXWindow"), 0) == kCFCompareEqualTo) {
                                
                                    CFStringRef subrole;
                                    err = AXUIElementCopyAttributeValue(window, CFSTR("AXSubrole"), (CFTypeRef *)&subrole);
                                    if (err == kAXErrorSuccess && subrole) {
                                        
                                        if (CFStringCompare(subrole, CFSTR("AXStandardWindow"), 0) == kCFCompareEqualTo) {
                                            AXUIElementPerformAction(window, CFSTR("AXRaise"));
                                            CFRelease(subrole);
                                            CFRelease(role);
                                            break;
                                        }
                                        
                                        CFRelease(subrole);
                                    }
                                }
                                CFRelease(role);
                            }
                        }
                        
                    }
                    
                    CFRelease(windowArray);
                }
            }
            CFRelease(ref);
        }
    });
}

/////////////////////////////////////////////////////////////////////////
#pragma mark Observing properties

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if ([object isEqual:self->_runningApplicationForActivate]) {
        [self->_lockForActivate lock];
        if ([keyPath isEqualToString:@"active"]) {
            NSNumber *val = change[NSKeyValueChangeNewKey];
            if (val && [val boolValue]) {
                DDLogDebug(@"Was activated: %@", self->_runningApplicationForActivate);
                [self->_lockForActivate broadcast];
            }
        }
        [self->_lockForActivate unlock];
    }
}

/////////////////////////////////////////////////////////////////////////
#pragma mark Supporting actions in application menubar

- (NSString *)menuBarItemNameForIndexPath:(NSIndexPath *)indexPath {
    
    AXUIElementRef menuItem = [self copyMenuBarItemForIndexPath:indexPath];
    
    NSString *name;
    if (menuItem) {
        
        CFTypeRef title;
        name = (AXUIElementCopyAttributeValue(menuItem, (CFStringRef) NSAccessibilityTitleAttribute, (CFTypeRef *)&title) == kAXErrorSuccess ?
                (NSString *)CFBridgingRelease(title): nil);
        
        CFRelease(menuItem);
    }
    
    return name;
}

- (BOOL)pressMenuBarItemForIndexPath:(NSIndexPath *)indexPath {
    
    if ([self isFullscreenOtherCurrentFrontmost]) {
        [self showFullscreenRestrictsNotification];
        return NO;
    }
    
    AXUIElementRef menuItem = [self copyMenuBarItemForIndexPath:indexPath];
    
    BOOL result = NO;
    if (menuItem) {
        result = (AXUIElementPerformAction(menuItem, (CFStringRef)NSAccessibilityPressAction) == kAXErrorSuccess);
        CFRelease(menuItem);
    }
    DDLogDebug(@"(pressMenuBarItemForIndexPath) Result: %@", (result ? @"YES" : @"NO"));

    return result;
}

/////////////////////////////////////////////////////////////////////////
#pragma mark Private methods

- (NSRunningApplication *)runningApplication{
    NSRunningApplication *result;
    if (self->_processIdentifier) {
        result = [NSRunningApplication runningApplicationWithProcessIdentifier:self->_processIdentifier];
    }
    else {
        return nil;
    }
    if (result == nil) {
        result = [self runningApplicationCreateFromBundleId:self->_bundleIdentifier];
    }
    return self->_processIdentifier ? [NSRunningApplication runningApplicationWithProcessIdentifier:self->_processIdentifier] : nil;
}

- (NSRunningApplication *)runningApplicationCreateFromBundleId:(NSString *)bundleIdentifier {
    @autoreleasepool {
        NSRunningApplication *runningApp = [[NSRunningApplication runningApplicationsWithBundleIdentifier:bundleIdentifier] firstObject];
        if (runningApp) {
            self->_processIdentifier = runningApp.processIdentifier;
            self->_sbApplication = [SBApplication applicationWithProcessIdentifier:self->_processIdentifier];
            _sharedAppHandler[bundleIdentifier] = self;
            DDLogDebug(@"runningApplicationCreateFromBundleId add: %@, %d", self->_bundleIdentifier, self->_processIdentifier);

            return runningApp;
        }
        return nil;
    }
}

- (AXUIElementRef)copyMenuBarItemForIndexPath:(NSIndexPath *)indexPath{
    
    if (! indexPath.length) {
        return nil;
    }

    AXUIElementRef item = nil;
    AXUIElementRef ref = AXUIElementCreateApplication(self.processIdentifier);
    
    if (ref) {
        
        CFIndex count = 0;
        CFArrayRef items = nil;
        AXUIElementRef menu = nil;
        BOOL notFound = NO;
        if (AXUIElementCopyAttributeValue(ref, (CFStringRef)NSAccessibilityMenuBarAttribute, (CFTypeRef *)&menu) == kAXErrorSuccess
            && menu) {
            
            item = CFRetain(menu);
            for (NSUInteger i = 0; i < indexPath.length && notFound == NO; i++) {

                //getting submenu if needs it
                if (i) {
                    
                    AXError error = AXUIElementCopyAttributeValues(item, (CFStringRef)NSAccessibilityChildrenAttribute, 0, 1, &items);
                    if (error == kAXErrorSuccess && items) {
                        
                        CFRelease(item);
                        item = CFRetain(CFArrayGetValueAtIndex(items, 0));
                        
                        CFRelease(items);
                    }
                    else {
                        notFound = YES;
                        break;
                    }
                }
                
                NSUInteger index = [indexPath indexAtPosition:i];
                if (AXUIElementGetAttributeValueCount(item, (CFStringRef)NSAccessibilityChildrenAttribute, &count) == kAXErrorSuccess
                    && count > index ) {
                    
                    //getting menu position
                    if (AXUIElementCopyAttributeValues(item, (CFStringRef)NSAccessibilityChildrenAttribute, index, 1, &items) == kAXErrorSuccess
                        && items) {
                        
                        CFRelease(item);
                        item = CFRetain(CFArrayGetValueAtIndex(items, 0));
                        
                        CFRelease(items);
                    }
                    else {
                        
                        notFound = YES;
                    }
                }
                else {
                    
                    notFound = YES;
                }
            }

            if (notFound) {
                
                CFRelease(item);
                item = nil;
            }
            CFRelease(menu);
        }
        
        CFRelease(ref);
    }
    
    return item;
}
- (void)holdCurrentFrontmost{
    
    if (_frontmostAppFocusedWindow) {
        CFRelease(_frontmostAppFocusedWindow);
        _frontmostAppFocusedWindow = nil;
    }
    
    _frontmostApp = [[NSWorkspace sharedWorkspace] frontmostApplication];
    if (_frontmostApp == nil) {
        return;
    }
    
    AXUIElementRef ref = AXUIElementCreateApplication(_frontmostApp.processIdentifier);
    
    if (ref) {
        
        AXUIElementRef window = nil;
        if (AXUIElementCopyAttributeValue(ref, (CFStringRef)NSAccessibilityFocusedWindowAttribute, (CFTypeRef *)&window) != kAXErrorSuccess
            || window == nil) {
            if (AXUIElementCopyAttributeValue(ref, (CFStringRef)NSAccessibilityMainWindowAttribute, (CFTypeRef *)&window) != kAXErrorSuccess ) {
                window = nil;
            }
        }
        if (window) {
            
            _frontmostAppFocusedWindow = window;
            _frontmostAppFocusedWindowFullScreen = [runningSBApplication isFullscreenUIElementWindow:_frontmostAppFocusedWindow];
            DDLogDebug(@"Active app main window obtained");
        }
        else {
            DDLogDebug(@"Active app main window didn't obtain");
        }
        CFRelease(ref);
    }
}

- (void)repairFrontmost {
    if (_frontmostApp) {
        if ([_frontmostApp activateWithOptions:(NSApplicationActivateIgnoringOtherApps | NSApplicationActivateAllWindows)]
            && _frontmostAppFocusedWindow) {
            AXUIElementPerformAction(_frontmostAppFocusedWindow, CFSTR("AXRaise"));
            CFRelease(_frontmostAppFocusedWindow);
            _frontmostAppFocusedWindow = nil;
            _frontmostAppFocusedWindowFullScreen = NO;
        }
        _frontmostApp = nil;
    }

}

+ (BOOL)isFullscreenUIElementWindow:(AXUIElementRef)window {
    
    BOOL result = NO;
    if (window) {
        
        CFTypeRef val;
        NSNumber *number;
        number = (AXUIElementCopyAttributeValue(window, CFSTR("AXFullScreen"), (CFTypeRef *)&val) == kAXErrorSuccess ?
                (NSNumber *)CFBridgingRelease(val): nil);
        result = number.boolValue;
    }
    DDLogDebug(@"isFullscreenUIElementWindow result: %@", result ? @"YES" : @"NO");
    return result;
}

- (BOOL)setFullscreenUIElementWindow:(AXUIElementRef)window value:(BOOL)value {
    
    if (window) {
        return AXUIElementSetAttributeValue(window, CFSTR("AXFullScreen"), (CFNumberRef)@(value)) == kAXErrorSuccess;
    }
    return NO;
}

- (void)showFullscreenRestrictsNotification {
    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    content.title = [NSString stringWithFormat:BSLocalizedString(@"warning-notification-ax-fullscreen-bug-title", @""),
                  [[self runningApplication] localizedName]];
    content.subtitle = BSLocalizedString(@"warning-notification-ax-fullscreen-bug-subtitle", @"");
    content.subtitle = BSLocalizedString(@"warning-notification-ax-fullscreen-bug-body", @"");
    content.sound = [UNNotificationSound defaultSound];
    content.threadIdentifier = @"critical-alert";
    UNTimeIntervalNotificationTrigger* trigger = [UNTimeIntervalNotificationTrigger
                triggerWithTimeInterval:0.05 repeats:NO];
    UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:@"critical-alert-ax-fullscreen"
                content:content trigger:trigger];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:nil];
}

- (BOOL)isEqual:(id)object{

    if (object == self)
        return YES;
    if ([object isKindOfClass:[self class]]
        && [_bundleIdentifier isEqualToString:[object bundleIdentifier]])
        return YES;

    return NO;
}

- (NSUInteger)hash
{
    return [_bundleIdentifier hash];
}

@end
