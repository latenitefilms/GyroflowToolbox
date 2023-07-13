//
//  BRAWParameters.mm
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 23/10/2022.
//

#import <Foundation/Foundation.h>
#import "BRAWParameters.h"

//---------------------------------------------------------
// BRAW Plugin Parameters Object:
//---------------------------------------------------------
@implementation BRAWParameters

//---------------------------------------------------------
// BRAW Path & Frame Information:
//---------------------------------------------------------
@synthesize brawFilePath;
@synthesize bookmarkData;
@synthesize frameToRender;
@synthesize frameCount;
@synthesize frameRate;
@synthesize width;
@synthesize height;
@synthesize startTimecode;
@synthesize baseFrameIndex;
@synthesize isDropFrameTimecode;
@synthesize uniqueID;
@synthesize creationDate;

//---------------------------------------------------------
// Metadata:
//---------------------------------------------------------
@synthesize clipMetadata;
@synthesize frameMetadata;

//---------------------------------------------------------
// Audio:
//---------------------------------------------------------
@synthesize audioSamples;
@synthesize audioBitDepth;
@synthesize audioChannelCount;
@synthesize audioSampleRate;

//---------------------------------------------------------
// Current Values:
//---------------------------------------------------------
@synthesize currentColorScienceGen;
@synthesize currentGamut;
@synthesize currentGamma;
@synthesize currentHighlightRecovery;
@synthesize currentGamutCompression;

@synthesize currentISO;
@synthesize currentExposure;
@synthesize currentWhiteBalanceKelvin;
@synthesize currentWhiteBalanceTint;
@synthesize currentLUTMode;

@synthesize currentToneCurveSaturation;
@synthesize currentToneCurveContrast;
@synthesize currentToneCurveMidpoint;
@synthesize currentToneCurveHighlights;
@synthesize currentToneCurveShadows;
@synthesize currentToneCurveBlackLevel;
@synthesize currentToneCurveWhiteLevel;
@synthesize currentToneCurveVideoBlackLevel;

//---------------------------------------------------------
// Parameter Lists:
//---------------------------------------------------------
@synthesize colorScienceVersionList;
@synthesize gamutList;
@synthesize gammaList;
@synthesize isoList;
@synthesize lutModeList;

//---------------------------------------------------------
// Parameter Read Only:
//---------------------------------------------------------
@synthesize isoReadOnly;
@synthesize exposureReadOnly;
@synthesize whiteBalanceKelvinReadOnly;
@synthesize whiteBalanceTintReadOnly;
@synthesize colorScienceVersionReadOnly;
@synthesize gamutReadOnly;
@synthesize gammaReadOnly;
@synthesize highlightRecoveryReadOnly;
@synthesize gamutCompressionReadOnly;
@synthesize lutModeReadOnly;

@synthesize toneCurveSaturationReadOnly;
@synthesize toneCurveContrastReadOnly;
@synthesize toneCurveMidpointReadOnly;
@synthesize toneCurveHighlightsReadOnly;
@synthesize toneCurveShadowsReadOnly;
@synthesize toneCurveBlackLevelReadOnly;
@synthesize toneCurveWhiteLevelReadOnly;
@synthesize toneCurveVideoBlackLevelReadOnly;

//---------------------------------------------------------
// Parameter Ranges:
//---------------------------------------------------------
@synthesize exposureMin;
@synthesize exposureMax;

@synthesize whiteBalanceKelvinMin;
@synthesize whiteBalanceKelvinMax;

@synthesize whiteBalanceTintMin;
@synthesize whiteBalanceTintMax;

@synthesize toneCurveSaturationMin;
@synthesize toneCurveSaturationMax;

@synthesize toneCurveContrastMin;
@synthesize toneCurveContrastMax;

@synthesize toneCurveMidpointMin;
@synthesize toneCurveMidpointMax;

@synthesize toneCurveHighlightsMin;
@synthesize toneCurveHighlightsMax;

@synthesize toneCurveShadowsMin;
@synthesize toneCurveShadowsMax;

@synthesize toneCurveBlackLevelMin;
@synthesize toneCurveBlackLevelMax;

@synthesize toneCurveWhiteLevelMin;
@synthesize toneCurveWhiteLevelMax;

//---------------------------------------------------------
// "Quality" Group:
//---------------------------------------------------------
@synthesize decodeQuality;
@synthesize checkedDecodeQuality;

//---------------------------------------------------------
// "Frame Metadata" Group:
//---------------------------------------------------------
@synthesize iso;
@synthesize checkedISO;

