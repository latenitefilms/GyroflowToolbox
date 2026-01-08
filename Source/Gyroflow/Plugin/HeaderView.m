//
//  HeaderView.m
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 13/7/2023.
//

#import "HeaderView.h"
#import <Foundation/Foundation.h>

@interface HeaderView ()
@property (nonatomic, strong) NSArray *topLevelObjects;
@end

@implementation HeaderView

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        NSBundle *bundle = [NSBundle bundleForClass:self.class];

        NSArray *objects = nil;
        if (![bundle loadNibNamed:@"HeaderView" owner:self topLevelObjects:&objects]) {
            NSLog(@"Failed to load HeaderView.xib");
            return self;
        }
        self.topLevelObjects = objects; // keep strong refs

        NSView *content = self.view;
        content.frame = self.bounds;
        content.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self addSubview:content];

        self.versionString.stringValue = [self getAppVersionAndBuildNumberFromBundle:bundle];
    }
    return self;
}

- (NSString *)getAppVersionAndBuildNumberFromBundle:(NSBundle *)bundle
{
    NSDictionary *info = bundle.infoDictionary;
    NSString *version = info[@"CFBundleShortVersionString"] ?: @"?";
    NSString *build   = info[@"CFBundleVersion"] ?: @"?";
    return [NSString stringWithFormat:@"v%@ (Build %@)", version, build];
}

@end
