#import "GyroflowAlertFactory.h"

@implementation GyroflowAlertFactory

+ (NSAlert *)makeAlert
{
    NSAlert *alert = [[NSAlert alloc] init];
    // Resolve the asset in our own bundle, including when running inside FxPlug.
    NSBundle *resourceBundle = [NSBundle bundleForClass:[GyroflowAlertFactory class]];
    alert.icon = [resourceBundle imageForResource:@"GyroflowToolbox"];
    return alert;
}

@end
