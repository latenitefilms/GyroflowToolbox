#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

/// Reuses one Metal-backed Core Image context and one bounded GRAY8 readback buffer per analysis.
@interface GyroflowAnalysisImage : NSObject
- (instancetype)initWithDevice:(id<MTLDevice>)device;
/// The returned data is borrowed until the next conversion. Layout is validated by the Rust bridge.
- (nullable NSData *)convertTexture:(id<MTLTexture>)texture topDown:(BOOL)topDown
                            layout:(NSDictionary *)layout error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
