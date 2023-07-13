//
//  BRAWMetadataReader.mm
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 26/10/2022.
//

#include "BRAWMetadataReader.h"

#import "BRAWParameters.h"

#include "BlackmagicRawAPI.h"

#include <algorithm>        // std::min
#include <atomic>           // std::atomic
#include <cassert>          // assert
#include <chrono>           // std::chrono
#include <cstdint>          // uint32_t
#include <iostream>         // std::cout, std::cerr
#include <thread>           // std::thread

#include <variant>          // std::variant
#include <vector>           // std::vector

#include <ImageIO/ImageIO.h>
#include <CoreServices/CoreServices.h>

//---------------------------------------------------------
// We can use the `using` directive to bring all the
// identifiers of the namespace std as if they were
// declared globally:
//---------------------------------------------------------
using namespace std;

//---------------------------------------------------------
// BlackmagicRawVariantType - Variant types that may be
// stored as metadata:
//---------------------------------------------------------
using VARIANT = Variant;
using VARTYPE = BlackmagicRawVariantType;

//---------------------------------------------------------
// To help with debugging:
//---------------------------------------------------------
#define VERIFY(condition) assert(SUCCEEDED(condition))

//---------------------------------------------------------
// Callback for the `-parameterChanged` method:
//
// Central callback object for entire codec. Jobs submitted
// to any clip created by this codec will have their
// results provided through these function calls.
//---------------------------------------------------------
class MetadataCameraCodecCallback : public IBlackmagicRawCallback
{
public:
    explicit MetadataCameraCodecCallback() = default;
    virtual ~MetadataCameraCodecCallback()
    {
        assert(m_refCount == 0);
        SetFrame(nullptr);
    }

    IBlackmagicRawFrame*    GetFrame() { return m_frame; }

    virtual void ReadComplete(IBlackmagicRawJob* readJob, HRESULT result, IBlackmagicRawFrame* frame)
    {
        if (result == S_OK) {
            SetFrame(frame);
        }
    }

    virtual void ProcessComplete(IBlackmagicRawJob* job, HRESULT result, IBlackmagicRawProcessedImage* processedImage) {}
    virtual void DecodeComplete(IBlackmagicRawJob*, HRESULT) {}
    virtual void TrimProgress(IBlackmagicRawJob*, float) {}
    virtual void TrimComplete(IBlackmagicRawJob*, HRESULT) {}
    virtual void SidecarMetadataParseWarning(IBlackmagicRawClip*, CFStringRef, uint32_t, CFStringRef) {}
    virtual void SidecarMetadataParseError(IBlackmagicRawClip*, CFStringRef, uint32_t, CFStringRef) {}
    virtual void PreparePipelineComplete(void*, HRESULT) {}

    virtual HRESULT STDMETHODCALLTYPE QueryInterface(REFIID, LPVOID*)
    {
        return E_NOTIMPL;
    }

    virtual ULONG STDMETHODCALLTYPE AddRef(void)
    {
        return ++m_refCount;
    }

    virtual ULONG STDMETHODCALLTYPE Release(void)
    {
        const int32_t newRefValue = --m_refCount;

        if (newRefValue == 0)
        {
            delete this;
        }

        assert(newRefValue >= 0);
        return newRefValue;
    }

private:

    void SetFrame(IBlackmagicRawFrame* frame)
    {
        if (m_frame != nullptr)
            m_frame->Release();
        m_frame = frame;
        if (m_frame != nullptr)
            m_frame->AddRef();
    }

    IBlackmagicRawFrame* m_frame = nullptr;
    std::atomic<int32_t> m_refCount = {0};
};

//---------------------------------------------------------
// Main class performing the rendering:
//---------------------------------------------------------
@implementation BRAWMetadataReader
{
    //---------------------------------------------------------
    // BRAW Factory:
    //---------------------------------------------------------
    IBlackmagicRawFactory*              _factory;
    IBlackmagicRaw*                     _codec;
    IBlackmagicRawConfiguration*        _config;
}

//---------------------------------------------------------
// Deallocates the memory occupied by the receiver:
//---------------------------------------------------------
- (void)dealloc
{
    if (_config != nullptr) {
        _config->Release();
    }

    if (_codec != nullptr) {
        _codec->Release();
    }

    if (_factory != nullptr) {
        _factory->Release();
    }

    [super dealloc];
    
    //NSLog(@"[Gyroflow Toolbox Renderer] Successfully deallocated BRAWMetadataReader.");
}

