//
//  MetalDeviceCache.m
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 17/9/2022.
//

#import "MetalDeviceCache.h"

static MetalDeviceCache* gDeviceCache = nil;

//---------------------------------------------------------
//
// Metal Device Cache Item:
//
//---------------------------------------------------------
@interface MetalDeviceCacheItem : NSObject
@property (nonatomic, strong, readonly) id<MTLDevice> gpuDevice;
@property (nonatomic, strong, readonly) id<MTLCommandQueue> commandQueue;

- (instancetype)initWithDevice:(id<MTLDevice>)device;
@end

@implementation MetalDeviceCacheItem

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    self = [super init];
    if (!self) return nil;

    _gpuDevice = device;

    return self;
}

@end

//---------------------------------------------------------
//
// Metal Device Cache:
//
//---------------------------------------------------------
@implementation MetalDeviceCache

+ (MTLPixelFormat)MTLPixelFormatForImageTile:(FxImageTile*)imageTile
{
    MTLPixelFormat  result  = MTLPixelFormatRGBA16Float;
    
    switch (imageTile.ioSurface.pixelFormat)
    {
        case kCVPixelFormatType_128RGBAFloat:
            result = MTLPixelFormatRGBA32Float;
            break;
            
        case kCVPixelFormatType_32BGRA:
            result = MTLPixelFormatBGRA8Unorm;
            break;
            
        default:
            break;
    }
    
    return result;
}

//---------------------------------------------------------
// Get the Device Cache:
//---------------------------------------------------------
+ (MetalDeviceCache*)deviceCache;
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gDeviceCache = [[MetalDeviceCache alloc] init];
    });
    
    return gDeviceCache;
}

//---------------------------------------------------------
// Initialize the Metal Device Cache:
//---------------------------------------------------------
- (instancetype)init
{
    self = [super init];
    if (!self) return nil;

    NSArray<id<MTLDevice>> *devices = MTLCopyAllDevices();

    NSMutableDictionary<NSNumber*, MetalDeviceCacheItem*> *tmp = [[NSMutableDictionary alloc] initWithCapacity:devices.count];

    for (id<MTLDevice> d in devices) {
        MetalDeviceCacheItem *item = [[MetalDeviceCacheItem alloc] initWithDevice:d];
        if (!item) continue;
        tmp[@(d.registryID)] = item;
    }

    _cacheByRegistryID = [tmp copy]; // immutable
    return self;
}

//---------------------------------------------------------
// Get the MTLDevice from a GPU Registry ID:
//---------------------------------------------------------
- (id<MTLDevice>)deviceWithRegistryID:(uint64_t)registryID
{
    return _cacheByRegistryID[@(registryID)].gpuDevice;
}

@end
