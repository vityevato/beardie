//
//  BSSwinsianTabAdapter.m
//  Beardie
//
//  Created by Roman Sokolov on 06.06.2021.
//  Copyright © 2021 GPL v3 http://www.gnu.org/licenses/gpl.html
//

#import "BSSwinsianTabAdapter.h"
#import "runningSBApplication.h"
#import "BSMediaStrategy.h"
#import "BSTrack.h"
#import "NSString+Utils.h"

#define APPID                  @"com.swinsian.Swinsian"
#define APPNAME                @"Swinsian"

@implementation BSSwinsianTabAdapter

+ (NSString *)displayName {
    static NSString *name;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        name = [super displayName];
    });
    return name ?: APPNAME;
}

+ (NSString *)bundleId{
    return APPID;
}

- (NSString *)title{

    @autoreleasepool {

        SwinsianApplication *music = (SwinsianApplication *)[self.application sbApplication];
        SwinsianTrack *currentTrack = [music currentTrack];

        NSString *title;
        if (currentTrack) {

            if (currentTrack.name.length){
                title = currentTrack.name;
            }
            
            if (currentTrack.artist.length) {

                if (title) title = [title stringByAppendingFormat:@" - %@", currentTrack.artist];
                else
                    title = currentTrack.artist;
            }
        }

        if ([NSString isNullOrEmpty:title]) {
            title = BSLocalizedString(@"no-track-title", @"No tack title for tabs menu and default notification ");
        }

        return [NSString stringWithFormat:@"%@ (%@)", title, BSSwinsianTabAdapter.displayName];
    }
}

- (NSString *)URL{

    return APPID;
}

// We have only one window.
- (NSString *)key{

    return @"A:" APPID;
}

// We have only one window.
-(BOOL) isEqual:(__autoreleasing id)otherTab{

    if (otherTab == nil || ![otherTab isKindOfClass:[BSSwinsianTabAdapter class]]) return NO;

    return YES;
}

//////////////////////////////////////////////////////////////
#pragma mark Player control methods
//////////////////////////////////////////////////////////////

- (BOOL)toggle{

    SwinsianApplication *music = (SwinsianApplication *)[self.application sbApplication];
    if (music) {
        [music playpause];
    }
//    _musicNeedDisplayNotification = YES;
    return YES;
}
- (BOOL)pause{

    SwinsianApplication *music = (SwinsianApplication *)[self.application sbApplication];
    if (music) {
        [music pause];
    }
//    _musicNeedDisplayNotification = YES;
    return YES;
}
- (BOOL)next{

    SwinsianApplication *music = (SwinsianApplication *)[self.application sbApplication];
    if (music) {
        [music nextTrack];
    }
//    _musicNeedDisplayNotification = NO;
    return YES;
}
- (BOOL)previous{

    SwinsianApplication *music = (SwinsianApplication *)[self.application sbApplication];
    if (music) {
        [music previousTrack];
    }
//    _musicNeedDisplayNotification = NO;
    return YES;
}

- (BOOL)favorite{

    SwinsianApplication *music = (SwinsianApplication *)[self.application sbApplication];
    if (music) {
        SwinsianTrack *track = [music currentTrack];
        @try {
            if ([[track rating] integerValue])
                track.rating = @(0);
            else
                track.rating = @(5);
        }
        @catch (NSException *exception) {

            DDLogError(@"Error when calling [Swinsian rating]: %@", exception);
            ERROR_TRACE;
        }
    }
    return YES;
}

- (BSTrack *)trackInfo{

    SwinsianApplication *music = (SwinsianApplication *)[self.application sbApplication];
    if (music) {

        SwinsianTrack *track = [music currentTrack];
        if (track) {
            BSTrack *trackInfo = [BSTrack new];

            trackInfo.track = track.name ?: BSLocalizedString(@"apple-music-track-info-not-supported", @"");
            trackInfo.album = track.album;
            trackInfo.artist = track.artist;
            id image = track.albumArt;
            if ([image isKindOfClass:[NSImage class]]) {
                trackInfo.image = image;
            }
            else if ([image isKindOfClass:[NSAppleEventDescriptor class]]) {
                image = nil;
                NSData *data = [(NSAppleEventDescriptor *)track.albumArt data];
                if (data.length) {
                    trackInfo.image = [[NSImage alloc] initWithData:data];
                }
            }


            @try {
                trackInfo.favorited = @([track.rating boolValue]);
            }
            @catch (NSException *exception) {
                DDLogError(@"Error when calling [Swinsian rating]: %@", exception);
                ERROR_TRACE;
            }

            return trackInfo;
        }
    }

    return nil;
}

- (BOOL)isPlaying{

    SwinsianApplication *music = (SwinsianApplication *)[self.application sbApplication];
    if (music) {

        switch (music.playerState) {

            case SwinsianPlayerStateStopped:
            case SwinsianPlayerStatePaused:

                return NO;

            default:

                return YES;
        }
    }

    return NO;
}

//- (BOOL)showNotifications{
//    return _musicNeedDisplayNotification;
//}

@end
