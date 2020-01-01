//
//  BSSharedResources.m
//  BeardedSpice
//
//  Created by Roman Sokolov on 20.08.2018.
//  Copyright © 2018  GPL v3 http://www.gnu.org/licenses/gpl.html
//

#import "BSSharedResources.h"
#import <SafariServices/SafariServices.h>
#import "NSException+Utils.h"
#import "EHFileLocker.h"

#define DEFAULTS_KEY_TABPORT                    @"TabPort"

#define DATA_KEY_ACCEPTERS                      @"accepters.data"

#define NOTIFICATION_TABPORT                    BS_BUNDLE_ID @".notify.tabport"
#define NOTIFICATION_ACCEPTERS                  BS_BUNDLE_ID @".notify.accepters"


/////////////////////////////////////////////////////////////////////
#pragma mark - BSSharedResources Constants

NSString *const BeardedSpicePlayPauseShortcut = @"BeardedSpicePlayPauseShortcut";
NSString *const BeardedSpiceNextTrackShortcut = @"BeardedSpiceNextTrackShortcut";
NSString *const BeardedSpicePreviousTrackShortcut = @"BeardedSpicePreviousTrackShortcut";
NSString *const BeardedSpiceActiveTabShortcut = @"BeardedSpiceActiveTabShortcut";
NSString *const BeardedSpiceFavoriteShortcut = @"BeardedSpiceFavoriteShortcut";
NSString *const BeardedSpiceNotificationShortcut = @"BeardedSpiceNotificationShortcut";
NSString *const BeardedSpiceActivatePlayingTabShortcut = @"BeardedSpiceActivatePlayingTabShortcut";
NSString *const BeardedSpicePlayerNextShortcut = @"BeardedSpicePlayerNextShortcut";
NSString *const BeardedSpicePlayerPreviousShortcut = @"BeardedSpicePlayerPreviousShortcut";

NSString *const BeardedSpiceFirstRun = @"BeardedSpiceFirstRun";

/////////////////////////////////////////////////////////////////////
#pragma mark - BSSharedResources

@implementation BSSharedResources

static void onChangedNotify(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);

/////////////////////////////////////////////////////////////////////
#pragma mark Initialize
/////////////////////////////////////////////////////////////////////

static NSURL *_containerFolderUrl;
static NSUserDefaults *_sharedUserDefaults;

static BSSListenerBlock _onAcceptersChangedBlock;
static BSSListenerBlock _onTabPortChangedBlock;

+ (void)initialize{
    
    if (self == [BSSharedResources class]) {
        
        _containerFolderUrl = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:BS_GROUP];
        _sharedUserDefaults = [[NSUserDefaults alloc] initWithSuiteName:BS_GROUP];

        // Registering standart Defaults
        NSString *defPath = [[NSBundle mainBundle] pathForResource:@"defaults" ofType:@"plist"];
        if (defPath) {
            NSDictionary * defs = [NSDictionary dictionaryWithContentsOfFile:defPath];
            if (defs)
                [_sharedUserDefaults registerDefaults:defs];
        }

        _onAcceptersChangedBlock = NULL;
        _onTabPortChangedBlock = NULL;
    }
}

/////////////////////////////////////////////////////////////////////
#pragma mark   Events (public methods)

+ (NSURL *)sharedResuorcesURL{
    
    return _containerFolderUrl;
}

+ (NSUserDefaults *)sharedDefaults{

    return _sharedUserDefaults;
}

+ (void)synchronizeSharedDefaults{

    [_sharedUserDefaults synchronize];
}

+ (void)setListenerOnTabPortChanged:(BSSListenerBlock)block {
    [self setListenerForNotification:NOTIFICATION_TABPORT
                            blockPtr:&_onTabPortChangedBlock
                               block:block];
}

+ (void)setTabPort:(NSUInteger)tabPort {
    [self willChangeValueForKey:@"tabPort"];
    [[self sharedDefaults] setInteger:tabPort forKey:DEFAULTS_KEY_TABPORT];
    dispatch_async(dispatch_get_main_queue(), ^{
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (CFStringRef)NOTIFICATION_TABPORT, NULL, NULL, YES);
    });
    [self didChangeValueForKey:@"tabPort"];
}

+ (NSUInteger)tabPort {
    return [[self sharedDefaults] integerForKey:DEFAULTS_KEY_TABPORT];
}

+ (void)setListenerOnAcceptersChanged:(BSSListenerBlock)block {
    [self setListenerForNotification:NOTIFICATION_ACCEPTERS
                            blockPtr:&_onAcceptersChangedBlock
                               block:block];
}

+ (void)setAccepters:(NSDictionary *)accepters completion:(void (^)(void))completion {
    [self saveObject:accepters key:DATA_KEY_ACCEPTERS completion:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (CFStringRef)NOTIFICATION_ACCEPTERS, NULL, NULL, YES);
        });
        if (completion) {
            completion();
        }
    }];
}

