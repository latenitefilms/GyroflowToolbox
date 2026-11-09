#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Creates consistently branded alerts for the application and FxPlug renderer.
@interface GyroflowAlertFactory : NSObject

/// Returns a new alert with the bundled Gyroflow Toolbox icon.
/// Use this factory for all Toolbox alerts and call it on the main thread.
+ (NSAlert *)makeAlert;

@end

NS_ASSUME_NONNULL_END
