//
//  BeardedSpiceHostAppProtocol.h
//  BeardedSpiceControllers
//
//  Created by Roman Sokolov on 05.03.16.
//  Copyright (c) 2015-2016 GPL v3 http://www.gnu.org/licenses/gpl.html
//

#import <Foundation/Foundation.h>

@interface BS_XPCEvent: NSObject <NSCoding, NSSecureCoding>
@property (readonly) NSEventModifierFlags modifierFlags;
@property (readonly) NSInteger data1;
@property (readonly) NSInteger data2;
@property (readonly) BOOL keyPressed;

- (instancetype)initWithModifierFlags:(NSEventModifierFlags)modifierFlags
                                data1:(NSInteger)data1
                                data2:(NSInteger)data2
                           keyPressed:(BOOL)keyPressed;

- (NSEvent *)NSEvent;
@end

@protocol BeardedSpiceHostAppProtocol

- (void)playPauseToggle;
- (void)nextTrack;
- (void)previousTrack;

- (void)activeTab;
- (void)favorite;
- (void)notification;
- (void)activatePlayingTab;

- (void)playerNext;
- (void)playerPrevious;

- (void)volumeUp:(BS_XPCEvent *)event;
- (void)volumeDown:(BS_XPCEvent *)event;
- (void)volumeMute:(BS_XPCEvent *)event;

- (void)headphoneUnplug;

@end
