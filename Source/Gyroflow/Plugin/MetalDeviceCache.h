//
//  MetalDeviceCache.h
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 17/9/2022.
//

#import <Metal/Metal.h>
#import <FxPlug/FxPlugSDK.h>

@class MetalDeviceCacheItem;

@interface MetalDeviceCache : NSObject
{
    NSMutableDictionary<NSNumber*, MetalDeviceCacheItem*> *_cacheByRegistryID;
}
+ (MetalDeviceCache*)deviceCache;
- (id<MTLDevice>)deviceWithRegistryID:(uint64_t)registryID;
@end
