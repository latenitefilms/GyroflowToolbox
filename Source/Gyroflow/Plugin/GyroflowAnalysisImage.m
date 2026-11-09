#import "GyroflowAnalysisImage.h"
#import <CoreImage/CoreImage.h>

@interface GyroflowAnalysisImage ()
@property (nonatomic, strong) CIContext *context;
@property (nonatomic, strong) NSMutableData *pixels;
@end

@implementation GyroflowAnalysisImage
- (instancetype)initWithDevice:(id<MTLDevice>)device {
    if ((self = [super init])) {
        _context = [CIContext contextWithMTLDevice:device options:@{
            kCIContextUseSoftwareRenderer: @NO, kCIContextCacheIntermediates: @NO,
            kCIContextWorkingColorSpace: NSNull.null, kCIContextOutputColorSpace: NSNull.null}];
    }
    return self;
}

- (NSData *)convertTexture:(id<MTLTexture>)texture topDown:(BOOL)topDown
                    layout:(NSDictionary *)layout error:(NSError **)error {
    @autoreleasepool {
        @try {
            CIImage *image = [CIImage imageWithMTLTexture:texture options:@{kCIImageColorSpace: NSNull.null}];
            if (!image) @throw [NSException exceptionWithName:NSInvalidArgumentException
                reason:@"The analysis frame has an unsupported pixel format." userInfo:nil];
            if (!topDown) image = [image imageByApplyingTransform:CGAffineTransformMake(1, 0, 0, -1, 0, image.extent.size.height)];
            NSArray *crop = layout[@"crop"];
            image = [image imageByCroppingToRect:CGRectMake([crop[0] doubleValue], [crop[1] doubleValue],
                [crop[2] doubleValue], [crop[3] doubleValue])];
            image = [image imageByApplyingTransform:CGAffineTransformMakeTranslation(-image.extent.origin.x, -image.extent.origin.y)];
            image = [image imageByApplyingTransform:CGAffineTransformMakeRotation([layout[@"rotation"] doubleValue] * M_PI / 180.0)];
            image = [image imageByApplyingTransform:CGAffineTransformMakeTranslation(-image.extent.origin.x, -image.extent.origin.y)];
            NSUInteger width = [layout[@"width"] unsignedIntegerValue], height = [layout[@"height"] unsignedIntegerValue];
            image = [image imageByApplyingTransform:CGAffineTransformMakeScale(width / image.extent.size.width,
                height / image.extent.size.height)];
            image = [image imageByApplyingTransform:CGAffineTransformMake(1, 0, 0, -1, 0, height)];
            NSUInteger length = width * height;
            if (self.pixels.length != length) self.pixels = [NSMutableData dataWithLength:length];
            [self.context render:image toBitmap:self.pixels.mutableBytes rowBytes:width
                bounds:CGRectMake(0, 0, width, height) format:kCIFormatL8 colorSpace:nil];
            return self.pixels;
        } @catch (NSException *exception) {
            if (error) *error = [NSError errorWithDomain:@"com.latenitefilms.GyroflowToolbox.Analysis" code:1
                userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Metal could not prepare the analysis frame."}];
            return nil;
        }
    }
}
@end
