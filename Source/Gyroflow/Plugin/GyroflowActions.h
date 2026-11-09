#import "GyroflowPlugIn.h"

NS_ASSUME_NONNULL_BEGIN

/// Inspector actions share one capture and commit path with the background analyzer.
@interface GyroflowPlugIn (ToolboxActions)
- (void)performToolboxAction:(UInt32)identifier;
- (nullable GyroflowParameters *)captureToolboxParameters:(NSError **)error;
- (nullable NSString *)currentToolboxProject:(NSError **)error;
- (BOOL)commitToolboxProject:(NSString *)project expectedProject:(NSString *)expected
           refreshControls:(BOOL)refresh error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