//---------------------------------------------------------
// Process Metadata:
//---------------------------------------------------------
- (NSMutableDictionary*) newProcessMetadataWithIterator:(IBlackmagicRawMetadataIterator*)metadataIterator
{
    NSMutableDictionary *metadata = [NSMutableDictionary new];
    NSString *currentKey    = @"";
    NSString *currentValue  = @"";
    
    CFStringRef key = nullptr;
    Variant value;
    HRESULT result;

    while (SUCCEEDED(metadataIterator->GetKey(&key)))
    {
        //---------------------------------------------------------
        // Set the current key:
        //---------------------------------------------------------
        currentKey = [NSString stringWithString:(NSString *)key];

        VariantInit(&value);
        result = metadataIterator->GetData(&value);
        if (result != S_OK)
        {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get data from IBlackmagicRawMetadataIterator.");
            break;
        }

        //---------------------------------------------------------
        // Set the current values:
        //---------------------------------------------------------
        BlackmagicRawVariantType variantType = value.vt;
        switch (variantType)
        {
            case blackmagicRawVariantTypeS16:
            {
                short s16 = value.iVal;
                currentValue = [NSString stringWithFormat:@"%hd", s16];
            }
            break;
            case blackmagicRawVariantTypeU16:
            {
                unsigned short u16 = value.uiVal;
                currentValue = [NSString stringWithFormat:@"%hd", u16];
            }
            break;
            case blackmagicRawVariantTypeS32:
            {
                int i32 = value.intVal;
                currentValue = [NSString stringWithFormat:@"%d", i32];
            }
            break;
            case blackmagicRawVariantTypeU32:
            {
                unsigned int u32 = value.uintVal;
                currentValue = [NSString stringWithFormat:@"%u", u32];
            }
            break;
            case blackmagicRawVariantTypeFloat32:
            {
                float f32 = value.fltVal;
                currentValue = [NSString stringWithFormat:@"%g", f32];
            }
            break;
            case blackmagicRawVariantTypeString:
            {
                currentValue = [NSString stringWithString:(NSString *)value.bstrVal];
            }
            break;
            case blackmagicRawVariantTypeSafeArray:
            {
                currentValue = @"";
                
                SafeArray* safeArray = value.parray;

                void* safeArrayData = nullptr;
                result = SafeArrayAccessData(safeArray, &safeArrayData);
                if (result != S_OK)
                {
                    NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to access safeArray data.");
                    break;
                }

                BlackmagicRawVariantType arrayVarType;
                result = SafeArrayGetVartype(safeArray, &arrayVarType);
                if (result != S_OK)
                {
                    NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get BlackmagicRawVariantType from safeArray.");
                    break;
                }

                long lBound;
                result = SafeArrayGetLBound(safeArray, 1, &lBound);
                if (result != S_OK)
                {
                    NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get LBound from safeArray.");
                    break;
                }

                long uBound;
                result = SafeArrayGetUBound(safeArray, 1, &uBound);
                if (result != S_OK)
                {
                    NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get UBound from safeArray.");
                    break;
                }

                long safeArrayLength = (uBound - lBound) + 1;
                long arrayLength = safeArrayLength > 32 ? 32 : safeArrayLength;

                for (int i = 0; i < arrayLength; ++i)
                {
                    switch (arrayVarType)
                    {
                        case blackmagicRawVariantTypeU8:
                        {
                            int u8 = static_cast<int>(static_cast<unsigned char*>(safeArrayData)[i]);
                            if (i > 0) {
                                currentValue = [currentValue stringByAppendingString:@", "];
                            }
                            currentValue = [currentValue stringByAppendingFormat:@"%d", u8];
                        }
                        break;
                        case blackmagicRawVariantTypeS16:
                        {
                            short s16 = static_cast<short*>(safeArrayData)[i];
                            if (i > 0) {
                                currentValue = [currentValue stringByAppendingString:@", "];
                            }
                            currentValue = [currentValue stringByAppendingFormat:@"%hd", s16];
                        }
                        break;
                        case blackmagicRawVariantTypeU16:
                        {
                            unsigned short u16 = static_cast<unsigned short*>(safeArrayData)[i];
                            if (i > 0) {
                                currentValue = [currentValue stringByAppendingString:@", "];
                            }
                            currentValue = [currentValue stringByAppendingFormat:@"%hd", u16];
                        }
                        break;
                        case blackmagicRawVariantTypeS32:
                        {
                            int i32 = static_cast<int*>(safeArrayData)[i];
                            if (i > 0) {
                                currentValue = [currentValue stringByAppendingString:@", "];
                            }
                            currentValue = [currentValue stringByAppendingFormat:@"%d", i32];
                        }
                        break;
                        case blackmagicRawVariantTypeU32:
                        {
                            unsigned int u32 = static_cast<unsigned int*>(safeArrayData)[i];
                            if (i > 0) {
                                currentValue = [currentValue stringByAppendingString:@", "];
                            }
                            currentValue = [currentValue stringByAppendingFormat:@"%u", u32];
                        }
                        break;
                        case blackmagicRawVariantTypeFloat32:
                        {
                            float f32 = static_cast<float*>(safeArrayData)[i];
                            if (i > 0) {
                                currentValue = [currentValue stringByAppendingString:@", "];
                            }
                            currentValue = [currentValue stringByAppendingFormat:@"%g", f32];
                        }
                        break;
                        default:
                            break;
                    }
                }
            }
            default:
                break;
        }

        VariantClear(&value);

        //---------------------------------------------------------
        // Add metadata to dictionary:
        //---------------------------------------------------------
        [metadata setObject:currentValue forKey:currentKey];
        
        metadataIterator->Next();
    }
    return metadata;
}

//---------------------------------------------------------
// Initialize the MTKView:
//---------------------------------------------------------
- (nonnull instancetype)init
{
    self = [super init];
    if(self)
    {
        HRESULT result = S_OK;
                
        //---------------------------------------------------------
        // Create a 'factory' for BRAW processing.
        // IBlackmagicRawFactory is the API entry point.
        //---------------------------------------------------------
        _factory = CreateBlackmagicRawFactoryInstance();
        if (_factory == nullptr)
        {
            NSLog(@"[Gyroflow Toolbox Renderer] FATAL ERROR - Failed to create IBlackmagicRawFactory.");
            return self;
        }

        //---------------------------------------------------------
        // Create a codec from the factory:
        //---------------------------------------------------------
        result = _factory->CreateCodec(&_codec);
        if (result != S_OK)
        {
            NSLog(@"[Gyroflow Toolbox Renderer] FATAL ERROR - Failed to create IBlackmagicRaw.");
            return self;
        }

        //---------------------------------------------------------
        // Query the codec interface.
        //
        // Each codec interface will have its own memory storage
        // and decoder. When decoding multiple clips via one codec,
        // first in first out ordering will apply.
        //---------------------------------------------------------
        result = _codec->QueryInterface(IID_IBlackmagicRawConfiguration, (void**)&_config);
        if (result != S_OK)
        {
            NSLog(@"[Gyroflow Toolbox Renderer] FATAL ERROR - Failed to get IID_IBlackmagicRawConfiguration.");
            return self;
        }
    }

    return self;
}

