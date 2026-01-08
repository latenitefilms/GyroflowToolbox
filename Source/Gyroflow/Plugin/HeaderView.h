//
//  HeaderView.h
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 13/7/2023.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface HeaderView : NSView

@property (nonatomic, weak) IBOutlet NSView *view;

@property (nonatomic, weak) IBOutlet NSTextField *versionString;

@end

NS_ASSUME_NONNULL_END
