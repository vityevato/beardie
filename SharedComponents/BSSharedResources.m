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
#define DEFAULTS_KEY_LOGLEVEL                   @"DebugLogLevel"

#define DATA_KEY_ACCEPTERS                      @"accepters.data"

#define NOTIFICATION_TABPORT                    BS_BUNDLE_ID @".notify.tabport"
#define NOTIFICATION_ACCEPTERS                  BS_BUNDLE_ID @".notify.accepters"
#define NOTIFICATION_LOGLEVEL                   BS_BUNDLE_ID @".notify.loglevel"

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
NSString *const BeardieBrowserExtensionsFirstRun = @"BeardieBrowserExtensionsFirstRun";

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
static BSSListenerBlock _onLogLevelChangedBlock;
static NSURL *_logsDirectory;

#ifdef DEBUG
DDLogLevel defLogLevel = DDLogLevelDebug;
DDLogLevel verboseLogLevel = DDLogLevelVerbose;
#else
DDLogLevel defLogLevel = DDLogLevelInfo;
DDLogLevel verboseLogLevel = DDLogLevelDebug;
#endif

DDLogLevel ddLogLevel = DDLogLevelAll;

+ (void)initialize{
    
    if (self == [BSSharedResources class]) {
        
        _containerFolderUrl = [self directoryWithUrl:
                                [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:BS_GROUP]
                                                title:@"App Group"] ;
        [self directoryWithUrl:[_containerFolderUrl URLByAppendingPathComponent:@"Library/Preferences/"] title:@"UserDefaults"];
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
#pragma mark  Public

+ (NSURL *)sharedResuorcesURL{
    
    return _containerFolderUrl;
}

+ (NSUserDefaults *)sharedDefaults{

    return _sharedUserDefaults;
}

+ (void)initLoggerForAppWithName:(NSString *)name {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        [self initLoggerFor:name];
        
        [self bind:@"logLevelDebugBinding"
          toObject:[NSUserDefaultsController sharedUserDefaultsController]
       withKeyPath:[@"values." stringByAppendingString:DEFAULTS_KEY_LOGLEVEL]
           options:@{}];

        self.logLevelDebug = [NSUserDefaults.standardUserDefaults boolForKey:DEFAULTS_KEY_LOGLEVEL];
    });

}
+ (void)initLoggerForComponentWithName:(NSString *)name changed:(dispatch_block_t)changedBlock {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{

        [self initLoggerFor:name];
        
        ASSIGN_WEAK(self);
        BSSListenerBlock block = ^{
            ASSIGN_STRONG(self);
            ddLogLevel = USE_STRONG(self).logLevelDebug ? verboseLogLevel: defLogLevel;
            if ([USE_STRONG(self) respondsToSelector:@selector(setSwiftLogLevel:)]) {
                [USE_STRONG(self) setSwiftLogLevel:USE_STRONG(self).logLevelDebug];
            }
            if (changedBlock) {
                changedBlock();
            }
            DDLogInfo(@"Log level changed to debug: %@", USE_STRONG(self).logLevelDebug ? @"YES" : @"NO");
        };
        [self setListenerOnLogLevelChanged:block];
        block();
    });

}

+ (void)synchronizeSharedDefaults{

    [_sharedUserDefaults synchronize];
}

/////////////////////////////////////////////////////////////////////
#pragma mark   Events (public methods)


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

+ (void)setListenerOnLogLevelChanged:(BSSListenerBlock)block {
    [self setListenerForNotification:NOTIFICATION_LOGLEVEL
                            blockPtr:&_onLogLevelChangedBlock
                               block:block];
}

+ (void)setLogLevelDebug:(BOOL)logLevelDebug {
    [self willChangeValueForKey:@"logLevelDebug"];
    
    ddLogLevel = logLevelDebug ? verboseLogLevel: defLogLevel;
    
    if ([self respondsToSelector:@selector(setSwiftLogLevel:)]) {
        [self setSwiftLogLevel:logLevelDebug];
    }
    
    [[self sharedDefaults] setBool:logLevelDebug forKey:DEFAULTS_KEY_LOGLEVEL];
    dispatch_async(dispatch_get_main_queue(), ^{
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (CFStringRef)NOTIFICATION_LOGLEVEL, NULL, NULL, YES);
    });
    [self didChangeValueForKey:@"logLevelDebug"];
}

