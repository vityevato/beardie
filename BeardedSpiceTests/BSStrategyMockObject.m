//
//  BSStrategyMockObject.m
//  BeardedSpice
//
//  Created by Alex Evers on 12/01/15.
//  Copyright (c) 2015 GPL v3 http://www.gnu.org/licenses/gpl.html
//

#import "BSStrategyMockObject.h"

#import "NSURL+Utils.h"

@implementation BSStrategyMockObject

+ (NSDictionary *)strategies
{
    static dispatch_once_t setupStrategies;
    static NSDictionary *strategies = nil;

    dispatch_once(&setupStrategies, ^{
        //NSString *strategiesFilePath = [[NSBundle mainBundle] URLForResource:@"vcr-strategy-urls" withExtension:@"plist"];
        //strategies = [[NSDictionary alloc] initWithContentsOfFile:strategiesFilePath];
        strategies = @{
            @"Youtube": @"https://www.youtube.com/watch?v=bY73vFGhSVk"
        };
    });

    return strategies;
}

- (instancetype)initWithStrategyName:(NSString *)strategyName
{
    self = [super init];
    if (self)
    {
        _file = [NSString stringWithFormat:@"%@StrategyTests", strategyName];
        _strategyName = strategyName;
        _webView = [[WebView alloc] initWithFrame:CGRectZero frameName:[NSString stringWithFormat:@"frame-name-%@", strategyName] groupName:@"strategy-group-test"];
        _webView.frameLoadDelegate = self;
        _finishedLoading = NO;

        NSError *error = nil;
        NSURL *url = [self strategyServiceURL];
        NSString *content = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&error];
        [_webView.mainFrame loadHTMLString:content baseURL:url];
    }
    return self;
}

- (BOOL)start
{
    if (!_strategyName)
        return NO;

    [self _beginTests];

    return YES;
}

- (NSURL *)strategyServiceURL
{
    NSString *urlForStrategy = [BSStrategyMockObject strategies][_strategyName];
    if (urlForStrategy)
        return [NSURL URLWithString:urlForStrategy];
    return nil;
}

- (NSURL *)strategyTemplateURL
{
    return [NSURL URLForFileName:_strategyName];
}

- (NSString *)evaluateScript:(NSString *)script
{
    /*
    NSString *javascriptString =[NSString stringWithFormat:@"javascript:(function(){id='X_BeardedSpice_Chrome_ApplescriptHack';if (document.getElementById(id) === null){node = document.createElement('pre');node.id = id;node.hidden = true; document.getElementsByTagName('body')[0].appendChild(node);} document.getElementById(id).innerText =  (function(){ var hackResult = %@; return JSON.stringify({'hackResult': hackResult}); })();})();", script];
    //Get the result from the hack element

    [self.tab executeJavascript:[NSString stringWithFormat:@"window.location.assign(\"%@\");",javascriptString]];

    NSDictionary *result = [self.tab executeJavascript:@"JSON.parse(document.getElementById('X_BeardedSpice_Chrome_ApplescriptHack').innerText)"];

    [self.tab executeJavascript:@"document.getElementById('X_BeardedSpice_Chrome_ApplescriptHack').remove()"];

    return result[@"hackResult"];
    */
    return [[self.webView windowScriptObject] evaluateWebScript:script];
}

- (void)_beginTests
{

}

#pragma mark - WebFrameLoadDelegate
- (void)webView:(WebView *)sender didStartProvisionalLoadForFrame:(WebFrame *)frame
{
    DDLogDebug(@"!!!!!!!!!");
}
- (void)webView:(WebView *)sender didCommitLoadForFrame:(WebFrame *)frame
{
    DDLogDebug(@":((((((");
}
- (void)webView:(WebView *)sender didClearWindowObject:(WebScriptObject *)windowObject forFrame:(WebFrame *)frame
{
    DDLogDebug(@":((((((");
}

- (void)webView:(WebView *)sender didCancelClientRedirectForFrame:(WebFrame *)frame
{
    DDLogDebug(@":((((((");
}

- (void)webView:(WebView *)sender willPerformClientRedirectToURL:(NSURL *)URL delay:(NSTimeInterval)seconds fireDate:(NSDate *)date forFrame:(WebFrame *)frame
{
DDLogDebug(@":((((((");
}

- (void)webView:(WebView *)sender didReceiveServerRedirectForProvisionalLoadForFrame:(WebFrame *)frame
{
DDLogDebug(@":((((((");
}

- (void)webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame
{
DDLogDebug(@":((((((");
}

- (void)webView:(WebView *)sender didReceiveIcon:(NSImage *)image forFrame:(WebFrame *)frame
{
DDLogDebug(@":((((((");
}

- (void)webView:(WebView *)sender didChangeLocationWithinPageForFrame:(WebFrame *)frame
{
DDLogDebug(@":((((((");
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    DDLogDebug(@"------------------------- did finish loading for frame....");
    self.finishedLoading = YES;
}

- (void)webView:(WebView *)sender didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    DDLogDebug(@"------------------------- webview failed to (provisionally) load strategy %@: %@", _strategyName, [error localizedDescription]);
    // FIXME add XCAssert here for failure
}

- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    DDLogDebug(@"------------------------- webview failed to load strategy %@: %@", _strategyName, [error localizedDescription]);
    // FIXME add XCAssert here for failure
}

@end
