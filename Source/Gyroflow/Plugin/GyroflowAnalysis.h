#import <FxPlug/FxPlugSDK.h>
@class GyroflowPlugIn;

NS_ASSUME_NONNULL_BEGIN

/// Converts an owned Rust response into a Foundation result and always frees the response.
FOUNDATION_EXPORT NSDictionary * _Nullable GyroflowBridgeResult(const char *response, NSError **error);
/// Creates a host-presentable error without presenting UI on an analysis thread.
FOUNDATION_EXPORT BOOL GyroflowAnalysisError(NSError **error, NSString *message);

/// Thin FxPlug lifecycle and Metal image adapter. Rust owns analysis, presets and project data.
@interface GyroflowAnalysis : NSObject <FxAnalyzer>
- (instancetype)initWithPlugin:(GyroflowPlugIn *)plugin;
- (BOOL)startMode:(NSString *)mode project:(NSString *)project originalProject:(NSString *)original
      parameters:(NSString *)parameters error:(NSError **)error;
- (void)cancel;
@end

NS_ASSUME_NONNULL_END
