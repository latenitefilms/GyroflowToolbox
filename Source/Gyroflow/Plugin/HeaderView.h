//
//  HeaderView.h
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 13/7/2023.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface HeaderView : NSView

@property (assign) IBOutlet NSView *view;

@property (assign) IBOutlet NSTextField *versionString;

@end

NS_ASSUME_NONNULL_END