@synthesize exposure;
@synthesize checkedExposure;

@synthesize whiteBalanceKelvin;
@synthesize checkedWhiteBalanceKelvin;

@synthesize whiteBalanceTint;
@synthesize checkedWhiteBalanceTint;

//---------------------------------------------------------
// "Clip Metadata" Group:
//---------------------------------------------------------
@synthesize colorScienceGen;
@synthesize checkedColorScienceGen;

@synthesize gamut;
@synthesize checkedGamut;

@synthesize gamma;
@synthesize checkedGamma;

@synthesize highlightRecovery;
@synthesize checkedHighlightRecovery;

@synthesize gamutCompression;
@synthesize checkedGamutCompression;

@synthesize lutMode;
@synthesize checkedLUTMode;

//---------------------------------------------------------
// "Custom Gamma Controls" Group::
//---------------------------------------------------------
@synthesize toneCurveSaturation;
@synthesize checkedToneCurveSaturation;

@synthesize toneCurveContrast;
@synthesize checkedToneCurveContrast;

@synthesize toneCurveMidpoint;
@synthesize checkedToneCurveMidpoint;

@synthesize toneCurveHighlights;
@synthesize checkedToneCurveHighlights;

@synthesize toneCurveShadows;
@synthesize checkedToneCurveShadows;

@synthesize toneCurveBlackLevel;
@synthesize checkedToneCurveBlackLevel;

@synthesize toneCurveWhiteLevel;
@synthesize checkedToneCurveWhiteLevel;

@synthesize toneCurveVideoBlackLevel;
@synthesize checkedToneCurveVideoBlackLevel;

+ (BOOL)supportsSecureCoding
{
    return YES;
}

