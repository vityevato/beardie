//
//  BSMediaStrategyTests.m
//  BeardedSpice
//
//  Created by Alex Evers on 12/01/15.
//  Copyright (c) 2015 GPL v3 http://www.gnu.org/licenses/gpl.html
//

#import <XCTest/XCTest.h>

#import "BSMediaStrategy.h"

@interface BSMediaStrategyTests : XCTestCase

@end

@implementation BSMediaStrategyTests

- (void)testYouTubeStrategyLoads {
    NSURL *path = [[[NSBundle mainBundle] resourceURL] URLByAppendingPathComponent:@"MediaStrategies"];
    NSString *fileName = @"YouTube.js";
    NSURL *fileURL = [NSURL URLWithString:fileName relativeToURL:path];

    NSError *error = nil;
    BSMediaStrategy *strategy = [BSMediaStrategy mediaStrategyWithURL:fileURL error:&error];

    XCTAssertNotNil(strategy, @"Failed to load the YouTube strategy: %@", error);
    XCTAssertTrue([strategy isMemberOfClass:BSMediaStrategy.class]);

    XCTAssertNotNil(strategy.scripts);
    XCTAssertNotEqual(strategy.strategyVersion, 0);

    XCTAssertEqualObjects(strategy.displayName, @"YouTube");
    XCTAssertEqualObjects(strategy.fileName, @"YouTube.js");
    XCTAssertNotEqualObjects(strategy.displayName, strategy.fileName);

    XCTAssertNotNil(strategy.scripts[kBSMediaStrategyKeyToggle]);
    XCTAssertNotNil(strategy.scripts[kBSMediaStrategyKeyPrevious]);
    XCTAssertNotNil(strategy.scripts[kBSMediaStrategyKeyNext]);
    XCTAssertNotNil(strategy.scripts[kBSMediaStrategyKeyPause]);

    XCTAssertNotNil(strategy.toggle);
    XCTAssertNotNil(strategy.previous);
    XCTAssertNotNil(strategy.next);
    XCTAssertNotNil(strategy.pause);
}

@end
