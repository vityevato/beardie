//
//  BeardedSpiceHostAppProtocol.m
//  BeardedSpiceControllers
//
//  Created by Roman Sokolov on 05.19.21.
//  Copyright (c) 2015-2016 GPL v3 http://www.gnu.org/licenses/gpl.html
//

#import "BeardedSpiceHostAppProtocol.h"
#import "SPMediaKeyTap.h"

@implementation BS_XPCEvent

+ (BOOL)supportsSecureCoding{
    return YES;
}
- (instancetype)initWithModifierFlags:(NSEventModifierFlags)modifierFlags
                                data1:(NSInteger)data1
                                data2:(NSInteger)data2
                           keyPressed:(BOOL)keyPressed {
    self = [super init];
    if (self) {
        _modifierFlags = modifierFlags;
        _data1 = data1;
        _data2 = data2;
        _keyPressed = keyPressed;
    }
    return self;
}

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [coder encodeInteger:(NSInteger)_modifierFlags forKey:@"_modifierFlags"];
    [coder encodeInteger:_data1 forKey:@"_data1"];
    [coder encodeInteger:_data2 forKey:@"_data2"];
    [coder encodeBool:_keyPressed forKey:@"_keyPressed"];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
    self = [super init];
    if (self) {
        _modifierFlags = (NSUInteger)[coder decodeIntegerForKey:@"_modifierFlags"];
        _data1 = [coder decodeIntegerForKey:@"_data1"];
        _data2 = [coder decodeIntegerForKey:@"_data2"];;
        _keyPressed = [coder decodeBoolForKey:@"_keyPressed"];
    }
    return self;
}

- (NSEvent *)NSEvent {
    return [NSEvent otherEventWithType:NSEventTypeSystemDefined
                                        location:NSZeroPoint
                                   modifierFlags:_modifierFlags
                                       timestamp:0
                                    windowNumber:0
                                         context:nil
                                         subtype:SPSystemDefinedEventMediaKeys
                                           data1:_data1
                                           data2:SPPassthroughEventData2Value];

}
@end