//---------------------------------------------------------
// Deallocate:
//---------------------------------------------------------
- (void)dealloc {
    //---------------------------------------------------------
    // BRAW Path & Frame Information:
    //---------------------------------------------------------
    [frameToRender release];
    [brawFilePath release];
    [bookmarkData release];
    [frameCount release];
    [frameRate release];
    [width release];
    [height release];
    [startTimecode release];
    [baseFrameIndex release];
    [isDropFrameTimecode release];
    [uniqueID release];
    [creationDate release];
    
    //---------------------------------------------------------
    // Metadata:
    //---------------------------------------------------------
    [clipMetadata release];
    [frameMetadata release];
    
    //---------------------------------------------------------
    // Audio:
    //---------------------------------------------------------
    [audioSamples release];
    [audioBitDepth release];
    [audioChannelCount release];
    [audioSampleRate release];
    
    //---------------------------------------------------------
    // Current Values:
    //---------------------------------------------------------
    [currentColorScienceGen release];
    [currentGamut release];
    [currentGamma release];
    [currentHighlightRecovery release];
    [currentGamutCompression release];

    [currentISO release];
    [currentExposure release];
    [currentWhiteBalanceKelvin release];
    [currentWhiteBalanceTint release];
    [currentLUTMode release];

    [currentToneCurveSaturation release];
    [currentToneCurveContrast release];
    [currentToneCurveMidpoint release];
    [currentToneCurveHighlights release];
    [currentToneCurveShadows release];
    [currentToneCurveBlackLevel release];
    [currentToneCurveWhiteLevel release];
    [currentToneCurveVideoBlackLevel release];
    
    //---------------------------------------------------------
    // Parameter Lists:
    //---------------------------------------------------------
    [colorScienceVersionList release];
    [gamutList release];
    [gammaList release];
    [isoList release];
    [lutModeList release];
    
    //---------------------------------------------------------
    // Parameter Ranges:
    //---------------------------------------------------------
    [exposureMin release];
    [exposureMax release];

    [whiteBalanceKelvinMin release];
    [whiteBalanceKelvinMax release];

    [whiteBalanceTintMin release];
    [whiteBalanceTintMax release];

    [toneCurveSaturationMin release];
    [toneCurveSaturationMax release];

    [toneCurveContrastMin release];
    [toneCurveContrastMax release];

    [toneCurveMidpointMin release];
    [toneCurveMidpointMax release];

    [toneCurveHighlightsMin release];
    [toneCurveHighlightsMax release];

    [toneCurveShadowsMin release];
    [toneCurveShadowsMax release];

    [toneCurveBlackLevelMin release];
    [toneCurveBlackLevelMax release];

    [toneCurveWhiteLevelMin release];
    [toneCurveWhiteLevelMax release];
    
    //---------------------------------------------------------
    // Read Only:
    //---------------------------------------------------------
    [isoReadOnly release];
    [exposureReadOnly release];
    [whiteBalanceKelvinReadOnly release];
    [whiteBalanceTintReadOnly release];
    [colorScienceVersionReadOnly release];
    [gamutReadOnly release];
    [gammaReadOnly release];
    [highlightRecoveryReadOnly release];
    [gamutCompressionReadOnly release];
    [lutModeReadOnly release];

    [toneCurveSaturationReadOnly release];
    [toneCurveContrastReadOnly release];
    [toneCurveMidpointReadOnly release];
    [toneCurveHighlightsReadOnly release];
    [toneCurveShadowsReadOnly release];
    [toneCurveBlackLevelReadOnly release];
    [toneCurveWhiteLevelReadOnly release];
    [toneCurveVideoBlackLevelReadOnly release];
    
    //---------------------------------------------------------
    // "Quality" Group:
    //---------------------------------------------------------
    [decodeQuality release];
    [checkedDecodeQuality release];
    
    //---------------------------------------------------------
    // "Frame Metadata" Group:
    //---------------------------------------------------------
    [iso release];
    [checkedISO release];
    
    [exposure release];
    [checkedExposure release];
    
    [whiteBalanceKelvin release];
    [checkedWhiteBalanceKelvin release];
    
    [whiteBalanceTint release];
    [checkedWhiteBalanceTint release];
    
    //---------------------------------------------------------
    // "Clip Metadata" Group:
    //---------------------------------------------------------
    [colorScienceGen release];
    [checkedColorScienceGen release];
    [gamut release];
    [checkedGamut release];

    [gamma release];
    [checkedGamma release];
     
    [highlightRecovery release];
    [checkedHighlightRecovery release];
     
    [gamutCompression release];
    [checkedGamutCompression release];
    
    [lutMode release];
    [checkedLUTMode release];
    
    //---------------------------------------------------------
    // "Custom Gamma Controls" Group::
    //---------------------------------------------------------
    [toneCurveSaturation release];
    [checkedToneCurveSaturation release];
    
    [toneCurveContrast release];
    [checkedToneCurveContrast release];
    
    [toneCurveMidpoint release];
    [checkedToneCurveMidpoint release];
    
    [toneCurveHighlights release];
    [checkedToneCurveHighlights release];
    
    [toneCurveShadows release];
    [checkedToneCurveShadows release];
    
    [toneCurveBlackLevel release];
    [checkedToneCurveBlackLevel release];

    [toneCurveWhiteLevel release];
    [checkedToneCurveWhiteLevel release];
    
    [toneCurveVideoBlackLevel release];
    [checkedToneCurveVideoBlackLevel release];
    
    [super dealloc];
}

