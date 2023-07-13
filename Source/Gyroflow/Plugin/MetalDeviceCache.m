//
//  MetalDeviceCache.m
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 17/9/2022.
//

//---------------------------------------------------------
//
// In your app, a MTLDevice object is a thin abstraction for a GPU; you use it to communicate with a GPU.
// Metal creates a MTLDevice for each GPU. You get the default device object by calling MTLCreateSystemDefaultDevice.
// In macOS, where a Mac can have multiple GPUs, Metal chooses one of the GPUs as the default and returns that GPU’s
// device object.
//
// Metal represents other GPU-related entities, like compiled shaders, memory buffers and textures, as objects.
// To create these GPU-specific objects, you call methods on a MTLDevice or you call methods on objects created by
// a MTLDevice. All objects created directly or indirectly by a device object are usable only with that device object.
// Apps that use multiple GPUs will use multiple device objects and create a similar hierarchy of Metal objects for each.
//
//---------------------------------------------------------

#import "MetalDeviceCache.h"

const NSUInteger    kMaxCommandQueues   = 20;
static NSString*    kKey_InUse          = @"InUse";
static NSString*    kKey_CommandQueue   = @"CommandQueue";

static MetalDeviceCache*   gDeviceCache    = nil;

//---------------------------------------------------------
//
// Metal Device Cache Item:
//
//---------------------------------------------------------
@interface MetalDeviceCacheItem : NSObject

@property (readonly)    id<MTLDevice>                           gpuDevice;
@property (readonly)    id<MTLRenderPipelineState>              pipelineState;
@property (retain)      NSMutableArray<NSMutableDictionary*>*   commandQueueCache;
@property (readonly)    NSLock*                                 commandQueueCacheLock;
@property (readonly)    MTLPixelFormat                          pixelFormat;

- (instancetype)initWithDevice:(id<MTLDevice>)device
                   pixelFormat:(MTLPixelFormat)pixFormat;
- (id<MTLCommandQueue>)getNextFreeCommandQueue;
- (void)returnCommandQueue:(id<MTLCommandQueue>)commandQueue;
- (BOOL)containsCommandQueue:(id<MTLCommandQueue>)commandQueue;

@end

@implementation MetalDeviceCacheItem

//---------------------------------------------------------
// Initalise with MTLDevice & Pixel Format:
//---------------------------------------------------------
- (instancetype)initWithDevice:(id<MTLDevice>)device
                   pixelFormat:(MTLPixelFormat)pixFormat;
{
    self = [super init];
    
    if (self != nil)
    {
        //---------------------------------------------------------
        // Retain the MTLDevice:
        //---------------------------------------------------------
        _gpuDevice = [device retain];
        
        //---------------------------------------------------------
        // Create the Command Queues:
        //---------------------------------------------------------
        _commandQueueCache = [[NSMutableArray alloc] initWithCapacity:kMaxCommandQueues];
        for (NSUInteger i = 0; (_commandQueueCache != nil) && (i < kMaxCommandQueues); i++)
        {
            NSMutableDictionary*   commandDict = [NSMutableDictionary dictionary];
            [commandDict setObject:[NSNumber numberWithBool:NO]
                            forKey:kKey_InUse];
            
            //---------------------------------------------------------
            // To send work to the GPU, you need a command queue.
            // Metal uses command queues to schedule commands.
            // Create a command queue by asking the MTLDevice for one.
            //---------------------------------------------------------
            id<MTLCommandQueue> commandQueue    = [_gpuDevice newCommandQueue];
            [commandDict setObject:commandQueue
                            forKey:kKey_CommandQueue];
            
            [_commandQueueCache addObject:commandDict];
        }
        
        //---------------------------------------------------------
        // Load all the shader files with a .metal file extension
        // in the project:
        //---------------------------------------------------------
        id<MTLLibrary> defaultLibrary = [[_gpuDevice newDefaultLibrary] autorelease];
        
        //---------------------------------------------------------
        // Load the vertex function from the library:
        //---------------------------------------------------------
        id<MTLFunction> vertexFunction = [[defaultLibrary newFunctionWithName:@"vertexShader"] autorelease];
        
        //---------------------------------------------------------
        // Load the fragment function from the library:
        //---------------------------------------------------------
        id<MTLFunction> fragmentFunction = [[defaultLibrary newFunctionWithName:@"fragmentShader"] autorelease];
        
        //---------------------------------------------------------
        // Configure a pipeline descriptor that is used to create
        // a pipeline state:
        //---------------------------------------------------------
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[[MTLRenderPipelineDescriptor alloc] init] autorelease];
        pipelineStateDescriptor.label = @"Gyroflow Toolbox Pipeline";
        pipelineStateDescriptor.vertexFunction = vertexFunction;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction;
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = pixFormat;
        _pixelFormat = pixFormat;
        
        NSError* error = nil;
        _pipelineState = [_gpuDevice newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                    error:&error];
        if (error != nil) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to create pipeline state due to: %@", error.localizedDescription);
        }
        
        //---------------------------------------------------------
        // If the Command Queue Cache Exists, create a NSLock:
        //---------------------------------------------------------
        if (_commandQueueCache != nil) {
            _commandQueueCacheLock = [[NSLock alloc] init];
        }
        
        //---------------------------------------------------------
        // If something fails, release and return nil:
        //---------------------------------------------------------
        if ((_gpuDevice == nil) || (_commandQueueCache == nil) || (_commandQueueCacheLock == nil) || (_pipelineState == nil)) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to create MetalDeviceCacheItem.");
            [self release];
            self = nil;
        }
    }
    
    return self;
}

