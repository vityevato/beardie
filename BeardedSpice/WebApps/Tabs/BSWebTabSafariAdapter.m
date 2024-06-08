//
//  BSWebTabSafariAdapter.m
//  BeardedSpice
//
//  Created by Roman Sokolov on 13/10/2019.
//  Copyright © 2019  GPL v3 http://www.gnu.org/licenses/gpl.html
//

#import "BSWebTabSafariAdapter.h"
#import "runningSBApplication.h"
#import "EHSystemUtils.h"

#define AX_REPAIR_TIMEOUT       0.6 // 0.6 seconds

@implementation BSWebTabSafariAdapter {
    AXUIElementRef _window;
    NSString *_windowId;
}

static NSSet *_safariBundleIds;

/////////////////////////////////////////////////////////////////////////
#pragma mark Public methods

- (instancetype)init {
    self = [super init];
    if (self) {
        _window = nil;
    }
    return self;
}

- (BOOL)suitableForSocket {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _safariBundleIds = [NSSet setWithArray:@[BS_DEFAULT_SAFARI_BUBDLE_ID, BS_SAFARI_TECHPREVIEW_ID]];
    });
    @autoreleasepool {
        runningSBApplication *app = self.application;
        
        if (app.bundleIdentifier && [_safariBundleIds containsObject:app.bundleIdentifier]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)activateTab {
    NSDictionary *response = [self sendMessage:@"activate"];
    
    return [self tabResponseProcessing:response];
}

- (BOOL)deactivateTab {
    if ([self frontmost]) {
        DDLogDebug(@"frontmost");
        if ([self isActivated]) {
            DDLogDebug(@"activated");
            NSDictionary *response = [self sendMessage:@"hide"];
            return [self tabResponseProcessing:response];
        }
    }
    return NO;
}

#pragma mark Private methods

- (BOOL)tabResponseProcessing:(NSDictionary *)response {
    
    BOOL result = [response[@"result"] boolValue];
    if (result) {
        result = [self windowMakefrontmostIfNeedFromResponse:response];
        if (result == NO) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)(AX_REPAIR_TIMEOUT * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [self windowMakefrontmostIfNeedFromResponse:response];
            });
            result = YES;
        }
    }
    return result;
}

- (BOOL)windowMakefrontmostIfNeedFromResponse:(__unsafe_unretained NSDictionary *)response {
    if (response && [response isKindOfClass:[NSDictionary class]]) {
        AXUIElementRef window = nil;
        NSString *windowId = response[@"windowIdForMakeFrontmost"];
        if (windowId) {
            
            if (_window) {
                if ([_windowId isEqualToString:windowId]) {
                    window = _window;
                    DDLogDebug(@"Using saved window ref for: %@", windowId);
                }
                else {
                    _windowId = nil;
                    CFRelease(_window);
                    _window = nil;
                }
            }
            
            // gettting new window ref
            if (window == nil) {
                
                NSArray *variants = @[
                    [NSString stringWithFormat:@"SafariWindow?UsingUnifiedBar=false&UUID=%@", windowId],
                    windowId
                ];
                DDLogDebug(@"List of variants: %@", variants);
                for (NSString *item in variants) {
                    
                    window = [self AXWindowByIdentifier:item];
                    if (window) {
                        _window = window;
                        _windowId = windowId;
                        DDLogDebug(@"New window obtained: %p", window);
                        break;
                    }
                }
            }
            
            if (window) {
                AXUIElementPerformAction(window, CFSTR("AXRaise"));
                DDLogDebug(@"Window raised: %p", window);
                return YES;
            }
        }
    }
    return NO;
}


- (AXUIElementRef)AXWindowByIdentifier:(__unsafe_unretained NSString *)windowId{
    
    AXUIElementRef ref = AXUIElementCreateApplication(self.application.processIdentifier);
    AXUIElementRef result = NULL;
    if (ref) {

        DDLogDebug(@"(AXWindowByIdentifier) ref obtained");
        
        // search through windows list
        CFIndex count = 0;
        CFArrayRef windowArray = NULL;
        AXError err = AXUIElementGetAttributeValueCount(ref, CFSTR("AXWindows"), &count);
        if (err == kAXErrorSuccess && count) {

            DDLogDebug(@"(AXWindowByIdentifier) Safari windows count: %ld", (long)count);
            err = AXUIElementCopyAttributeValues(ref, CFSTR("AXWindows"), 0, count, &windowArray);
            if (err == kAXErrorSuccess && windowArray) {

                DDLogDebug(@"(AXWindowByIdentifier) Safari windows array obtained");
                for ( CFIndex i = 0; i < count; i++){
                    
                    AXUIElementRef window = CFArrayGetValueAtIndex(windowArray, i);
                    if (window) {

                        DDLogDebug(@"(AXWindowByIdentifier) Safari window obtained for index: %ld", (long)i);
                        CFStringRef role;
                        err = AXUIElementCopyAttributeValue(window, CFSTR("AXRole"), (CFTypeRef *)&role);
                        if (err == kAXErrorSuccess && role){
                            
                            if (CFStringCompare(role, CFSTR("AXWindow"), 0) == kCFCompareEqualTo) {
                                
                                DDLogDebug(@"(AXWindowByIdentifier) Safari window role AXWindow for index: %ld", (long)i);
                                CFStringRef subrole;
                                err = AXUIElementCopyAttributeValue(window, CFSTR("AXSubrole"), (CFTypeRef *)&subrole);
                                if (err == kAXErrorSuccess && subrole) {
                                    if ([self checkIdentifier:windowId window:window]) {
                                        result = window;
                                        CFRetain(result);
                                        
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
        if (result == nil) {
            // search in focused and main window
            AXUIElementRef window = nil;
            if (AXUIElementCopyAttributeValue(ref, (CFStringRef)NSAccessibilityFocusedWindowAttribute, (CFTypeRef *)&window) != kAXErrorSuccess
                || window == nil) {
                if (AXUIElementCopyAttributeValue(ref, (CFStringRef)NSAccessibilityMainWindowAttribute, (CFTypeRef *)&window) != kAXErrorSuccess ) {
                    window = nil;
                }
            }
            if (window) {
                if ([self checkIdentifier:windowId window:window]) {
                    result = window;
                    CFRetain(result);
                }
                CFRelease(window);
            }
        }
        
        CFRelease(ref);
    }
    return result;
}

- (BOOL)checkIdentifier:(__unsafe_unretained NSString *)windowId window:(AXUIElementRef)window {
    
    BOOL result = NO;
    CFStringRef identifier;
    AXError err = AXUIElementCopyAttributeValue(window, CFSTR("AXIdentifier"), (CFTypeRef *)&identifier);
    if (err == kAXErrorSuccess && identifier) {
        
        DDLogDebug(@"AXIdentifier for Safari window: %@", (__bridge NSString *)identifier);
        result = (CFStringCompare(identifier, (__bridge CFStringRef)windowId, 0) == kCFCompareEqualTo);
        CFRelease(identifier);
    }
    return result;
}

@end