//---------------------------------------------------------
// Initialize with Coder:
//---------------------------------------------------------
- (id)initWithCoder:(NSCoder *)decoder {
    if (self = [super init]) {
        //---------------------------------------------------------
        // BRAW Path & Frame Information:
        //---------------------------------------------------------
        self.brawFilePath                       = [decoder decodeObjectOfClass:[NSString class] forKey:@"brawFilePath"];
        self.bookmarkData                       = [decoder decodeObjectOfClass:[NSData class] forKey:@"bookmarkData"];
        self.frameToRender                      = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"frameToRender"];
        self.frameCount                         = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"frameCount"];
        self.frameRate                          = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"frameRate"];
        self.width                              = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"width"];
        self.height                             = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"height"];
        self.startTimecode                      = [decoder decodeObjectOfClass:[NSString class] forKey:@"startTimecode"];
        self.baseFrameIndex                     = [decoder decodeObjectOfClass:[NSString class] forKey:@"baseFrameIndex"];
        self.isDropFrameTimecode                = [decoder decodeObjectOfClass:[NSString class] forKey:@"isDropFrameTimecode"];
        self.uniqueID                           = [decoder decodeObjectOfClass:[NSString class] forKey:@"uniqueID"];
        self.creationDate                       = [decoder decodeObjectOfClass:[NSString class] forKey:@"creationDate"];
        
        //---------------------------------------------------------
        // Metadata:
        //---------------------------------------------------------
        self.clipMetadata                       = [decoder decodeObjectOfClass:[NSMutableDictionary class] forKey:@"clipMetadata"];
        self.frameMetadata                      = [decoder decodeObjectOfClass:[NSMutableDictionary class] forKey:@"frameMetadata"];
        
        //---------------------------------------------------------
        // Audio:
        //---------------------------------------------------------
        self.audioSamples                       = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"audioSamples"];
        self.audioBitDepth                      = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"audioBitDepth"];
        self.audioChannelCount                  = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"audioChannelCount"];
        self.audioSampleRate                    = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"audioSampleRate"];
                
        //---------------------------------------------------------
        // Current Values:
        //---------------------------------------------------------
        self.currentColorScienceGen             = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"currentColorScienceGen"];
        self.currentGamut                       = [decoder decodeObjectOfClass:[NSString class] forKey:@"currentGamut"];
        self.currentGamma                       = [decoder decodeObjectOfClass:[NSString class] forKey:@"currentGamma"];
        self.currentHighlightRecovery           = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"currentHighlightRecovery"];
        self.currentGamutCompression            = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"currentGamutCompression"];
        
        self.currentISO                         = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"currentISO"];
        self.currentExposure                    = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"currentExposure"];
        self.currentWhiteBalanceKelvin          = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"currentWhiteBalanceKelvin"];
        self.currentWhiteBalanceTint            = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"currentWhiteBalanceTint"];
        self.currentLUTMode                     = [decoder decodeObjectOfClass:[NSString class] forKey:@"currentLUTMode"];
        
        self.currentToneCurveSaturation         = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"currentToneCurveSaturation"];
        self.currentToneCurveContrast           = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"currentToneCurveContrast"];
        self.currentToneCurveMidpoint           = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"currentToneCurveMidpoint"];
        self.currentToneCurveHighlights         = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"currentToneCurveHighlights"];
        self.currentToneCurveShadows            = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"currentToneCurveShadows"];
        self.currentToneCurveBlackLevel         = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"currentToneCurveBlackLevel"];
        self.currentToneCurveWhiteLevel         = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"currentToneCurveWhiteLevel"];
        self.currentToneCurveVideoBlackLevel    = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"currentToneCurveVideoBlackLevel"];

        //---------------------------------------------------------
        // Parameter Lists:
        //---------------------------------------------------------
        self.colorScienceVersionList            = [decoder decodeObjectOfClass:[NSArray class] forKey:@"colorScienceVersionList"];
        self.gamutList                          = [decoder decodeObjectOfClass:[NSArray class] forKey:@"gamutList"];
        self.gammaList                          = [decoder decodeObjectOfClass:[NSArray class] forKey:@"gammaList"];
        self.isoList                            = [decoder decodeObjectOfClass:[NSArray class] forKey:@"isoList"];
        self.lutModeList                        = [decoder decodeObjectOfClass:[NSArray class] forKey:@"lutModeList"];
        
        //---------------------------------------------------------
        // Parameter Ranges:
        //---------------------------------------------------------
        self.exposureMin                        = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"exposureMin"];
        self.exposureMax                        = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"exposureMin"];
        
        self.whiteBalanceKelvinMin              = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"whiteBalanceKelvinMin"];
        self.whiteBalanceKelvinMax              = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"whiteBalanceKelvinMax"];
        
        self.whiteBalanceTintMin                = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"whiteBalanceTintMin"];
        self.whiteBalanceTintMax                = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"whiteBalanceTintMax"];
        
        self.toneCurveSaturationMin             = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveSaturationMin"];
        self.toneCurveSaturationMax             = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveSaturationMax"];
        
        self.toneCurveContrastMin               = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveContrastMin"];
        self.toneCurveContrastMax               = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveContrastMax"];
        
        self.toneCurveMidpointMin               = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveMidpointMin"];
        self.toneCurveMidpointMax               = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveMidpointMax"];
        
        self.toneCurveHighlightsMin             = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveHighlightsMin"];
        self.toneCurveHighlightsMax             = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveHighlightsMax"];
        
        self.toneCurveShadowsMin                = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveShadowsMin"];
        self.toneCurveShadowsMax                = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveShadowsMax"];
        
        self.toneCurveBlackLevelMin             = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveBlackLevelMin"];
        self.toneCurveBlackLevelMax             = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveBlackLevelMax"];
        
        self.toneCurveWhiteLevelMin             = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveWhiteLevelMin"];
        self.toneCurveWhiteLevelMax             = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveWhiteLevelMax"];
        
        //---------------------------------------------------------
        // Read Only:
        //---------------------------------------------------------
        self.isoReadOnly                        = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"isoReadOnly"];
        self.exposureReadOnly                   = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"exposureReadOnly"];
        self.whiteBalanceKelvinReadOnly         = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"whiteBalanceKelvinReadOnly"];
        self.whiteBalanceTintReadOnly           = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"whiteBalanceTintReadOnly"];
        self.colorScienceVersionReadOnly        = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"colorScienceVersionReadOnly"];
        self.gamutReadOnly                      = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"gamutReadOnly"];
        
        self.gamutReadOnly                      = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"gamutReadOnly"];
        self.gammaReadOnly                      = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"gammaReadOnly"];
        self.highlightRecoveryReadOnly          = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"highlightRecoveryReadOnly"];
        self.gamutCompressionReadOnly           = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"gamutCompressionReadOnly"];
        self.lutModeReadOnly                    = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"lutModeReadOnly"];
        
        self.toneCurveSaturationReadOnly        = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveSaturationReadOnly"];
        self.toneCurveContrastReadOnly          = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveContrastReadOnly"];
        self.toneCurveMidpointReadOnly          = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveMidpointReadOnly"];
        self.toneCurveHighlightsReadOnly        = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveHighlightsReadOnly"];
        self.toneCurveShadowsReadOnly           = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveShadowsReadOnly"];
        self.toneCurveBlackLevelReadOnly        = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveBlackLevelReadOnly"];
        self.toneCurveWhiteLevelReadOnly        = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveWhiteLevelReadOnly"];
        self.toneCurveVideoBlackLevelReadOnly   = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveVideoBlackLevelReadOnly"];

        //---------------------------------------------------------
        // "Quality" Group:
        //---------------------------------------------------------
        self.decodeQuality                      = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"decodeQuality"];
        self.checkedDecodeQuality               = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"checkedDecodeQuality"];
        
        //---------------------------------------------------------
        // "Frame Metadata" Group:
        //---------------------------------------------------------
        self.iso                                = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"iso"];
        self.checkedISO                         = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"checkedISO"];
            
        self.exposure                           = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"exposure"];
        self.checkedExposure                    = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"checkedExposure"];
    
        self.whiteBalanceKelvin                 = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"whiteBalanceKelvin"];
        self.checkedWhiteBalanceKelvin          = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"checkedWhiteBalanceKelvin"];
    
        self.whiteBalanceTint                   = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"whiteBalanceTint"];
        self.checkedWhiteBalanceTint            = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"checkedWhiteBalanceTint"];
        
        //---------------------------------------------------------
        // "Clip Metadata" Group:
        //---------------------------------------------------------
        self.colorScienceGen                    = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"colorScienceGen"];
        self.checkedColorScienceGen             = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"checkedColorScienceGen"];
            
        self.gamut                              = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"gamut"];
        self.checkedGamut                       = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"checkedGamut"];
            
        self.gamma                              = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"gamma"];
        self.checkedGamma                       = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"checkedGamma"];
            
        self.highlightRecovery                  = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"highlightRecovery"];
        self.checkedHighlightRecovery           = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"checkedHighlightRecovery"];
            
        self.gamutCompression                   = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"gamutCompression"];
        self.checkedGamutCompression            = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"checkedGamutCompression"];
        
        self.lutMode                            = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"lutMode"];
        self.checkedLUTMode                     = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"checkedLUTMode"];
        
        //---------------------------------------------------------
        // "Custom Gamma Controls" Group::
        //---------------------------------------------------------
        self.toneCurveSaturation                = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveSaturation"];
        self.checkedToneCurveSaturation         = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"checkedToneCurveSaturation"];
                
        self.toneCurveContrast                  = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveContrast"];
        self.checkedToneCurveContrast           = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"checkedToneCurveContrast"];
                
        self.toneCurveMidpoint                  = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveMidpoint"];
        self.checkedToneCurveMidpoint           = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"checkedToneCurveMidpoint"];
                
        self.toneCurveHighlights                = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveHighlights"];
        self.checkedToneCurveHighlights         = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"checkedToneCurveHighlights"];
                
        self.toneCurveShadows                   = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveShadows"];
        self.checkedToneCurveShadows            = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"checkedToneCurveShadows"];
                
        self.toneCurveBlackLevel                = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveBlackLevel"];
        self.checkedToneCurveBlackLevel         = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"checkedToneCurveBlackLevel"];
                
        self.toneCurveWhiteLevel                = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveWhiteLevel"];
        self.checkedToneCurveWhiteLevel         = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"checkedToneCurveWhiteLevel"];
        
        self.toneCurveVideoBlackLevel           = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"toneCurveVideoBlackLevel"];
        self.checkedToneCurveVideoBlackLevel    = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"checkedToneCurveVideoBlackLevel"];
    }
    return self;
}

