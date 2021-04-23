//
//  VLCTabAdapter.m
//  BeardedSpice
//
//  Created by Max Borghino on 2106-03-06
//  Copyright (c) 2015 Tyler Rhodes / Jose Falcon. All rights reserved.
//

#import "VLCTabAdapter.h"
#import "VLC.h"
#import "runningSBApplication.h"
#import "NSString+Utils.h"
#import "BSMediaStrategy.h"
#import "BSTrack.h"

#define APPNAME         @"VLC"
#define APPID           @"org.videolan.vlc"

@implementation VLCTabAdapter

+ (NSString *)displayName{
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

- (NSString *)title {

    @autoreleasepool {
        VLCApplication *vlc = (VLCApplication *)[self.application sbApplication];
        NSString *title;
        if (![NSString isNullOrEmpty:vlc.nameOfCurrentItem])
            title = vlc.nameOfCurrentItem;

        if ([NSString isNullOrEmpty:title]) {
            title = BSLocalizedString(@"no-track-title", @"No tack title for tabs menu and default notification ");
        }

        return [NSString stringWithFormat:@"%@ (%@)", title, APPNAME];
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

    if (otherTab == nil || ![otherTab isKindOfClass:[VLCTabAdapter class]]) return NO;

    return YES;
}

//////////////////////////////////////////////////////////////
#pragma mark Player control methods
//////////////////////////////////////////////////////////////

- (BOOL)toggle{
    VLCApplication *vlc = (VLCApplication *)[self.application sbApplication];
    if (vlc) {
        [vlc play];
        return YES;
    }
    return NO;
}

- (BOOL)pause{
    VLCApplication *vlc = (VLCApplication *)[self.application sbApplication];
    if (vlc && [vlc playing]) {
        if (vlc) {
            [vlc play];
            return YES;
        }
    }
    return NO;
}

- (BOOL)next{
    VLCApplication *vlc = (VLCApplication *)[self.application sbApplication];
    if (vlc) {
        [vlc next];
        return YES;
    }
    return NO;
}

- (BOOL)previous{
    VLCApplication *vlc = (VLCApplication *)[self.application sbApplication];
    if (vlc) {
        [vlc previous];
        return YES;
    }
    return NO;
}

- (BSTrack *)trackInfo{
    VLCApplication *vlc = (VLCApplication *)[self.application sbApplication];
    if (vlc) {
        return [[BSTrack alloc] initWithInfo:@{
           kBSTrackNameTrack: [vlc nameOfCurrentItem],
           kBSTrackNameArtist: APPNAME
        }];
    }

    return nil;
}

- (BOOL)isPlaying{

    VLCApplication *vlc = (VLCApplication *)[self.application sbApplication];
    if (vlc) {
        return (BOOL)[vlc playing];
    }

    return NO;
}

@end
