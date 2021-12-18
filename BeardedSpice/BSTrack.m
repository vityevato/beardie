//
//  BSTrack.m
//  BeardedSpice
//
//  Created by Alex Evers on 12/01/15.
//  Copyright (c) 2015 GPL v3 http://www.gnu.org/licenses/gpl.html
//

#import "BSTrack.h"
#import "Beardie-Swift.h"

#import "GeneralPreferencesViewController.h"

NSString *const kBSTrackNameImage = @"image";
NSString *const kBSTrackNameTrack = @"track";
NSString *const kBSTrackNameAlbum = @"album";
NSString *const kBSTrackNameArtist = @"artist";
NSString *const kBSTrackNameProgress = @"progress";
NSString *const kBSTrackNameFavorited = @"favorited";

NSString *const kImageLock = @"kImageLock";

@implementation BSTrack

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _track = @"";
        _album = @"";
        _artist = @"";
        _progress = @"";
        _favorited = @0;
        _image = nil;
    }
    return self;
}

- (instancetype)initWithInfo:(NSDictionary *)info
{
    self = [self init];
    if (self)
    {
        _track = info[kBSTrackNameTrack] ?: @"";
        _album = info[kBSTrackNameAlbum] ?: @"";
        _artist = info[kBSTrackNameArtist] ?: @"";
        _progress = info[kBSTrackNameProgress] ?: @"";
        _favorited = info[kBSTrackNameFavorited] ?: @0; // 0 could also be evaluated as @NO
        _image = [NSURL URLWithString:info[kBSTrackNameImage]];
    }
    return self;
}

- (UserNotification *)asNotification
{
    UserNotification *notification = [UserNotification new];

    BOOL isShowProgressActive = [[NSUserDefaults standardUserDefaults] boolForKey:BeardedSpiceShowProgress];
    if (self.progress.length == 0) {
        isShowProgressActive = NO;
    }
    else if (self.album.length == 0) {
        isShowProgressActive = YES;
    }

    notification.title = self.track;
    notification.subtitle = isShowProgressActive ? self.artist : self.album;
    notification.body = isShowProgressActive ? self.progress : self.artist;

    if (self.favorited && [self.favorited boolValue]) {

        if (notification.title) {
            notification.title = [NSString stringWithFormat:@"★ %@ ★", notification.title];
        }
        else if (notification.subtitle){
            notification.subtitle = [NSString stringWithFormat:@"★ %@ ★", notification.subtitle];
        }
        else if (notification.body){

            notification.body = [NSString stringWithFormat:@"★ %@ ★", notification.body];
        }
    }
    notification.image = self.image;
    
    return notification;
}

- (void)setValue:(id)value forUndefinedKey:(NSString *)key { /* Do nothing. */ }

- (NSString *)description {
    return [NSString stringWithFormat:@"[BSTrack: %p, title: %@, album: %@, artist: %@, progress: %@, favorited: %@, image: %@]", self, _track, _album, _artist, _progress, (_favorited.boolValue ? @"YES" : @"NO"), (_image == nil ? @"none" : @"exists")];
}

@end