//---------------------------------------------------------
// Encode With Coder:
//---------------------------------------------------------
- (void)encodeWithCoder:(NSCoder *)encoder {
    //---------------------------------------------------------
    // BRAW Path & Frame Information:
    //---------------------------------------------------------
    [encoder encodeObject:brawFilePath                      forKey:@"brawFilePath"];
    [encoder encodeObject:bookmarkData                      forKey:@"bookmarkData"];
    [encoder encodeObject:frameToRender                     forKey:@"frameToRender"];
    [encoder encodeObject:frameCount                        forKey:@"frameCount"];
    [encoder encodeObject:frameRate                         forKey:@"frameRate"];
    [encoder encodeObject:width                             forKey:@"width"];
    [encoder encodeObject:height                            forKey:@"height"];
    [encoder encodeObject:startTimecode                     forKey:@"startTimecode"];
    [encoder encodeObject:baseFrameIndex                    forKey:@"baseFrameIndex"];
    [encoder encodeObject:isDropFrameTimecode               forKey:@"isDropFrameTimecode"];
    [encoder encodeObject:uniqueID                          forKey:@"uniqueID"];
    [encoder encodeObject:creationDate                      forKey:@"creationDate"];    
    
    //---------------------------------------------------------
    // Metadata:
    //---------------------------------------------------------
    [encoder encodeObject:clipMetadata                      forKey:@"clipMetadata"];
    [encoder encodeObject:frameMetadata                     forKey:@"frameMetadata"];
        
    //---------------------------------------------------------
    // Audio:
    //---------------------------------------------------------
    [encoder encodeObject:audioSamples                      forKey:@"audioSamples"];
    [encoder encodeObject:audioBitDepth                     forKey:@"audioBitDepth"];
    [encoder encodeObject:audioChannelCount                 forKey:@"audioChannelCount"];
    [encoder encodeObject:audioSampleRate                   forKey:@"audioSampleRate"];
    
    //---------------------------------------------------------
    // Current Values:
    //---------------------------------------------------------
    [encoder encodeObject:currentColorScienceGen            forKey:@"currentColorScienceGen"];
    [encoder encodeObject:currentGamut                      forKey:@"currentGamut"];
    [encoder encodeObject:currentGamma                      forKey:@"currentGamma"];
    [encoder encodeObject:currentHighlightRecovery          forKey:@"currentHighlightRecovery"];
    [encoder encodeObject:currentGamutCompression           forKey:@"currentGamutCompression"];
    
    [encoder encodeObject:currentISO                        forKey:@"currentISO"];
    [encoder encodeObject:currentExposure                   forKey:@"currentExposure"];
    [encoder encodeObject:currentWhiteBalanceKelvin         forKey:@"currentWhiteBalanceKelvin"];
    [encoder encodeObject:currentWhiteBalanceTint           forKey:@"currentWhiteBalanceTint"];
    [encoder encodeObject:currentLUTMode                    forKey:@"currentLUTMode"];
    
    [encoder encodeObject:currentToneCurveSaturation        forKey:@"currentToneCurveSaturation"];
    [encoder encodeObject:currentToneCurveContrast          forKey:@"currentToneCurveContrast"];
    [encoder encodeObject:currentToneCurveMidpoint          forKey:@"currentToneCurveMidpoint"];
    [encoder encodeObject:currentToneCurveHighlights        forKey:@"currentToneCurveHighlights"];
    [encoder encodeObject:currentToneCurveShadows           forKey:@"currentToneCurveShadows"];
    [encoder encodeObject:currentToneCurveBlackLevel        forKey:@"currentToneCurveBlackLevel"];
    [encoder encodeObject:currentToneCurveWhiteLevel        forKey:@"currentToneCurveWhiteLevel"];
    [encoder encodeObject:currentToneCurveVideoBlackLevel   forKey:@"currentToneCurveVideoBlackLevel"];
    
    //---------------------------------------------------------
    // Parameter Lists:
    //---------------------------------------------------------
    [encoder encodeObject:colorScienceVersionList           forKey:@"colorScienceVersionList"];
    [encoder encodeObject:gamutList                         forKey:@"gamutList"];
    [encoder encodeObject:gammaList                         forKey:@"gammaList"];
    [encoder encodeObject:isoList                           forKey:@"isoList"];
    [encoder encodeObject:lutModeList                       forKey:@"lutModeList"];
    
    //---------------------------------------------------------
    // Parameter Ranges:
    //---------------------------------------------------------
    [encoder encodeObject:exposureMin                       forKey:@"exposureMin"];
    [encoder encodeObject:exposureMax                       forKey:@"exposureMax"];

    [encoder encodeObject:whiteBalanceKelvinMin             forKey:@"whiteBalanceKelvinMin"];
    [encoder encodeObject:whiteBalanceKelvinMax             forKey:@"whiteBalanceKelvinMax"];

    [encoder encodeObject:whiteBalanceTintMin               forKey:@"whiteBalanceTintMin"];
    [encoder encodeObject:whiteBalanceTintMax               forKey:@"whiteBalanceTintMax"];

    [encoder encodeObject:toneCurveSaturationMin            forKey:@"toneCurveSaturationMin"];
    [encoder encodeObject:toneCurveSaturationMax            forKey:@"toneCurveSaturationMax"];

    [encoder encodeObject:toneCurveContrastMin              forKey:@"toneCurveContrastMin"];
    [encoder encodeObject:toneCurveContrastMax              forKey:@"toneCurveContrastMax"];

    [encoder encodeObject:toneCurveMidpointMin              forKey:@"toneCurveMidpointMin"];
    [encoder encodeObject:toneCurveMidpointMax              forKey:@"toneCurveMidpointMax"];

    [encoder encodeObject:toneCurveHighlightsMin            forKey:@"toneCurveHighlightsMin"];
    [encoder encodeObject:toneCurveHighlightsMax            forKey:@"toneCurveHighlightsMax"];

    [encoder encodeObject:toneCurveShadowsMin               forKey:@"toneCurveShadowsMin"];
    [encoder encodeObject:toneCurveShadowsMax               forKey:@"toneCurveShadowsMax"];

    [encoder encodeObject:toneCurveBlackLevelMin            forKey:@"toneCurveBlackLevelMin"];
    [encoder encodeObject:toneCurveBlackLevelMax            forKey:@"toneCurveBlackLevelMax"];

    [encoder encodeObject:toneCurveWhiteLevelMin            forKey:@"toneCurveWhiteLevelMin"];
    [encoder encodeObject:toneCurveWhiteLevelMax            forKey:@"toneCurveWhiteLevelMax"];
    
    //---------------------------------------------------------
    // Read Only:
    //---------------------------------------------------------
    [encoder encodeObject:isoReadOnly                       forKey:@"isoReadOnly"];
    [encoder encodeObject:exposureReadOnly                  forKey:@"exposureReadOnly"];
    [encoder encodeObject:whiteBalanceKelvinReadOnly        forKey:@"whiteBalanceKelvinReadOnly"];
    [encoder encodeObject:whiteBalanceTintReadOnly          forKey:@"whiteBalanceTintReadOnly"];
    [encoder encodeObject:colorScienceVersionReadOnly       forKey:@"colorScienceVersionReadOnly"];
    [encoder encodeObject:gamutReadOnly                     forKey:@"gamutReadOnly"];
    [encoder encodeObject:gammaReadOnly                     forKey:@"gammaReadOnly"];
    [encoder encodeObject:highlightRecoveryReadOnly         forKey:@"highlightRecoveryReadOnly"];
    [encoder encodeObject:gamutCompressionReadOnly          forKey:@"gamutCompressionReadOnly"];
    [encoder encodeObject:lutModeReadOnly                   forKey:@"lutModeReadOnly"];
    
    [encoder encodeObject:toneCurveSaturationReadOnly       forKey:@"toneCurveSaturationReadOnly"];
    [encoder encodeObject:toneCurveContrastReadOnly         forKey:@"toneCurveContrastReadOnly"];
    [encoder encodeObject:toneCurveMidpointReadOnly         forKey:@"toneCurveMidpointReadOnly"];
    [encoder encodeObject:toneCurveHighlightsReadOnly       forKey:@"toneCurveHighlightsReadOnly"];
    [encoder encodeObject:toneCurveShadowsReadOnly          forKey:@"toneCurveShadowsReadOnly"];
    [encoder encodeObject:toneCurveBlackLevelReadOnly       forKey:@"toneCurveBlackLevelReadOnly"];
    [encoder encodeObject:toneCurveWhiteLevelReadOnly       forKey:@"toneCurveWhiteLevelReadOnly"];
    [encoder encodeObject:toneCurveVideoBlackLevelReadOnly  forKey:@"toneCurveVideoBlackLevelReadOnly"];
        
    //---------------------------------------------------------
    // "Quality" Group:
    //---------------------------------------------------------
    [encoder encodeObject:decodeQuality                     forKey:@"decodeQuality"];
    [encoder encodeObject:checkedDecodeQuality              forKey:@"checkedDecodeQuality"];    
    
    //---------------------------------------------------------
    // "Frame Metadata" Group:
    //---------------------------------------------------------
    [encoder encodeObject:iso                               forKey:@"iso"];
    [encoder encodeObject:checkedISO                        forKey:@"checkedISO"];
                
    [encoder encodeObject:exposure                          forKey:@"exposure"];
    [encoder encodeObject:checkedExposure                   forKey:@"checkedExposure"];
        
    [encoder encodeObject:whiteBalanceKelvin                forKey:@"whiteBalanceKelvin"];
    [encoder encodeObject:checkedWhiteBalanceKelvin         forKey:@"checkedWhiteBalanceKelvin"];
    
    [encoder encodeObject:whiteBalanceTint                  forKey:@"whiteBalanceTint"];
    [encoder encodeObject:checkedWhiteBalanceTint           forKey:@"checkedWhiteBalanceTint"];
    
    //---------------------------------------------------------
    // "Clip Metadata" Group:
    //---------------------------------------------------------
    [encoder encodeObject:colorScienceGen                   forKey:@"colorScienceGen"];
    [encoder encodeObject:checkedColorScienceGen            forKey:@"checkedColorScienceGen"];
                
    [encoder encodeObject:gamut                             forKey:@"gamut"];
    [encoder encodeObject:checkedGamut                      forKey:@"checkedGamut"];
        
    [encoder encodeObject:gamma                             forKey:@"gamma"];
    [encoder encodeObject:checkedGamma                      forKey:@"checkedGamma"];
    
    [encoder encodeObject:highlightRecovery                 forKey:@"highlightRecovery"];
    [encoder encodeObject:checkedHighlightRecovery          forKey:@"checkedHighlightRecovery"];
            
    [encoder encodeObject:gamutCompression                  forKey:@"gamutCompression"];
    [encoder encodeObject:checkedGamutCompression           forKey:@"checkedGamutCompression"];
    
    [encoder encodeObject:lutMode                           forKey:@"lutMode"];
    [encoder encodeObject:checkedLUTMode                    forKey:@"checkedLUTMode"];
    
    //---------------------------------------------------------
    // "Custom Gamma Controls" Group::
    //---------------------------------------------------------
    [encoder encodeObject:toneCurveSaturation               forKey:@"toneCurveSaturation"];
    [encoder encodeObject:checkedToneCurveSaturation        forKey:@"checkedToneCurveSaturation"];
    
    [encoder encodeObject:toneCurveContrast                 forKey:@"toneCurveContrast"];
    [encoder encodeObject:checkedToneCurveContrast          forKey:@"checkedToneCurveContrast"];
        
    [encoder encodeObject:toneCurveMidpoint                 forKey:@"toneCurveMidpoint"];
    [encoder encodeObject:checkedToneCurveMidpoint          forKey:@"checkedToneCurveMidpoint"];
        
    [encoder encodeObject:toneCurveHighlights               forKey:@"toneCurveHighlights"];
    [encoder encodeObject:checkedToneCurveHighlights        forKey:@"checkedToneCurveHighlights"];
        
    [encoder encodeObject:toneCurveShadows                  forKey:@"toneCurveShadows"];
    [encoder encodeObject:checkedToneCurveShadows           forKey:@"checkedToneCurveShadows"];
        
    [encoder encodeObject:toneCurveBlackLevel               forKey:@"toneCurveBlackLevel"];
    [encoder encodeObject:checkedToneCurveBlackLevel        forKey:@"checkedToneCurveBlackLevel"];
        
    [encoder encodeObject:toneCurveWhiteLevel               forKey:@"toneCurveWhiteLevel"];
    [encoder encodeObject:checkedToneCurveWhiteLevel        forKey:@"checkedToneCurveWhiteLevel"];
    
    [encoder encodeObject:toneCurveVideoBlackLevel          forKey:@"toneCurveVideoBlackLevel"];
    [encoder encodeObject:checkedToneCurveVideoBlackLevel   forKey:@"checkedToneCurveVideoBlackLevel"];
}

@end