+ (BOOL)logLevelDebug {
    return [[self sharedDefaults] boolForKey:DEFAULTS_KEY_LOGLEVEL];
}

/////////////////////////////////////////////////////////////////////
#pragma mark   Binding

+ (id)valueForUndefinedKey:(NSString *)key{

    return nil;
}

+ (void)setLogLevelDebugBinding:(id)logLevelDebugBinding {
    DDLogError(@"Trace");
    [self setLogLevelDebug:[NSUserDefaults.standardUserDefaults boolForKey:DEFAULTS_KEY_LOGLEVEL]];
}

/////////////////////////////////////////////////////////////////////
#pragma mark Helper methods (private)

+ (void)initLoggerFor:(NSString *)name {
        NSString *path = [@"Library/Logs/" stringByAppendingPathComponent:name];
        NSURL *logsDirectory = [self directoryWithUrl:[[self sharedResuorcesURL] URLByAppendingPathComponent:path isDirectory:YES]
                                          title:@"Logs"];
        if (logsDirectory == nil) {
                    [[NSException exceptionWithName:NSGenericException reason:@"Can't create logs directiory, find error in Console.app" userInfo:nil] raise];
        }
        DDLogFileManagerDefault *defaultLogFileManager = [[DDLogFileManagerDefault alloc] initWithLogsDirectory:[logsDirectory path]];

       DDFileLogger *fileLogger = [[DDFileLogger alloc] initWithLogFileManager:defaultLogFileManager];
        fileLogger.rollingFrequency = 60 * 60 * 24; // 24 hour rolling
        fileLogger.logFileManager.maximumNumberOfLogFiles = 7;
        fileLogger.maximumFileSize = 1024*1024;

        [DDLog addLogger:fileLogger];
        [DDLog addLogger:[DDOSLogger sharedInstance]];
        _logsDirectory = logsDirectory;
}

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

+ (NSURL *)directoryWithUrl:(NSURL *)url title:(NSString *)title {
    NSError *err;
    if (url) {
        
        if ([[NSFileManager defaultManager] createDirectoryAtURL:url
                                     withIntermediateDirectories:YES
                                                      attributes:nil
                                                           error:&err])
            return url;
        
        else {
            NSString *msg = [NSString stringWithFormat:@"Cannot create %@ directory: %@", title ?: @"", [err localizedDescription]];
            DDLogError(@"%@", msg);
        }
    }
    return nil;
}

/////////////////////////////////////////////////////////////////////
#pragma mark Storage methods (private)


+ (NSData *)loadDataFromFileRelativePath:(NSString *)relativePath{
    
    if (!relativePath) {
        [[NSException argumentException:@"relativePath"] raise];
    }
    
    @autoreleasepool {
        if (_containerFolderUrl) {
            
            NSURL *dataUrl = [self urlForRelativePath:relativePath];
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
            
            NSURL *dataUrl = [self urlForRelativePath:relativePath];
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
                NSError *err;
                data  = [NSKeyedArchiver archivedDataWithRootObject:obj requiringSecureCoding:YES error:&err];
                if (err) {
                    DDLogError(@"Converting error %@ to archive: %@", obj, err);
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
                NSError *err;
                result = [NSKeyedUnarchiver unarchivedObjectOfClass:aClass fromData:data error:&err];
                if (err) {
                    DDLogError(@"Converting error object from archive: %@", err);
                }
            }
            if (completion) {
                completion(result);
            }
        }
    });
}

+ (NSURL *) urlForRelativePath:(NSString*) relativePath {
    static NSURL *cachesUrl;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cachesUrl = [self directoryWithUrl:[[self sharedResuorcesURL] URLByAppendingPathComponent:@"Library/Caches/" isDirectory:YES]
                                          title:@"Caches"];
    });
    return [cachesUrl URLByAppendingPathComponent:relativePath];
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
    else if ([nName isEqualToString:NOTIFICATION_LOGLEVEL]) {
        block = _onLogLevelChangedBlock;
    }

    if (block) {
        block();
    }
}

@end