//---------------------------------------------------------
// Dealloc:
//---------------------------------------------------------
- (void)dealloc
{
    [_gpuDevice release];
    [_commandQueueCache release];
    [_commandQueueCacheLock release];
    [_pipelineState release];
    
    [super dealloc];
}

//---------------------------------------------------------
// Get the next free Command Queue:
//---------------------------------------------------------
- (id<MTLCommandQueue>)getNextFreeCommandQueue
{
    id<MTLCommandQueue> result = nil;
    
    [_commandQueueCacheLock lock];
    NSUInteger index = 0;
    while ((result == nil) && (index < kMaxCommandQueues)) {
        NSMutableDictionary*    nextCommandQueue    = [_commandQueueCache objectAtIndex:index];
        NSNumber*               inUse               = [nextCommandQueue objectForKey:kKey_InUse];
        if (![inUse boolValue]) {
            [nextCommandQueue setObject:[NSNumber numberWithBool:YES]
                                 forKey:kKey_InUse];
            result = [nextCommandQueue objectForKey:kKey_CommandQueue];
        }
        index++;
    }
    [_commandQueueCacheLock unlock];
    
    return result;
}

//---------------------------------------------------------
// Return the Command Queue back to the Cache:
//---------------------------------------------------------
- (void)returnCommandQueue:(id<MTLCommandQueue>)commandQueue
{
    [_commandQueueCacheLock lock];
    
    BOOL        found   = false;
    NSUInteger  index   = 0;
    while ((!found) && (index < kMaxCommandQueues))
    {
        NSMutableDictionary*    nextCommandQueuDict = [_commandQueueCache objectAtIndex:index];
        id<MTLCommandQueue>     nextCommandQueue    = [nextCommandQueuDict objectForKey:kKey_CommandQueue];
        if (nextCommandQueue == commandQueue)
        {
            found = YES;
            [nextCommandQueuDict setObject:[NSNumber numberWithBool:NO]
                                    forKey:kKey_InUse];
        }
        index++;
    }
    
    [_commandQueueCacheLock unlock];
}

//---------------------------------------------------------
// Does this Metal Device Cache Item contain this
// Command Queue?
//---------------------------------------------------------
- (BOOL)containsCommandQueue:(id<MTLCommandQueue>)commandQueue
{
    BOOL        found   = NO;
    NSUInteger  index   = 0;
    while ((!found) && (index < kMaxCommandQueues))
    {
        NSMutableDictionary*    nextCommandQueuDict = [_commandQueueCache objectAtIndex:index];
        id<MTLCommandQueue>     nextCommandQueue    = [nextCommandQueuDict objectForKey:kKey_CommandQueue];
        if (nextCommandQueue == commandQueue)
        {
            found = YES;
        }
        index++;
    }
    
    return found;
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
    
    if (self != nil)
    {
        NSArray<id<MTLDevice>>* devices = MTLCopyAllDevices();
        
        deviceCaches = [[NSMutableArray alloc] initWithCapacity:devices.count];
        
        for (id<MTLDevice> nextDevice in devices)
        {
            MetalDeviceCacheItem*  newCacheItem    = [[[MetalDeviceCacheItem alloc] initWithDevice:nextDevice
                                                                                       pixelFormat:MTLPixelFormatRGBA16Float] autorelease];
            [deviceCaches addObject:newCacheItem];
        }
        
        [devices release];
    }
    
    return self;
}