+ (void)acceptersWithCompletion:(void (^)(NSDictionary *accepters))completion {
    [self loadObjectWithKey:DATA_KEY_ACCEPTERS class:[NSDictionary class] completion:completion];
}

/////////////////////////////////////////////////////////////////////
#pragma mark Helper methods (private)

+ (void)setListenerForNotification:(NSString *)notificationName
                          blockPtr:(__strong BSSListenerBlock *)blockPtr
                             block:(BSSListenerBlock)block {
    if (*blockPtr) {
        //Observer was registered
        if (! block) {
            //unregister observer
            CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                               (__bridge const void *)(self),
                                               (CFStringRef)notificationName,
                                               NULL);
        }
    }
    else if (block) {
        //Register observer

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge const void *)(self),
                                        &onChangedNotify,
                                        (CFStringRef)notificationName,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    *blockPtr = block;
}

/////////////////////////////////////////////////////////////////////
#pragma mark Storage methods (private)


+ (NSData *)loadDataFromFileRelativePath:(NSString *)relativePath{
    
    if (!relativePath) {
        [[NSException argumentException:@"relativePath"] raise];
    }
    
    @autoreleasepool {
        if (_containerFolderUrl) {
            
            NSURL *dataUrl = [_containerFolderUrl URLByAppendingPathComponent:relativePath];
            if (dataUrl) {
                EHFileLocker *locker = [[EHFileLocker alloc] initWithPath:[dataUrl path]];
                if ([locker lock]) {
                    
                    NSData *data = [NSData dataWithContentsOfURL:dataUrl];
                    
                    [locker unlock];
                    
                    return data;
                }
            }
        }
        
        return nil;
    }
}

+ (BOOL)saveData:(NSData *)data toFileRelativePath:(NSString *)relativePath{

    if (!(data && relativePath)) {
        [[NSException argumentException:@"data/relativePath"] raise];
    }
    
    @autoreleasepool {
        if (_containerFolderUrl) {
            
            NSURL *dataUrl = [_containerFolderUrl URLByAppendingPathComponent:relativePath];
            if (dataUrl) {
                EHFileLocker *locker = [[EHFileLocker alloc] initWithPath:[dataUrl path]];
                if ([locker lock]) {
                    
                    BOOL result = [data writeToURL:dataUrl atomically:YES];
                    
                    [locker unlock];
                    
                    return result;
                }
            }
        }
        
        return NO;;
    }
}

+ (void)saveObject:(id)obj key:(NSString *)key completion:(void (^)(void))completion {

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
        @autoreleasepool {
            if (obj == nil) {
                [self saveData:[NSData data] toFileRelativePath:key];
            }
            else {
                NSData *data;
                if (@available(macOS 10.13, *)) {
                    NSError *err;
                    data  = [NSKeyedArchiver archivedDataWithRootObject:obj requiringSecureCoding:YES error:&err];
                    if (err) {
                        BSLog(BSLOG_ERROR, @"Converting error %@ to archive: %@", obj, err);
                    }
                } else {
                    data  = [NSKeyedArchiver archivedDataWithRootObject:obj];
                }
                if (!data) {
                    data = [NSData data];
                }

                [self saveData:data toFileRelativePath:key];
            }
            if (completion) {
                completion();
            }
        }
    });
}

+ (void)loadObjectWithKey:(NSString *)key class:(Class)aClass completion:(void (^)(id obj))completion {

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
        @autoreleasepool {
            NSData *data = [self loadDataFromFileRelativePath:key];
            id result = nil;
            if (data.length) {
                if (@available(macOS 10.13, *)) {
                    NSError *err;
                    result = [NSKeyedUnarchiver unarchivedObjectOfClass:aClass fromData:data error:&err];
                    if (err) {
                        BSLog(BSLOG_ERROR, @"Converting error object from archive: %@", err);
                    }
                }
                else {
                    result = [NSKeyedUnarchiver unarchiveObjectWithData:data];
                }
            }
            if (completion) {
                completion(result);
            }
        }
    });
}

- (NSString*) pathForRelativePath:(NSString*) relativePath {
    
    NSURL *dataUrl = [_containerFolderUrl URLByAppendingPathComponent:relativePath];
    
    return dataUrl.path;
}

/////////////////////////////////////////////////////////////////////
#pragma mark Darwin notofication callbacks (private)

static void onChangedNotify(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSString *nName = (__bridge NSString *)name;
    BSSListenerBlock block = nil;
    if ([nName isEqualToString:NOTIFICATION_TABPORT]) {
        block = _onTabPortChangedBlock;
    }
    else if ([nName isEqualToString:NOTIFICATION_ACCEPTERS]) {
        block = _onAcceptersChangedBlock;
    }

    if (block) {
        block();
    }
}

@end

