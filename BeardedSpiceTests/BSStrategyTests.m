//
//  BSStrategyTests.m
//  BeardedSpice
//
//  Created by Alex Evers on 12/01/15.
//  Copyright (c) 2015 GPL v3 http://www.gnu.org/licenses/gpl.html
//

#import <XCTest/XCTest.h>

#import "BSStrategyCache.h"
#import "BSMediaStrategy.h"
#import "NSURL+Utils.h"

@interface BSStrategyTests : XCTestCase

@property (nonatomic, strong) BSStrategyCache *cache;

@end

@implementation BSStrategyTests

- (void)setUp {
    [super setUp];

    self.cache = [BSStrategyCache new];
    XCTAssertTrue([self.cache updateStrategiesFromSourceURL:[NSURL URLForBundleStrategies]],
                  @"Failed to load strategies from the application bundle");
}

- (void)testAllStrategiesAreLoaded {
    NSArray<BSMediaStrategy *> *strategies = [self.cache allStrategies];
    XCTAssertGreaterThan(strategies.count, 0, @"No media strategies were loaded");
}

- (void)testAllStrategiesHaveValidScripts {
    NSArray<BSMediaStrategy *> *strategies = [self.cache allStrategies];
    XCTAssertGreaterThan(strategies.count, 0, @"No media strategies were loaded");

    for (BSMediaStrategy *strategy in strategies) {
        NSString *fileName = strategy.fileName;

        NSDictionary *acceptParams = strategy.acceptParams;
        XCTAssertNotNil(acceptParams, @"%@: acceptParams is nil", fileName);
        XCTAssertGreaterThan(acceptParams.count, 0, @"%@: acceptParams is empty", fileName);

        id acceptScript = acceptParams[kBSMediaStrategyAcceptMethod];
        XCTAssertNotNil(acceptScript, @"%@: accept script is nil", fileName);
        XCTAssertTrue([acceptScript isKindOfClass:[NSString class]],
                      @"%@: accept script is not a string", fileName);
        if ([acceptScript isKindOfClass:[NSString class]]) {
            XCTAssertGreaterThan([(NSString *)acceptScript length], 0,
                                 @"%@: accept script is empty", fileName);
        }

        id toggleScript = strategy.scripts[kBSMediaStrategyKeyToggle];
        XCTAssertNotNil(toggleScript, @"%@: toggle script is nil", fileName);
        XCTAssertTrue([toggleScript isKindOfClass:[NSString class]],
                      @"%@: toggle script is not a string", fileName);
        if ([toggleScript isKindOfClass:[NSString class]]) {
            XCTAssertGreaterThan([(NSString *)toggleScript length], 0,
                                 @"%@: toggle script is empty", fileName);
        }
    }
}

@end