//---------------------------------------------------------
// Read Metadata From Path:
//---------------------------------------------------------
- (BRAWParameters*)readMetadataFromPath:(nonnull NSString*)brawFilePath
{
    //---------------------------------------------------------
    // A shared result:
    //---------------------------------------------------------
    HRESULT result = S_OK;
    
    //---------------------------------------------------------
    // Storage for frame metadata:
    //---------------------------------------------------------
    unsigned long long  currentFrame        = 0;
    
    uint64_t            frameCount          = 0;
    float               frameRate           = 0;
    
    uint32_t            width               = 0;
    uint32_t            height              = 0;
    
    NSString*           startTimecode       = nil;
    
    uint32_t            baseFrameIndex      = 0;
    bool                isDropFrameTimecode = NO;
    
    //---------------------------------------------------------
    // Audio:
    //---------------------------------------------------------
    uint64_t audioSamples                   = 0;
    uint32_t audioBitDepth                  = 0;
    uint32_t audioChannelCount              = 0;
    uint32_t audioSampleRate                = 0;
    
    //---------------------------------------------------------
    // "Clip Metadata" Group:
    //---------------------------------------------------------
    VARIANT currentColorScienceGen;
    VARIANT currentGamut;
    VARIANT currentGamma;
    VARIANT currentHighlightRecovery;
    VARIANT currentGamutCompression;
    
    NSNumber *colorScienceGen               = nil;
    NSString *gamut                         = nil;
    NSString *gamma                         = nil;
    NSNumber *highlightRecovery             = 0;
    NSNumber *gamutCompression              = 0;
    
    NSArray *colorScienceVersionList        = nil;
    NSArray *gamutList                      = nil;
    NSArray *gammaList                      = nil;
    
    //---------------------------------------------------------
    // "Frame Metadata" Group:
    //---------------------------------------------------------
    VARIANT currentISO;
    VARIANT currentExposure;
    VARIANT currentWhiteBalanceKelvin;
    VARIANT currentWhiteBalanceTint;
    VARIANT currentLUTMode;
    
    NSNumber *iso                           = nil;
    NSNumber *exposure                      = nil;
    NSNumber *whiteBalanceKelvin            = nil;
    NSNumber *whiteBalanceTint              = nil;
    
    NSString *lutMode                       = nil;
    
    NSArray *isoList                        = nil;
    
    double exposureMin                      = 0.0;
    double exposureMax                      = 0.0;

    double whiteBalanceKelvinMin            = 0.0;
    double whiteBalanceKelvinMax            = 0.0;
    
    double whiteBalanceTintMin              = 0.0;
    double whiteBalanceTintMax              = 0.0;
    
    NSArray *lutModeList                    = nil;

    //---------------------------------------------------------
    // "Custom Gamma Controls" Group::
    //---------------------------------------------------------
    VARIANT currentToneCurveSaturation;
    VARIANT currentToneCurveContrast;
    VARIANT currentToneCurveMidpoint;
    VARIANT currentToneCurveHighlights;
    VARIANT currentToneCurveShadows;
    VARIANT currentToneCurveBlackLevel;
    VARIANT currentToneCurveWhiteLevel;
    VARIANT currentToneCurveVideoBlackLevel;
    
    NSNumber *toneCurveSaturation           = nil;
    NSNumber *toneCurveContrast             = nil;
    NSNumber *toneCurveMidpoint             = nil;
    NSNumber *toneCurveHighlights           = nil;
    NSNumber *toneCurveShadows              = nil;
    NSNumber *toneCurveBlackLevel           = nil;
    NSNumber *toneCurveWhiteLevel           = nil;
    NSNumber *toneCurveVideoBlackLevel      = nil;

    double toneCurveSaturationMin           = 0.0;
    double toneCurveSaturationMax           = 0.0;
    
    double toneCurveContrastMin             = 0.0;
    double toneCurveContrastMax             = 0.0;
    
    double toneCurveMidpointMin             = 0.0;
    double toneCurveMidpointMax             = 0.0;
    
    double toneCurveHighlightsMin           = 0.0;
    double toneCurveHighlightsMax           = 0.0;
    
    double toneCurveShadowsMin              = 0.0;
    double toneCurveShadowsMax              = 0.0;
    
    double toneCurveBlackLevelMin           = 0.0;
    double toneCurveBlackLevelMax           = 0.0;
    
    double toneCurveWhiteLevelMin           = 0.0;
    double toneCurveWhiteLevelMax           = 0.0;
    
    //---------------------------------------------------------
    // Read Only:
    //---------------------------------------------------------
    bool isoReadOnly                       = NO;
    bool exposureReadOnly                  = NO;
    bool whiteBalanceKelvinReadOnly        = NO;
    bool whiteBalanceTintReadOnly          = NO;
    bool colorScienceVersionReadOnly       = NO;
    bool gamutReadOnly                     = NO;
    bool gammaReadOnly                     = NO;
    bool highlightRecoveryReadOnly         = NO;
    bool gamutCompressionReadOnly          = NO;
    bool lutModeReadOnly                   = NO;
    
    bool toneCurveSaturationReadOnly       = NO;
    bool toneCurveContrastReadOnly         = NO;
    bool toneCurveMidpointReadOnly         = NO;
    bool toneCurveHighlightsReadOnly       = NO;
    bool toneCurveShadowsReadOnly          = NO;
    bool toneCurveBlackLevelReadOnly       = NO;
    bool toneCurveWhiteLevelReadOnly       = NO;
    bool toneCurveVideoBlackLevelReadOnly  = NO;
    
    //---------------------------------------------------------
    // Metadata:
    //---------------------------------------------------------
    NSMutableDictionary *clipMetadata       = nil;
    NSMutableDictionary *frameMetadata      = nil;
    
    //---------------------------------------------------------
    // Make a copy of the BRAW file path (or else it'll crash):
    //---------------------------------------------------------
    CFStringRef pathToBRAWFile                    = (__bridge CFStringRef)[brawFilePath copy];

    //---------------------------------------------------------
    // Setup our BRAW API objects:
    //---------------------------------------------------------
    IBlackmagicRawClip* clip                                    = nullptr;
    IBlackmagicRawClipEx* clipEx                                = nullptr;
    IBlackmagicRawFrame* frame                                  = nullptr;
    IBlackmagicRawClipProcessingAttributes* attributes          = nullptr;
    IBlackmagicRawFrameProcessingAttributes* frameAttributes    = nullptr;
    MetadataCameraCodecCallback* callback                       = nullptr;
    IBlackmagicRawClipAudio* audio                              = nullptr;
    IBlackmagicRawMetadataIterator* clipMetadataIterator        = nullptr;
    IBlackmagicRawMetadataIterator* frameMetadataIterator       = nullptr;
    
    //---------------------------------------------------------
    // We use a do loop here so we can easily break and
    // continue as required.
    //---------------------------------------------------------
    do
    {
        //---------------------------------------------------------
        // Open Clip:
        //---------------------------------------------------------
        result = _codec->OpenClip(pathToBRAWFile, &clip);
        if (result != S_OK)
        {
            NSLog(@"[Gyroflow Toolbox Renderer] FATAL ERROR - Failed to open IBlackmagicRawClip in readMetadataFromPath.");
            break;
        }

        //---------------------------------------------------------
        // Query the Extended Clip Interface:
        //---------------------------------------------------------
        result = clip->QueryInterface(IID_IBlackmagicRawClipEx, (void**)&clipEx);
        if (result != S_OK)
        {
            NSLog(@"[Gyroflow Toolbox Renderer] FATAL ERROR - Failed to get IID_IBlackmagicRawClipEx.");
            break;
        }
        
        //---------------------------------------------------------
        // Get base frame index and drop frame status:
        //---------------------------------------------------------
        result = clipEx->QueryTimecodeInfo(&baseFrameIndex, &isDropFrameTimecode);
        if (result != S_OK)
        {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get Timecode Info.");
            
            
            //---------------------------------------------------------
            // NOTE: BRAW files from the Panasonic S1H seem to be
            //       unable to query the timecode info. I'm unsure if
            //       this is a bug in the BRAW SDK or not.
            //---------------------------------------------------------
            //break;
        }
        
        //---------------------------------------------------------
        // Query the Audio Interface:
        //---------------------------------------------------------
        result = clip->QueryInterface(IID_IBlackmagicRawClipAudio, (void**)&audio);
        if (result != S_OK)
        {
            NSLog(@"[Gyroflow Toolbox Renderer] FATAL ERROR - Failed to get IID_IBlackmagicRawClipAudio.");
            break;
        }
                
        //---------------------------------------------------------
        // Get Audio Samples:
        //---------------------------------------------------------
        result = audio->GetAudioSampleCount(&audioSamples);
        if (result != S_OK)
        {
            NSLog(@"[Gyroflow Toolbox Renderer] FATAL ERROR - Failed to get Audio Sample Count.");
            break;
        }

        //---------------------------------------------------------
        // Get Audio Bit Depth:
        //---------------------------------------------------------
        result = audio->GetAudioBitDepth(&audioBitDepth);
        if (result != S_OK)
        {
            NSLog(@"[Gyroflow Toolbox Renderer] FATAL ERROR - Failed to get Audio Bit Depth.");
            break;
        }

        //---------------------------------------------------------
        // Get Audio Channel Count:
        //---------------------------------------------------------
        result = audio->GetAudioChannelCount(&audioChannelCount);
        if (result != S_OK)
        {
            NSLog(@"[Gyroflow Toolbox Renderer] FATAL ERROR - Failed to get Audio Channel Count.");
            break;
        }

        //---------------------------------------------------------
        // Get Audio Sample Rate:
        //---------------------------------------------------------
        result = audio->GetAudioSampleRate(&audioSampleRate);
        if (result != S_OK)
        {
            NSLog(@"[Gyroflow Toolbox Renderer] FATAL ERROR - Failed to get Audio Sample Rate.");
            break;
        }
        
        //---------------------------------------------------------
        // Get the clip's frame count:
        //---------------------------------------------------------
        result = clip->GetFrameCount(&frameCount);
        if (result != S_OK)
        {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get the clip's frame count.");
            break;
        }

        //---------------------------------------------------------
        // Get the clip's frame count:
        //---------------------------------------------------------
        result = clip->GetFrameRate(&frameRate);
        if (result != S_OK)
        {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get the clip's frame rate.");
            break;
        }
        
        //---------------------------------------------------------
        // Get the clip's width:
        //---------------------------------------------------------
        result = clip->GetWidth(&width);
        if (result != S_OK)
        {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get the clip's width.");
            break;
        }
        
        //---------------------------------------------------------
        // Get the clip's height:
        //---------------------------------------------------------
        result = clip->GetHeight(&height);
        if (result != S_OK)
        {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get the clip's height.");
            break;
        }
       
        //---------------------------------------------------------
        // Get the start timecode:
        //---------------------------------------------------------
        CFStringRef startTimecodeRef;
        result = clip->GetTimecodeForFrame(0, &startTimecodeRef);
        if (result != S_OK)
        {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get the clip's start timecode.");
            break;
        }
        startTimecode = (NSString *)startTimecodeRef;
        
        //---------------------------------------------------------
        // Setup a new callback:
        //---------------------------------------------------------
        callback = new MetadataCameraCodecCallback();
        callback->AddRef();
        result = _codec->SetCallback(callback);
        if (result != S_OK)
        {
            NSLog(@"[Gyroflow Toolbox Renderer] FATAL ERROR - Failed to set IBlackmagicRawCallback in parameterChanged.");
            break;
        }

        //---------------------------------------------------------
        // Get Clip Metadata Iterator:
        //---------------------------------------------------------
        result = clip->GetMetadataIterator(&clipMetadataIterator);
        if (result != S_OK)
        {
            NSLog(@"[Gyroflow Toolbox Renderer] FATAL ERROR - Failed to get clip IBlackmagicRawMetadataIterator.");
            break;
        }
        
        //---------------------------------------------------------
        // Create the new Job:
        //---------------------------------------------------------
        IBlackmagicRawJob* readJob = nullptr;
        result = clip->CreateJobReadFrame(currentFrame, &readJob);
        if (result != S_OK)
        {
            NSLog(@"[Gyroflow Toolbox Renderer] FATAL ERROR - Failed to get IBlackmagicRawJob in parameterChanged.");
            break;
        }

        //---------------------------------------------------------
        // Submit the readJob:
        //---------------------------------------------------------
        result = readJob->Submit();

        //---------------------------------------------------------
        // Release the readJob after it's been submitted:
        //---------------------------------------------------------
        readJob->Release();

        //---------------------------------------------------------
        // Make sure the job submitted successfully:
        //---------------------------------------------------------
        if (result != S_OK)
        {
            NSLog(@"[Gyroflow Toolbox Renderer] FATAL ERROR - Failed to submit IBlackmagicRawJob in parameterChanged.");
            break;
        }

        //---------------------------------------------------------
        // Flush Jobs (this is a blocking call):
        //---------------------------------------------------------
        _codec->FlushJobs();

        //---------------------------------------------------------
        // Get the frame:
        //---------------------------------------------------------
        frame = callback->GetFrame();
        if (frame == nullptr)
        {
            NSLog(@"[Gyroflow Toolbox Renderer] FATAL ERROR - Failed to get IBlackmagicRawFrame in parameterChanged.");
            break;
        }

        //---------------------------------------------------------
        // Get Frame Metadata Iterator:
        //---------------------------------------------------------
        result = frame->GetMetadataIterator(&frameMetadataIterator);
        if (result != S_OK)
        {
            NSLog(@"[Gyroflow Toolbox Renderer] FATAL ERROR - Failed to get frame IBlackmagicRawMetadataIterator.");
            break;
        }
        
        //---------------------------------------------------------
        // Get Clip Attributes Interface:
        //---------------------------------------------------------
        clip->QueryInterface(IID_IBlackmagicRawClipProcessingAttributes, (void**)&attributes);
        if (attributes == nullptr)
        {
            NSLog(@"[Gyroflow Toolbox Renderer] FATAL ERROR - Failed to create IBlackmagicRawClipProcessingAttributes in parameterChanged.");
            break;
        }

        //---------------------------------------------------------
        // Get Frame Attributes Interface:
        //---------------------------------------------------------
        frame->QueryInterface(IID_IBlackmagicRawFrameProcessingAttributes, (void**)&frameAttributes);
        if (frameAttributes == nullptr)
        {
            NSLog(@"[Gyroflow Toolbox Renderer] FATAL ERROR - Failed to create IBlackmagicRawFrameProcessingAttributes in parameterChanged.");
            break;
        }

        //---------------------------------------------------------
        // Get a list of available Color Science Generations:
        //---------------------------------------------------------
        uint32_t colorScienceGenCount   = 0;
        result = attributes->GetClipAttributeList(blackmagicRawClipProcessingAttributeColorScienceGen, nullptr, &colorScienceGenCount, &colorScienceVersionReadOnly);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get list of Color Science Generations in BRAW Metadata Reader.");
        } else {
            vector<VARIANT> colorScienceGenArray(colorScienceGenCount);
            attributes->GetClipAttributeList(blackmagicRawClipProcessingAttributeColorScienceGen, &colorScienceGenArray[0], &colorScienceGenCount, nullptr);
            NSMutableArray *list = [[[NSMutableArray alloc] init] autorelease];
            for (const auto& v : colorScienceGenArray) {
                [list addObject:[NSString stringWithFormat:@"%d", v.uiVal]];
            }
            colorScienceVersionList = list;
        }

        //---------------------------------------------------------
        // Get current Color Science Generation:
        //---------------------------------------------------------
        result = attributes->GetClipAttribute(blackmagicRawClipProcessingAttributeColorScienceGen, &currentColorScienceGen);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get current Color Science Generation in BRAW Metadata Reader.");
        }
        colorScienceGen = [NSNumber numberWithInt:currentColorScienceGen.uiVal];
        
        //---------------------------------------------------------
        // Get a list of available Gamut options:
        //---------------------------------------------------------
        uint32_t gamutCount   = 0;
        result = attributes->GetClipAttributeList(blackmagicRawClipProcessingAttributeGamut, nullptr, &gamutCount, &gamutReadOnly);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get Gamut options in BRAW Metadata Reader.");
        }  else {
            vector<VARIANT> gamutArray(gamutCount);
            attributes->GetClipAttributeList(blackmagicRawClipProcessingAttributeGamut, &gamutArray[0], &gamutCount, nullptr);
            NSMutableArray *list = [[[NSMutableArray alloc] init] autorelease];
            for (const auto& v : gamutArray) {
                [list addObject:[NSString stringWithFormat:@"%@", v.bstrVal]];
            }
            gamutList = list;
        }

        //---------------------------------------------------------
        // Get current Gamut:
        //---------------------------------------------------------
        result = attributes->GetClipAttribute(blackmagicRawClipProcessingAttributeGamut, &currentGamut);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get current Gamut in BRAW Metadata Reader.");
        }
        gamut = (__bridge NSString *)currentGamut.bstrVal;

        //---------------------------------------------------------
        // Get a list of available Gamma options:
        //---------------------------------------------------------
        uint32_t gammaCount = 0;
        result = attributes->GetClipAttributeList(blackmagicRawClipProcessingAttributeGamma, nullptr, &gammaCount, &gammaReadOnly);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get Gamma options in BRAW Metadata Reader.");
        } else {
            vector<VARIANT> gammaArray(gammaCount);
            attributes->GetClipAttributeList(blackmagicRawClipProcessingAttributeGamma, &gammaArray[0], &gammaCount, nullptr);
            NSMutableArray *list = [[[NSMutableArray alloc] init] autorelease];
            for (const auto& v : gammaArray) {
                [list addObject:[NSString stringWithFormat:@"%@", v.bstrVal]];
            }
            gammaList = list;
        }

        //---------------------------------------------------------
        // Get current Gamma:
        //---------------------------------------------------------
        result = attributes->GetClipAttribute(blackmagicRawClipProcessingAttributeGamma, &currentGamma);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get current Gamma in BRAW Metadata Reader.");
        }
        gamma = (__bridge NSString *)currentGamma.bstrVal;
        
        
        //---------------------------------------------------------
        // Get current Highlight Recovery:
        //---------------------------------------------------------
        result = attributes->GetClipAttributeRange(blackmagicRawClipProcessingAttributeHighlightRecovery, nullptr, nullptr, &highlightRecoveryReadOnly);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get Highlight Recovery Ranges in BRAW Metadata Reader.");
        }
        result = attributes->GetClipAttribute(blackmagicRawClipProcessingAttributeHighlightRecovery, &currentHighlightRecovery);
        if (result != S_OK) {
           NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get current Highlight Recovery in BRAW Metadata Reader.");
        }
        highlightRecovery = [NSNumber numberWithInt:currentHighlightRecovery.uiVal];
        
        //---------------------------------------------------------
        // Get current Gamut Compression:
        //---------------------------------------------------------
        result = attributes->GetClipAttributeRange(blackmagicRawClipProcessingAttributeGamutCompressionEnable, nullptr, nullptr, &gamutCompressionReadOnly);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get Gamut Compression Ranges in BRAW Metadata Reader.");
        }
        result = attributes->GetClipAttribute(blackmagicRawClipProcessingAttributeGamutCompressionEnable, &currentGamutCompression);
        if (result != S_OK) {
           NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get current Gamut Compression in BRAW Metadata Reader.");
        }
        gamutCompression = [NSNumber numberWithInt:currentGamutCompression.uiVal];
        
        //---------------------------------------------------------
        // Get a list of available ISO options:
        //---------------------------------------------------------
        uint32_t isoCount   = 0;
        result = attributes->GetISOList(nullptr, &isoCount, &isoReadOnly);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get ISO list in BRAW Metadata Reader.");
        } else {
            vector<uint32_t> isoArray(isoCount);
            attributes->GetISOList(&isoArray[0], &isoCount, nullptr);
            NSMutableArray *list = [[[NSMutableArray alloc] init] autorelease];
            for (auto i : isoArray) {
                [list addObject:[NSString stringWithFormat:@"%u", i]];
            }
            isoList = list;
        }

        //---------------------------------------------------------
        // Get current ISO:
        //---------------------------------------------------------
        result = frameAttributes->GetFrameAttribute(blackmagicRawFrameProcessingAttributeISO, &currentISO);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get current ISO in BRAW Metadata Reader.");
        }
        iso = [NSNumber numberWithUnsignedInt:currentISO.uintVal];
        
        //---------------------------------------------------------
        // Get Exposure ranges:
        //---------------------------------------------------------
        result = frameAttributes->GetFrameAttributeRange(blackmagicRawFrameProcessingAttributeExposure, nullptr, nullptr, &exposureReadOnly);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get Exposure Ranges in BRAW Metadata Reader.");
        } else {
            VARIANT valMin;
            VARIANT valMax;
            VariantInit(&valMin);
            VariantInit(&valMax);

            frameAttributes->GetFrameAttributeRange(blackmagicRawFrameProcessingAttributeExposure, &valMin, &valMax, nullptr);
            
            exposureMin = valMin.fltVal;
            exposureMax = valMax.fltVal;
        }
        
        //---------------------------------------------------------
        // Get current Exposure:
        //---------------------------------------------------------
        result = frameAttributes->GetFrameAttribute(blackmagicRawFrameProcessingAttributeExposure, &currentExposure);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get current exposure in BRAW Metadata Reader.");
        }
        exposure = [NSNumber numberWithFloat:currentExposure.fltVal];
        
        //---------------------------------------------------------
        // Get White Balance Kelvin ranges:
        //---------------------------------------------------------
        result = frameAttributes->GetFrameAttributeRange(blackmagicRawFrameProcessingAttributeWhiteBalanceKelvin, nullptr, nullptr, &whiteBalanceKelvinReadOnly);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get White Balance Kelvin Ranges in BRAW Metadata Reader.");
        } else {
            VARIANT valMin;
            VARIANT valMax;
            VariantInit(&valMin);
            VariantInit(&valMax);

            frameAttributes->GetFrameAttributeRange(blackmagicRawFrameProcessingAttributeWhiteBalanceKelvin, &valMin, &valMax, nullptr);

            whiteBalanceKelvinMin = valMin.uintVal;
            whiteBalanceKelvinMax = valMax.uintVal;
        }
        
        //---------------------------------------------------------
        // Get current White Balance Kelvin:
        //---------------------------------------------------------
        result = frameAttributes->GetFrameAttribute(blackmagicRawFrameProcessingAttributeWhiteBalanceKelvin, &currentWhiteBalanceKelvin);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get current White Balance Kelvin in BRAW Metadata Reader.");
        }
        whiteBalanceKelvin = [NSNumber numberWithUnsignedInt:currentWhiteBalanceKelvin.uintVal];
        
        //---------------------------------------------------------
        // Get White Balance Tint ranges:
        //---------------------------------------------------------
        result = frameAttributes->GetFrameAttributeRange(blackmagicRawFrameProcessingAttributeWhiteBalanceTint, nullptr, nullptr, &whiteBalanceTintReadOnly);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get White Balance Tint Ranges in BRAW Metadata Reader.");
        } else {
            VARIANT valMin;
            VARIANT valMax;
            VariantInit(&valMin);
            VariantInit(&valMax);

            frameAttributes->GetFrameAttributeRange(blackmagicRawFrameProcessingAttributeWhiteBalanceTint, &valMin, &valMax, nullptr);
            
            whiteBalanceTintMin = valMin.iVal;
            whiteBalanceTintMax = valMax.iVal;
        }
        
        //---------------------------------------------------------
        // Get current White Balance Tint:
        //---------------------------------------------------------
        result = frameAttributes->GetFrameAttribute(blackmagicRawFrameProcessingAttributeWhiteBalanceTint, &currentWhiteBalanceTint);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get current White Balance Tint in BRAW Metadata Reader.");
        }
        whiteBalanceTint = [NSNumber numberWithInteger:currentWhiteBalanceTint.iVal];
        
        //---------------------------------------------------------
        // Get a list of available 3D LUT Mode options:
        //---------------------------------------------------------
        uint32_t lutModeCount   = 0;
        result = attributes->GetClipAttributeList(blackmagicRawClipProcessingAttributePost3DLUTMode, nullptr, &lutModeCount, &lutModeReadOnly);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get 3D LUT Mode options in BRAW Metadata Reader.");
        }  else {
            vector<VARIANT> lutModeArray(lutModeCount);
            attributes->GetClipAttributeList(blackmagicRawClipProcessingAttributePost3DLUTMode, &lutModeArray[0], &lutModeCount, nullptr);
            NSMutableArray *list = [[[NSMutableArray alloc] init] autorelease];
            for (const auto& v : lutModeArray) {
                [list addObject:[NSString stringWithFormat:@"%@", v.bstrVal]];
            }
            lutModeList = list;
        }
        
        //---------------------------------------------------------
        // Get current 3D LUT Mode:
        //---------------------------------------------------------
        result = attributes->GetClipAttribute(blackmagicRawClipProcessingAttributePost3DLUTMode, &currentLUTMode);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get current 3D LUT Mode in BRAW Metadata Reader.");
        }
        lutMode = [NSString stringWithString:(__bridge NSString *)currentLUTMode.bstrVal];
        
        //---------------------------------------------------------
        // Get Tone Curve Saturation ranges:
        //---------------------------------------------------------
        result = attributes->GetClipAttributeRange(blackmagicRawClipProcessingAttributeToneCurveSaturation, nullptr, nullptr, &toneCurveSaturationReadOnly);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get Tone Curve Saturation Ranges in BRAW Metadata Reader.");
        } else {
            VARIANT valMin;
            VARIANT valMax;
            VariantInit(&valMin);
            VariantInit(&valMax);

            attributes->GetClipAttributeRange(blackmagicRawClipProcessingAttributeToneCurveSaturation, &valMin, &valMax, nullptr);
            
            toneCurveSaturationMin = valMin.fltVal;
            toneCurveSaturationMax = valMax.fltVal;
        }
        
        //---------------------------------------------------------
        // Get current Tone Curve Saturation:
        //---------------------------------------------------------
        result = attributes->GetClipAttribute(blackmagicRawClipProcessingAttributeToneCurveSaturation, &currentToneCurveSaturation);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get current Tone Curve Saturation in BRAW Metadata Reader.");
        }
        toneCurveSaturation = [NSNumber numberWithFloat:currentToneCurveSaturation.fltVal];
        
        //---------------------------------------------------------
        // Get Tone Curve Contrast ranges:
        //---------------------------------------------------------
        result = attributes->GetClipAttributeRange(blackmagicRawClipProcessingAttributeToneCurveContrast, nullptr, nullptr, &toneCurveContrastReadOnly);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get Tone Curve Contrast Ranges in BRAW Metadata Reader.");
        } else {
            VARIANT valMin;
            VARIANT valMax;
            VariantInit(&valMin);
            VariantInit(&valMax);
            
            attributes->GetClipAttributeRange(blackmagicRawClipProcessingAttributeToneCurveContrast, &valMin, &valMax, nullptr);
            
            toneCurveContrastMin = valMin.fltVal;
            toneCurveContrastMax = valMax.fltVal;
        }

        //---------------------------------------------------------
        // Get current Tone Curve Contrast:
        //---------------------------------------------------------
        result = attributes->GetClipAttribute(blackmagicRawClipProcessingAttributeToneCurveContrast, &currentToneCurveContrast);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get current Tone Curve Contrast in BRAW Metadata Reader.");
        }
        toneCurveContrast = [NSNumber numberWithFloat:currentToneCurveContrast.fltVal];
        
        //---------------------------------------------------------
        // Get Tone Curve Midpoint ranges:
        //---------------------------------------------------------
        result = attributes->GetClipAttributeRange(blackmagicRawClipProcessingAttributeToneCurveMidpoint, nullptr, nullptr, &toneCurveMidpointReadOnly);
        if (result != S_OK) {
           NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get Tone Curve Midpoint Ranges in BRAW Metadata Reader.");
        } else {
            VARIANT valMin;
            VARIANT valMax;
            VariantInit(&valMin);
            VariantInit(&valMax);
            
            attributes->GetClipAttributeRange(blackmagicRawClipProcessingAttributeToneCurveMidpoint, &valMin, &valMax, nullptr);
            
            toneCurveMidpointMin = valMin.fltVal;
            toneCurveMidpointMax = valMax.fltVal;
        }

        //---------------------------------------------------------
        // Get current Tone Curve Midpoint:
        //---------------------------------------------------------
        result = attributes->GetClipAttribute(blackmagicRawClipProcessingAttributeToneCurveMidpoint, &currentToneCurveMidpoint);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get current Tone Curve Midpoint in BRAW Metadata Reader.");
        }
        toneCurveMidpoint = [NSNumber numberWithFloat:currentToneCurveMidpoint.fltVal];
        
        //---------------------------------------------------------
        // Get Tone Curve Highlights ranges:
        //---------------------------------------------------------
        result = attributes->GetClipAttributeRange(blackmagicRawClipProcessingAttributeToneCurveHighlights, nullptr, nullptr, &toneCurveHighlightsReadOnly);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get Tone Curve Highlights Ranges in BRAW Metadata Reader.");
        } else {
            VARIANT valMin;
            VARIANT valMax;
            VariantInit(&valMin);
            VariantInit(&valMax);
            
            attributes->GetClipAttributeRange(blackmagicRawClipProcessingAttributeToneCurveHighlights, &valMin, &valMax, nullptr);
            
            toneCurveHighlightsMin = valMin.fltVal;
            toneCurveHighlightsMax = valMax.fltVal;
        }

        //---------------------------------------------------------
        // Get current Tone Curve Highlights:
        //---------------------------------------------------------
        result = attributes->GetClipAttribute(blackmagicRawClipProcessingAttributeToneCurveHighlights, &currentToneCurveHighlights);
        if (result != S_OK) {
           NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get current Tone Curve Highlights in BRAW Metadata Reader.");
        }
        toneCurveHighlights = [NSNumber numberWithFloat:currentToneCurveHighlights.fltVal];
        
        //---------------------------------------------------------
        // Get Tone Curve Shadows ranges:
        //---------------------------------------------------------
        result = attributes->GetClipAttributeRange(blackmagicRawClipProcessingAttributeToneCurveShadows, nullptr, nullptr, &toneCurveShadowsReadOnly);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get Tone Curve Shadows Ranges in BRAW Metadata Reader.");
        } else {
            VARIANT valMin;
            VARIANT valMax;
            VariantInit(&valMin);
            VariantInit(&valMax);
            
            attributes->GetClipAttributeRange(blackmagicRawClipProcessingAttributeToneCurveShadows, &valMin, &valMax, nullptr);
            
            toneCurveShadowsMin = valMin.fltVal;
            toneCurveShadowsMax = valMax.fltVal;
        }

        //---------------------------------------------------------
        // Get current Tone Curve Shadows:
        //---------------------------------------------------------
        result = attributes->GetClipAttribute(blackmagicRawClipProcessingAttributeToneCurveShadows, &currentToneCurveShadows);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get current Tone Curve Shadows in BRAW Metadata Reader.");
        }
        toneCurveShadows = [NSNumber numberWithFloat:currentToneCurveShadows.fltVal];
        
        //---------------------------------------------------------
        // Get Tone Curve Black Level ranges:
        //---------------------------------------------------------
        result = attributes->GetClipAttributeRange(blackmagicRawClipProcessingAttributeToneCurveBlackLevel, nullptr, nullptr, &toneCurveBlackLevelReadOnly);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get Tone Curve Black Level Ranges in BRAW Metadata Reader.");
        } else {
            VARIANT valMin;
            VARIANT valMax;
            VariantInit(&valMin);
            VariantInit(&valMax);
            
            attributes->GetClipAttributeRange(blackmagicRawClipProcessingAttributeToneCurveBlackLevel, &valMin, &valMax, nullptr);
            
            toneCurveBlackLevelMin = valMin.fltVal;
            toneCurveBlackLevelMax = valMax.fltVal;
        }

        //---------------------------------------------------------
        // Get current Tone Curve Black Level:
        //---------------------------------------------------------
        result = attributes->GetClipAttribute(blackmagicRawClipProcessingAttributeToneCurveBlackLevel, &currentToneCurveBlackLevel);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get current Tone Curve Black Level in BRAW Metadata Reader.");
        }
        toneCurveBlackLevel = [NSNumber numberWithFloat:currentToneCurveBlackLevel.fltVal];
        
        //---------------------------------------------------------
        // Get Tone Curve White Level ranges:
        //---------------------------------------------------------
        result = attributes->GetClipAttributeRange(blackmagicRawClipProcessingAttributeToneCurveWhiteLevel, nullptr, nullptr, &toneCurveWhiteLevelReadOnly);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get Tone Curve White Level Ranges in BRAW Metadata Reader.");
        } else {
            VARIANT valMin;
            VARIANT valMax;
            VariantInit(&valMin);
            VariantInit(&valMax);
            
            attributes->GetClipAttributeRange(blackmagicRawClipProcessingAttributeToneCurveWhiteLevel, &valMin, &valMax, nullptr);
            
            toneCurveWhiteLevelMin = valMin.fltVal;
            toneCurveWhiteLevelMax = valMax.fltVal;
        }

        //---------------------------------------------------------
        // Get current Tone Curve White Level:
        //---------------------------------------------------------
        result = attributes->GetClipAttribute(blackmagicRawClipProcessingAttributeToneCurveWhiteLevel, &currentToneCurveWhiteLevel);
        if (result != S_OK) {
           NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get current Tone Curve White Level in BRAW Metadata Reader.");
        }
        toneCurveWhiteLevel = [NSNumber numberWithFloat:currentToneCurveWhiteLevel.fltVal];
        
        //---------------------------------------------------------
        // Get current Tone Curve Video Black Level:
        //---------------------------------------------------------
        result = attributes->GetClipAttributeRange(blackmagicRawClipProcessingAttributeToneCurveVideoBlackLevel, nullptr, nullptr, &toneCurveVideoBlackLevelReadOnly);
        if (result != S_OK) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get Tone Curve Video Black Level Ranges in BRAW Metadata Reader.");
        }
        result = attributes->GetClipAttribute(blackmagicRawClipProcessingAttributeToneCurveVideoBlackLevel, &currentToneCurveVideoBlackLevel);
        if (result != S_OK) {
           NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get current Tone Curve Video Black Level in BRAW Metadata Reader.");
        }
        toneCurveVideoBlackLevel = [NSNumber numberWithInt:currentToneCurveVideoBlackLevel.uiVal];
        
        //---------------------------------------------------------
        // Process the Clip & Frame Metadata:
        //---------------------------------------------------------
        clipMetadata = [self newProcessMetadataWithIterator:clipMetadataIterator];
        frameMetadata = [self newProcessMetadataWithIterator:frameMetadataIterator];

    } while(0);

    //---------------------------------------------------------
    // Release all the BRAW objects:
    //---------------------------------------------------------
    CFRelease(pathToBRAWFile);

    if (attributes != nullptr) {
        attributes->Release();
    }

    if (frameAttributes != nullptr) {
        frameAttributes->Release();
    }
    
    
    if (clipMetadataIterator != nullptr) {
        clipMetadataIterator->Release();
    }

    if (frameMetadataIterator != nullptr) {
        frameMetadataIterator->Release();
    }

    if (clip != nullptr) {
        clip->Release();
    }

    if (callback != nullptr) {
        callback->Release();
    }
    
    if (result != S_OK) {
        NSLog(@"[Gyroflow Toolbox Renderer] Something went wrong previously, so aborting readMetadataFromPath after cleanup.");
        
        if (clipMetadata != nil) {
            [clipMetadata release];
        }
        
        if (frameMetadata != nil) {
            [frameMetadata release];
        }        
        
        return nil;
    }
        
    //---------------------------------------------------------
    // Get the Creation Date of the BRAW File:
    //---------------------------------------------------------
    NSError *fileAttributesError = nil;
    NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:brawFilePath error:&fileAttributesError];

    NSString *creationDateString = nil;
    if (fileAttributesError != nil) {
        NSLog(@"[Gyroflow Toolbox Renderer] Error getting attributes of file at path %@: %@", brawFilePath, fileAttributesError);
    } else {
        NSDate *creationDate = [fileAttributes fileCreationDate];
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss Z";
        creationDateString = [formatter stringFromDate:creationDate];
        [formatter release];
    }
    
    //---------------------------------------------------------
    // Create our new BRAW Parameters Object:
    //---------------------------------------------------------
    BRAWParameters *params                  = [[[BRAWParameters alloc] init] autorelease];
    
    params.brawFilePath                     = brawFilePath;
    params.decodeQuality                    = [NSNumber numberWithUnsignedInt:0]; // Automatic
    params.frameToRender                    = @0;
    params.frameCount                       = [NSNumber numberWithUnsignedLongLong:frameCount];
    params.frameRate                        = [NSNumber numberWithFloat:frameRate];
    params.creationDate                     = creationDateString;
    
    params.baseFrameIndex                   = [NSNumber numberWithUnsignedInt:baseFrameIndex];
    params.isDropFrameTimecode              = [NSNumber numberWithBool:isDropFrameTimecode];
    
    NSDictionary *clipMetadataDict = [clipMetadata copy];
    NSDictionary *frameMetadataDict = [frameMetadata copy];
    
    params.clipMetadata                     = clipMetadataDict;
    params.frameMetadata                    = frameMetadataDict;
    
    [clipMetadataDict release];
    [frameMetadataDict release];
    [clipMetadata release];
    [frameMetadata release];
    
    params.width                            = [NSNumber numberWithFloat:width];
    params.height                           = [NSNumber numberWithFloat:height];
    
    params.startTimecode                    = startTimecode;
    
    params.audioSamples                     = [NSNumber numberWithFloat:audioSamples];                  // uint64_t
    params.audioBitDepth                    = [NSNumber numberWithFloat:audioBitDepth];                 // uint32_t
    params.audioChannelCount                = [NSNumber numberWithFloat:audioChannelCount];             // uint32_t
    params.audioSampleRate                  = [NSNumber numberWithFloat:audioSampleRate];               // uint32_t
        
    params.colorScienceVersionList          = colorScienceVersionList;
    params.gamutList                        = gamutList;
    params.gammaList                        = gammaList;
    params.isoList                          = isoList;
        
    params.exposureMin                      = [NSNumber numberWithDouble:exposureMin];
    params.exposureMax                      = [NSNumber numberWithDouble:exposureMax];
    
    params.whiteBalanceKelvinMin            = [NSNumber numberWithDouble:whiteBalanceKelvinMin];
    params.whiteBalanceKelvinMax            = [NSNumber numberWithDouble:whiteBalanceKelvinMax];
    
    params.whiteBalanceTintMin              = [NSNumber numberWithDouble:whiteBalanceTintMin];
    params.whiteBalanceTintMax              = [NSNumber numberWithDouble:whiteBalanceTintMax];
    
    params.lutModeList                      = lutModeList;
    
    params.toneCurveSaturationMin           = [NSNumber numberWithDouble:toneCurveSaturationMin];
    params.toneCurveSaturationMax           = [NSNumber numberWithDouble:toneCurveSaturationMax];
    
    params.toneCurveContrastMin             = [NSNumber numberWithDouble:toneCurveContrastMin];
    params.toneCurveContrastMax             = [NSNumber numberWithDouble:toneCurveContrastMax];
    
    params.toneCurveMidpointMin             = [NSNumber numberWithDouble:toneCurveMidpointMin];
    params.toneCurveMidpointMax             = [NSNumber numberWithDouble:toneCurveMidpointMax];
    
    params.toneCurveHighlightsMin           = [NSNumber numberWithDouble:toneCurveHighlightsMin];
    params.toneCurveHighlightsMax           = [NSNumber numberWithDouble:toneCurveHighlightsMax];
    
    params.toneCurveShadowsMin              = [NSNumber numberWithDouble:toneCurveShadowsMin];
    params.toneCurveShadowsMax              = [NSNumber numberWithDouble:toneCurveShadowsMax];
    
    params.toneCurveBlackLevelMin           = [NSNumber numberWithDouble:toneCurveBlackLevelMin];
    params.toneCurveBlackLevelMax           = [NSNumber numberWithDouble:toneCurveBlackLevelMax];
        
    params.toneCurveWhiteLevelMin           = [NSNumber numberWithDouble:toneCurveWhiteLevelMin];
    params.toneCurveWhiteLevelMax           = [NSNumber numberWithDouble:toneCurveWhiteLevelMax];
    
    params.currentColorScienceGen           = colorScienceGen;
    
    params.currentGamut                     = gamut;
    params.currentGamma                     = gamma;
    params.currentHighlightRecovery         = highlightRecovery;
    params.currentGamutCompression          = gamutCompression;
    
    params.currentISO                       = iso;
    params.currentExposure                  = exposure;
    params.currentWhiteBalanceKelvin        = whiteBalanceKelvin;
    params.currentWhiteBalanceTint          = whiteBalanceTint;
    
    params.currentLUTMode                   = lutMode;
    
    params.currentToneCurveSaturation       = toneCurveSaturation;
    params.currentToneCurveContrast         = toneCurveContrast;
    params.currentToneCurveMidpoint         = toneCurveMidpoint;
    params.currentToneCurveHighlights       = toneCurveHighlights;
    params.currentToneCurveShadows          = toneCurveShadows;
    params.currentToneCurveBlackLevel       = toneCurveBlackLevel;
    params.currentToneCurveWhiteLevel       = toneCurveWhiteLevel;
    params.currentToneCurveVideoBlackLevel  = toneCurveVideoBlackLevel;
        
    params.iso                              = [NSNumber numberWithUnsignedLong:[isoList indexOfObject:[NSString stringWithFormat:@"%@", iso]]];
    params.exposure                         = exposure;
    params.whiteBalanceKelvin               = whiteBalanceKelvin;
    params.whiteBalanceTint                 = whiteBalanceTint;
    params.colorScienceGen                  = [NSNumber numberWithUnsignedLong:[colorScienceVersionList indexOfObject:[NSString stringWithFormat:@"%@", colorScienceGen]]];
    params.gamut                            = [NSNumber numberWithUnsignedLong:[gamutList indexOfObject:gamut]];
    params.gamma                            = [NSNumber numberWithUnsignedLong:[gammaList indexOfObject:gamma]];
    params.highlightRecovery                = highlightRecovery;
    params.gamutCompression                 = gamutCompression;
    params.lutMode                          = [NSNumber numberWithUnsignedLong:[lutModeList indexOfObject:lutMode]];
    
    params.toneCurveSaturation              = toneCurveSaturation;
    params.toneCurveContrast                = toneCurveContrast;
    params.toneCurveMidpoint                = toneCurveMidpoint;
    params.toneCurveHighlights              = toneCurveHighlights;
    params.toneCurveShadows                 = toneCurveShadows;
    params.toneCurveBlackLevel              = toneCurveBlackLevel;
    params.toneCurveWhiteLevel              = toneCurveWhiteLevel;
    params.toneCurveVideoBlackLevel         = toneCurveVideoBlackLevel;
        
    params.isoReadOnly                       = [NSNumber numberWithBool:isoReadOnly];
    params.exposureReadOnly                  = [NSNumber numberWithBool:exposureReadOnly];
    params.whiteBalanceKelvinReadOnly        = [NSNumber numberWithBool:whiteBalanceKelvinReadOnly];
    params.whiteBalanceTintReadOnly          = [NSNumber numberWithBool:whiteBalanceTintReadOnly];
    params.colorScienceVersionReadOnly       = [NSNumber numberWithBool:colorScienceVersionReadOnly];
    params.gamutReadOnly                     = [NSNumber numberWithBool:gamutReadOnly];
    params.gammaReadOnly                     = [NSNumber numberWithBool:gammaReadOnly];
    params.highlightRecoveryReadOnly         = [NSNumber numberWithBool:highlightRecoveryReadOnly];
    params.gamutCompressionReadOnly          = [NSNumber numberWithBool:gamutCompressionReadOnly];
    params.lutModeReadOnly                   = [NSNumber numberWithBool:lutModeReadOnly];
    
    params.toneCurveSaturationReadOnly       = [NSNumber numberWithBool:toneCurveSaturationReadOnly];
    params.toneCurveContrastReadOnly         = [NSNumber numberWithBool:toneCurveContrastReadOnly];
    params.toneCurveMidpointReadOnly         = [NSNumber numberWithBool:toneCurveMidpointReadOnly];
    params.toneCurveHighlightsReadOnly       = [NSNumber numberWithBool:toneCurveHighlightsReadOnly];
    params.toneCurveShadowsReadOnly          = [NSNumber numberWithBool:toneCurveShadowsReadOnly];
    params.toneCurveBlackLevelReadOnly       = [NSNumber numberWithBool:toneCurveBlackLevelReadOnly];
    params.toneCurveWhiteLevelReadOnly       = [NSNumber numberWithBool:toneCurveWhiteLevelReadOnly];
    params.toneCurveVideoBlackLevelReadOnly  = [NSNumber numberWithBool:toneCurveVideoBlackLevelReadOnly];
    
    return params;
}

@end
