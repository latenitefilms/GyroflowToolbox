// Gyroflow Toolbox renderer process entry point.
#import <FxPlug/FxPlugSDK.h>
#import "gyroflow.h"

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        // Configure upstream's model override before FxPlug creates any worker threads. Changing
        // environment variables from a plug-in instance or an analysis callback would be unsafe.
        NSString *model = [NSBundle.mainBundle pathForResource:@"gmflow-scale2-regrefine6" ofType:@"bpk" inDirectory:@"Models"];
        NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
        NSString *storage = [support stringByAppendingPathComponent:@"Gyroflow Toolbox"];
        if (!model || !storage || setenv("GYROFLOW_GMFLOW_WEIGHTS", model.UTF8String, 1) != 0 ||
            setenv("GYROFLOW_GMFLOW_DEVICE", "hardware", 1) != 0) {
            NSLog(@"Gyroflow Toolbox could not locate its bundled analysis resources.");
            return EXIT_FAILURE;
        }
        const char *response = configureToolboxResources(storage.UTF8String, model.UTF8String);
        NSData *data = [NSData dataWithBytes:response length:strlen(response)];
        freeCString((char *)response);
        NSDictionary *result = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if (![result[@"ok"] boolValue]) {
            NSLog(@"Gyroflow Toolbox: %@", result[@"error"]);
            return EXIT_FAILURE;
        }
    }
    [FxPrincipal startServicePrincipal];
}
