//
//  HeaderView.m
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 13/7/2023.
//

#import "HeaderView.h"
#import <Foundation/Foundation.h>


@implementation HeaderView

- (NSString *)getAppVersionAndBuildNumber {
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    
    // Get the version number:
    NSString *version = [infoDictionary objectForKey:@"CFBundleShortVersionString"];
    
    // Get the build number:
    NSString *build = [infoDictionary objectForKey:@"CFBundleVersion"];
    
    // Construct the string:
    NSString *versionAndBuildString = [NSString stringWithFormat:@"v%@ (Build %@)", version, build];
    
    return versionAndBuildString;
}

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        if (![[NSBundle mainBundle] loadNibNamed:@"HeaderView" owner:self topLevelObjects:nil]) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to load HeaderView.xib");
        }
        [self.view setFrame:[self bounds]];
        [self addSubview:self.view];
                
        self.versionString.stringValue = [self getAppVersionAndBuildNumber];
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
}

@end
