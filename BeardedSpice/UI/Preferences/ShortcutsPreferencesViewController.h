//
//  AdvansedPreferencesViewController.h
//  BeardedSpice
//
//  Created by Roman Sokolov on 13.03.15.
//  Copyright (c) 2015 Tyler Rhodes / Jose Falcon. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MASPreferencesViewController.h"

@class BSShortcutRecorderView;

@interface ShortcutsPreferencesViewController : NSViewController <MASPreferencesViewController>

@property (nonatomic, weak) IBOutlet BSShortcutRecorderView *playPauseShortcut;
@property (nonatomic, weak) IBOutlet BSShortcutRecorderView *nextTrackShortcut;
@property (nonatomic, weak) IBOutlet BSShortcutRecorderView *previousTrackShortcut;
@property (nonatomic, weak) IBOutlet BSShortcutRecorderView *activatePlayingTabShortcut;
@property (nonatomic, weak) IBOutlet BSShortcutRecorderView *setActiveTabShortcut;
@property (nonatomic, weak) IBOutlet BSShortcutRecorderView *favoriteShortcut;
@property (nonatomic, weak) IBOutlet BSShortcutRecorderView *notificationShortcut;
@property (nonatomic, weak) IBOutlet BSShortcutRecorderView *playerNextShortcut;
@property (nonatomic, weak) IBOutlet BSShortcutRecorderView *playerPreviousShortcut;

@end
