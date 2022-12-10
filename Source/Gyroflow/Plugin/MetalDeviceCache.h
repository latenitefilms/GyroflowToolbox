//
//  MetalDeviceCache.h
//  Gyroflow for Final Cut Pro
//
//  Created by Chris Hocking on 10/12/2022.
//

#import <Metal/Metal.h>
#import <FxPlug/FxPlugSDK.h>

@class MetalDeviceCacheItem;

@interface MetalDeviceCache : NSObject
{
    NSMutableArray<MetalDeviceCacheItem*>*    deviceCaches;
}

+ (MetalDeviceCache*)deviceCache;
+ (MTLPixelFormat)MTLPixelFormatForImageTile:(FxImageTile*)imageTile;

- (id<MTLDevice>)deviceWithRegistryID:(uint64_t)registryID;
- (id<MTLRenderPipelineState>)pipelineStateWithRegistryID:(uint64_t)registryID
                                              pixelFormat:(MTLPixelFormat)pixFormat;
- (id<MTLCommandQueue>)commandQueueWithRegistryID:(uint64_t)registryID
                                      pixelFormat:(MTLPixelFormat)pixFormat;
- (void)returnCommandQueueToCache:(id<MTLCommandQueue>)commandQueue;

@end