//---------------------------------------------------------
// Dealloc:
//---------------------------------------------------------
- (void)dealloc
{
    [deviceCaches release];
    
    [super dealloc];
}

//---------------------------------------------------------
// Get the MTLDevice from a GPU Registry ID:
//---------------------------------------------------------
- (id<MTLDevice>)deviceWithRegistryID:(uint64_t)registryID
{
    for (MetalDeviceCacheItem* nextCacheItem in deviceCaches)
    {
        if (nextCacheItem.gpuDevice.registryID == registryID)
        {
            return nextCacheItem.gpuDevice;
        }
    }
    
    return nil;
}

//---------------------------------------------------------
// Create new Pipeline State using GPU Registry ID:
//---------------------------------------------------------
- (id<MTLRenderPipelineState>)pipelineStateWithRegistryID:(uint64_t)registryID
                                              pixelFormat:(MTLPixelFormat)pixFormat
{
    //---------------------------------------------------------
    // If the pipeline state has already been cached,
    // returned the cached version:
    //---------------------------------------------------------
    for (MetalDeviceCacheItem* nextCacheItem in deviceCaches)
    {
        if ((nextCacheItem.gpuDevice.registryID == registryID)  &&
            (nextCacheItem.pixelFormat == pixFormat))
        {
            return nextCacheItem.pipelineState;
        }
    }
    
    //---------------------------------------------------------
    // Didn't find one, so create one with the right settings:
    //---------------------------------------------------------
    NSArray<id<MTLDevice>>* devices = MTLCopyAllDevices();
    id<MTLDevice>   device  = nil;
    for (id<MTLDevice> nextDevice in devices)
    {
        if (nextDevice.registryID == registryID)
        {
            device = nextDevice;
        }
    }
    
    id<MTLRenderPipelineState>  result  = nil;
    if (device != nil)
    {
        MetalDeviceCacheItem*   newCacheItem    = [[[MetalDeviceCacheItem alloc] initWithDevice:device
                                                                                    pixelFormat:pixFormat]
                                                    autorelease];
        if (newCacheItem != nil)
        {
            [deviceCaches addObject:newCacheItem];
            result = newCacheItem.pipelineState;
        }
    }
    [devices release];
    return result;
}

//---------------------------------------------------------
// Create new Command Queue using GPU Registry ID:
//---------------------------------------------------------
- (id<MTLCommandQueue>)commandQueueWithRegistryID:(uint64_t)registryID
                                      pixelFormat:(MTLPixelFormat)pixFormat;
{
    //---------------------------------------------------------
    // If the Command Queue has already been cached,
    // returned the cached version:
    //---------------------------------------------------------
    for (MetalDeviceCacheItem* nextCacheItem in deviceCaches)
    {
        if ((nextCacheItem.gpuDevice.registryID == registryID) &&
            (nextCacheItem.pixelFormat == pixFormat))
        {
            return [nextCacheItem getNextFreeCommandQueue];
        }
    }
    
    //---------------------------------------------------------
    // If we don't already have a cached version, we need to
    // find the right MTLDevice and create one with the same
    // pixel format:
    //---------------------------------------------------------
    NSArray<id<MTLDevice>>* devices = MTLCopyAllDevices();
    id<MTLDevice> device  = nil;
    for (id<MTLDevice> nextDevice in devices)
    {
        if (nextDevice.registryID == registryID)
        {
            device = nextDevice;
        }
    }
    
    id<MTLCommandQueue> result = nil;
    if (device != nil)
    {
        MetalDeviceCacheItem* newCacheItem = [[[MetalDeviceCacheItem alloc] initWithDevice:device
                                                                               pixelFormat:pixFormat] autorelease];
        if (newCacheItem != nil) {
            //---------------------------------------------------------
            // Add the new item to the cache:
            //---------------------------------------------------------
            [deviceCaches addObject:newCacheItem];
            result = [newCacheItem getNextFreeCommandQueue];
        }
    }
    
    //---------------------------------------------------------
    // Release the array of MTLDevice's:
    //---------------------------------------------------------
    [devices release];
    return result;
}

//---------------------------------------------------------
// Return Command Queue to Cache:
//---------------------------------------------------------
- (void)returnCommandQueueToCache:(id<MTLCommandQueue>)commandQueue;
{
    for (MetalDeviceCacheItem* nextCacheItem in deviceCaches)
    {
        if ([nextCacheItem containsCommandQueue:commandQueue]) {
            [nextCacheItem returnCommandQueue:commandQueue];
            break;
        }
    }
}

@end
