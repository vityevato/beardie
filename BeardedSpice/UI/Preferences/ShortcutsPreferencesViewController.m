//
//  AdvansedPreferencesViewController.m
//  BeardedSpice
//
//  Created by Roman Sokolov on 13.03.15.
//  Copyright (c) 2015 Tyler Rhodes / Jose Falcon. All rights reserved.
//

#import "ShortcutsPreferencesViewController.h"
#import "BSSharedResources.h"
#import "Beardie-Swift.h"

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
    [self configureShortcutView:self.playPauseShortcut
                         action:BSShortcutActionPlayPause
                     identifier:@"shortcut.playPause"
                          label:@"Play/Pause"];
    [self configureShortcutView:self.nextTrackShortcut
                         action:BSShortcutActionNextTrack
                     identifier:@"shortcut.nextTrack"
                          label:@"Next"];
    [self configureShortcutView:self.previousTrackShortcut
                         action:BSShortcutActionPreviousTrack
                     identifier:@"shortcut.previousTrack"
                          label:@"Previous"];
    [self configureShortcutView:self.setActiveTabShortcut
                         action:BSShortcutActionActiveTab
                     identifier:@"shortcut.setActiveTab"
                          label:@"Set Active Player Window"];
    [self configureShortcutView:self.favoriteShortcut
                         action:BSShortcutActionFavorite
                     identifier:@"shortcut.favorite"
                          label:@"Toggle Favorite"];
    [self configureShortcutView:self.notificationShortcut
                         action:BSShortcutActionNotification
                     identifier:@"shortcut.notification"
                          label:@"Show Track Info"];
    [self configureShortcutView:self.activatePlayingTabShortcut
                         action:BSShortcutActionActivatePlayingTab
                     identifier:@"shortcut.activatePlayingTab"
                          label:@"Raise/Hide Active Player Window"];
    [self configureShortcutView:self.playerNextShortcut
                         action:BSShortcutActionPlayerNext
                     identifier:@"shortcut.playerNext"
                          label:@"Next"];
    [self configureShortcutView:self.playerPreviousShortcut
                         action:BSShortcutActionPlayerPrevious
                     identifier:@"shortcut.playerPrevious"
                          label:@"Previous"];

    [self configureKeyViewLoop];
}

- (void)viewDidAppear
{
    [super viewDidAppear];
    // The toolbar exists only after the pane is installed in the
    // preferences window, so refresh the exit target here.
    [self configureKeyViewLoop];
}

- (void)configureShortcutView:(BSShortcutRecorderView *)view
                       action:(BSShortcutAction)action
                   identifier:(NSString *)identifier
                        label:(NSString *)label
{
    __weak typeof(self) weakSelf = self;

    view.action = action;
    view.onChange = ^{
        [weakSelf shortcutsDidChange];
    };
    view.recordingDidChange = ^(BOOL active) {
        [[NSNotificationCenter defaultCenter] postNotificationName:BSShortcutRecordingDidChangeNotification
                                                            object:weakSelf
                                                          userInfo:@{BSShortcutRecordingActiveKey: @(active)}];
    };

    // Stable accessibility elements for UI tests and VoiceOver. The
    // identifier is set on the actual search field inside the wrapper.
    [view setShortcutAccessibilityWithIdentifier:identifier label:label];
}

- (void)configureKeyViewLoop
{
    NSArray<BSShortcutRecorderView *> *recorders = @[
        self.playPauseShortcut,
        self.nextTrackShortcut,
        self.previousTrackShortcut,
        self.playerNextShortcut,
        self.playerPreviousShortcut,
        self.setActiveTabShortcut,
        self.activatePlayingTabShortcut,
        self.favoriteShortcut,
        self.notificationShortcut,
    ];

    for (NSUInteger index = 0; index + 1 < recorders.count; index++) {
        recorders[index].keyView.nextKeyView = recorders[index + 1].keyView;
        recorders[index].nextRecorderView = recorders[index + 1];
    }

    for (NSUInteger index = 1; index < recorders.count; index++) {
        recorders[index].previousRecorderView = recorders[index - 1];
    }

    for (BSShortcutRecorderView *recorder in recorders) {
        recorder.firstRecorderView = recorders.firstObject;
        recorder.lastRecorderView = recorders.lastObject;
    }

    // Keep the standard key-view chain linear. BSShortcutRecorderView decides
    // where Tab goes: it wraps inside the recorder loop when keyboard
    // navigation is off, and exits to the first/last toolbar button when it
    // is on.
    recorders.lastObject.keyView.nextKeyView = nil;
    self.view.nextKeyView = recorders.firstObject.keyView;

    NSToolbar *toolbar = self.view.window.toolbar;
    NSView *firstToolbarButton = [self findToolbarButtonForItem:toolbar.items.firstObject];
    NSView *lastToolbarButton = [self findToolbarButtonForItem:toolbar.items.lastObject];

    DDLogDebug(@"Keyboard navigation: fullKeyboardAccess=%@, AppleKeyboardUIMode=%ld, first=%@, last=%@",
              NSApp.isFullKeyboardAccessEnabled ? @"YES" : @"NO",
              (long)[[NSUserDefaults standardUserDefaults] integerForKey:@"AppleKeyboardUIMode"],
              firstToolbarButton, lastToolbarButton);

    for (BSShortcutRecorderView *recorder in recorders) {
        recorder.forwardExitView = firstToolbarButton;
        recorder.backwardExitView = lastToolbarButton;
    }
}

- (NSView *)findToolbarButtonForItem:(NSToolbarItem *)item
{
    if (!item) {
        return nil;
    }

    id viewer = [item valueForKey:@"_itemViewer"];
    if (viewer) {
        NSView *button = [self findFirstButtonInView:viewer];
        if (button) {
            return button;
        }
    }

    // Fallback for a future macOS where the item viewer is not available.
    NSWindow *window = self.view.window;
    return [self findButtonWithTitle:item.label inView:window.contentView.superview];
}

- (NSView *)findFirstButtonInView:(NSView *)view
{
    if ([view isKindOfClass:[NSButton class]]) {
        return view;
    }

    for (NSView *subview in view.subviews) {
        NSView *result = [self findFirstButtonInView:subview];
        if (result) {
            return result;
        }
    }

    return nil;
}

- (NSView *)findButtonWithTitle:(NSString *)title inView:(NSView *)view
{
    if ([view isKindOfClass:[NSButton class]]) {
        NSButton *button = (NSButton *)view;
        if ([button.title isEqualToString:title] ||
            [button.accessibilityLabel isEqualToString:title]) {
            return button;
        }
    }

    for (NSView *subview in view.subviews) {
        NSView *result = [self findButtonWithTitle:title inView:subview];
        if (result) {
            return result;
        }
    }

    return nil;
}

- (void)shortcutsDidChange
{
    [[NSNotificationCenter defaultCenter] postNotificationName:BSShortcutsDidChangeNotification object:self];
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

    // Focusing RecorderCocoa immediately starts recording. Do not put the
    // cursor into the first shortcut field just because the pane opened;
    // the user can still Tab into the recorders.
    return self.view;
}


@end
