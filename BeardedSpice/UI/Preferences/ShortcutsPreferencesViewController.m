//
//  AdvansedPreferencesViewController.m
//  BeardedSpice
//
//  Created by Roman Sokolov on 13.03.15.
//  Copyright (c) 2015 Tyler Rhodes / Jose Falcon. All rights reserved.
//

#import "ShortcutsPreferencesViewController.h"
#import "BSSharedResources.h"

@implementation ShortcutsPreferencesViewController

- (id)init
{
    self = [super initWithNibName:@"ShortcutsPreferencesView" bundle:nil];
    if (self) {
    }
    return self;
}

- (void)awakeFromNib
{
    // associate view with userdefaults
    [self.playPauseShortcut setAssociatedUserDefaultsKey:BeardedSpicePlayPauseShortcut];
    [self.nextTrackShortcut setAssociatedUserDefaultsKey:BeardedSpiceNextTrackShortcut];
    [self.previousTrackShortcut setAssociatedUserDefaultsKey:BeardedSpicePreviousTrackShortcut];
    [self.setActiveTabShortcut setAssociatedUserDefaultsKey:BeardedSpiceActiveTabShortcut];
    [self.favoriteShortcut setAssociatedUserDefaultsKey:BeardedSpiceFavoriteShortcut];
    [self.notificationShortcut setAssociatedUserDefaultsKey:BeardedSpiceNotificationShortcut];
    [self.activatePlayingTabShortcut setAssociatedUserDefaultsKey:BeardedSpiceActivatePlayingTabShortcut];
    [self.playerNextShortcut setAssociatedUserDefaultsKey:BeardedSpicePlayerNextShortcut];
    [self.playerPreviousShortcut setAssociatedUserDefaultsKey:BeardedSpicePlayerPreviousShortcut];

    // Stable accessibility elements for UI tests. They do not change the
    // stored shortcuts.
    [self configureShortcutView:self.playPauseShortcut
                     identifier:@"shortcut.playPause"
                          label:@"Play/Pause"];
    [self configureShortcutView:self.nextTrackShortcut
                     identifier:@"shortcut.nextTrack"
                          label:@"Next"];
    [self configureShortcutView:self.previousTrackShortcut
                     identifier:@"shortcut.previousTrack"
                          label:@"Previous"];
    [self configureShortcutView:self.setActiveTabShortcut
                     identifier:@"shortcut.setActiveTab"
                          label:@"Next"];
    [self configureShortcutView:self.favoriteShortcut
                     identifier:@"shortcut.favorite"
                          label:@"Toggle Favorite"];
    [self configureShortcutView:self.notificationShortcut
                     identifier:@"shortcut.notification"
                          label:@"Show Track Info"];
    [self configureShortcutView:self.activatePlayingTabShortcut
                     identifier:@"shortcut.activatePlayingTab"
                          label:@"Set Active Player Window"];
    [self configureShortcutView:self.playerNextShortcut
                     identifier:@"shortcut.playerNext"
                          label:@"Next"];
    [self configureShortcutView:self.playerPreviousShortcut
                     identifier:@"shortcut.playerPrevious"
                          label:@"Previous"];
}

- (void)configureShortcutView:(NSView *)view
                   identifier:(NSString *)identifier
                        label:(NSString *)label
{
    [view setAccessibilityElement:YES];
    [view setAccessibilityRole:NSAccessibilityButtonRole];
    [view setAccessibilityLabel:label];
    [view setAccessibilityIdentifier:identifier];
}

- (NSString *)viewIdentifier
{
    return @"ShortcutsPreferences";
}

- (NSImage *)toolbarItemImage
{
    return [NSImage imageNamed:@"toolbarShortcuts"];
}

- (NSString *)toolbarItemLabel
{
    return BSLocalizedString(@"Shortcuts", @"Toolbar item name for the Shortcuts preference pane");
}

- (NSView *)initialKeyView{
    
    return self.playPauseShortcut;
}


@end
