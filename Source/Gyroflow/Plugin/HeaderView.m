//
//  HeaderView.m
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 13/7/2023.
//

#import "HeaderView.h"

@implementation HeaderView

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        if (![[NSBundle mainBundle] loadNibNamed:@"HeaderView" owner:self topLevelObjects:nil]) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to load HeaderView.xib");
        }
        [self.view setFrame:[self bounds]];
        [self addSubview:self.view];
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    // Drawing code here.
}

@end
