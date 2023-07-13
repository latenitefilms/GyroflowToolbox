//
//  BRAWParameters.h
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 23/10/2022.
//

#ifndef BRAWParameters_h
#define BRAWParameters_h

//---------------------------------------------------------
// BRAW Plugin Parameters:
//---------------------------------------------------------
@interface BRAWParameters : NSObject <NSCoding, NSSecureCoding> {
    //---------------------------------------------------------
    // BRAW Path & Frame Information:
    //---------------------------------------------------------
    NSString *brawFilePath;
    NSData   *bookmarkData;
    NSNumber *frameToRender;    
    NSNumber *frameCount;
    NSNumber *frameRate;
    NSNumber *width;
    NSNumber *height;
    NSString *startTimecode;
    NSNumber *baseFrameIndex;
    NSNumber *isDropFrameTimecode;
    NSString *uniqueID;
    NSString *creationDate;
    
    //---------------------------------------------------------
    // Metadata:
    //---------------------------------------------------------
    NSMutableDictionary *clipMetadata;
    NSMutableDictionary *frameMetadata;
    
    //---------------------------------------------------------
    // Audio:
    //---------------------------------------------------------
    NSNumber *audioSamples;
    NSNumber *audioBitDepth;
    NSNumber *audioChannelCount;
    NSNumber *audioSampleRate;
    
    //---------------------------------------------------------
    // Current Values:
    //---------------------------------------------------------
    NSNumber *currentColorScienceGen;
    NSString *currentGamut;
    NSString *currentGamma;
    NSNumber *currentHighlightRecovery;
    NSNumber *currentGamutCompression;
    
    NSNumber *currentISO;
    NSNumber *currentExposure;
    NSNumber *currentWhiteBalanceKelvin;
    NSNumber *currentWhiteBalanceTint;
    NSString *currentLUTMode;

    NSNumber *currentToneCurveSaturation;
    NSNumber *currentToneCurveContrast;
    NSNumber *currentToneCurveMidpoint;
    NSNumber *currentToneCurveHighlights;
    NSNumber *currentToneCurveShadows;
    NSNumber *currentToneCurveBlackLevel;
    NSNumber *currentToneCurveWhiteLevel;
    NSNumber *currentToneCurveVideoBlackLevel;
    
    //---------------------------------------------------------
    // Parameter Lists:
    //---------------------------------------------------------
    NSArray *colorScienceVersionList;
    NSArray *gamutList;
    NSArray *gammaList;
    NSArray *isoList;
    NSArray *lutModeList;
    
    //---------------------------------------------------------
    // Parameter Read Only:
    //---------------------------------------------------------
    NSNumber *isoReadOnly;
    NSNumber *exposureReadOnly;
    NSNumber *whiteBalanceKelvinReadOnly;
    NSNumber *whiteBalanceTintReadOnly;
    
    NSNumber *colorScienceVersionReadOnly;
    NSNumber *gamutReadOnly;
    NSNumber *gammaReadOnly;
    NSNumber *highlightRecoveryReadOnly;
    NSNumber *gamutCompressionReadOnly;
    NSNumber *lutModeReadOnly;
    
    NSNumber *toneCurveSaturationReadOnly;
    NSNumber *toneCurveContrastReadOnly;
    NSNumber *toneCurveMidpointReadOnly;
    NSNumber *toneCurveHighlightsReadOnly;
    NSNumber *toneCurveShadowsReadOnly;
    NSNumber *toneCurveBlackLevelReadOnly;
    NSNumber *toneCurveWhiteLevelReadOnly;
    NSNumber *toneCurveVideoBlackLevelReadOnly;

    //---------------------------------------------------------
    // Parameter Ranges:
    //---------------------------------------------------------
    NSNumber *exposureMin;
    NSNumber *exposureMax;

    NSNumber *whiteBalanceKelvinMin;
    NSNumber *whiteBalanceKelvinMax;
    
    NSNumber *whiteBalanceTintMin;
    NSNumber *whiteBalanceTintMax;
    
    NSNumber *toneCurveSaturationMin;
    NSNumber *toneCurveSaturationMax;
    
    NSNumber *toneCurveContrastMin;
    NSNumber *toneCurveContrastMax;
    
    NSNumber *toneCurveMidpointMin;
    NSNumber *toneCurveMidpointMax;
    
    NSNumber *toneCurveHighlightsMin;
    NSNumber *toneCurveHighlightsMax;
    
    NSNumber *toneCurveShadowsMin;
    NSNumber *toneCurveShadowsMax;
    
    NSNumber *toneCurveBlackLevelMin;
    NSNumber *toneCurveBlackLevelMax;
    
    NSNumber *toneCurveWhiteLevelMin;
    NSNumber *toneCurveWhiteLevelMax;
    
    //---------------------------------------------------------
    // "Quality" Group:
    //---------------------------------------------------------
    NSNumber *decodeQuality;
    NSNumber *checkedDecodeQuality;
    
    //---------------------------------------------------------
    // "Frame Metadata" Group:
    //---------------------------------------------------------
    NSNumber *iso;
    NSNumber *checkedISO;
    
    NSNumber *exposure;
    NSNumber *checkedExposure;
    
    NSNumber *whiteBalanceKelvin;
    NSNumber *checkedWhiteBalanceKelvin;
    
    NSNumber *whiteBalanceTint;
    NSNumber *checkedWhiteBalanceTint;
    
    //---------------------------------------------------------
    // "Clip Metadata" Group:
    //---------------------------------------------------------
    NSNumber *colorScienceGen;
    NSNumber *checkedColorScienceGen;

    NSNumber *gamut;
    NSNumber *checkedGamut;
    
    NSNumber *gamma;
    NSNumber *checkedGamma;
    
    NSNumber *highlightRecovery;
    NSNumber *checkedHighlightRecovery;
    
    NSNumber *gamutCompression;
    NSNumber *checkedGamutCompression;
    
    NSNumber *lutMode;
    NSNumber *checkedLUTMode;
    
    //---------------------------------------------------------
    // "Custom Gamma Controls" Group::
    //---------------------------------------------------------
    NSNumber *toneCurveSaturation;
    NSNumber *checkedToneCurveSaturation;
    
    NSNumber *toneCurveContrast;
    NSNumber *checkedToneCurveContrast;
    
    NSNumber *toneCurveMidpoint;
    NSNumber *checkedToneCurveMidpoint;
    
    NSNumber *toneCurveHighlights;
    NSNumber *checkedToneCurveHighlights;
    
    NSNumber *toneCurveShadows;
    NSNumber *checkedToneCurveShadows;
    
    NSNumber *toneCurveBlackLevel;
    NSNumber *checkedToneCurveBlackLevel;

    NSNumber *toneCurveWhiteLevel;
    NSNumber *checkedToneCurveWhiteLevel;
    
    NSNumber *toneCurveVideoBlackLevel;
    NSNumber *checkedToneCurveVideoBlackLevel;
}

//---------------------------------------------------------
// BRAW Path & Frame Information:
//---------------------------------------------------------
@property (nonatomic, copy) NSString *brawFilePath;
@property (nonatomic, copy) NSData   *bookmarkData;
@property (nonatomic, copy) NSNumber *frameToRender;
@property (nonatomic, copy) NSNumber *frameCount;
@property (nonatomic, copy) NSNumber *frameRate;
@property (nonatomic, copy) NSNumber *width;
@property (nonatomic, copy) NSNumber *height;
@property (nonatomic, copy) NSString *startTimecode;
@property (nonatomic, copy) NSNumber *baseFrameIndex;
@property (nonatomic, copy) NSNumber *isDropFrameTimecode;
@property (nonatomic, copy) NSString *uniqueID;
@property (nonatomic, copy) NSString *creationDate;

//---------------------------------------------------------
// Metadata:
//---------------------------------------------------------
@property (nonatomic, copy) NSDictionary *clipMetadata;
@property (nonatomic, copy) NSDictionary *frameMetadata;

//---------------------------------------------------------
// Audio:
//---------------------------------------------------------
@property (nonatomic, copy) NSNumber *audioSamples;
@property (nonatomic, copy) NSNumber *audioBitDepth;
@property (nonatomic, copy) NSNumber *audioChannelCount;
@property (nonatomic, copy) NSNumber *audioSampleRate;

//---------------------------------------------------------
// Current Values:
//---------------------------------------------------------
@property (nonatomic, copy) NSNumber *currentColorScienceGen;
@property (nonatomic, copy) NSString *currentGamut;
@property (nonatomic, copy) NSString *currentGamma;
@property (nonatomic, copy) NSNumber *currentHighlightRecovery;
@property (nonatomic, copy) NSNumber *currentGamutCompression;

@property (nonatomic, copy) NSNumber *currentISO;
@property (nonatomic, copy) NSNumber *currentExposure;
@property (nonatomic, copy) NSNumber *currentWhiteBalanceKelvin;
@property (nonatomic, copy) NSNumber *currentWhiteBalanceTint;
@property (nonatomic, copy) NSString *currentLUTMode;

@property (nonatomic, copy) NSNumber *currentToneCurveSaturation;
@property (nonatomic, copy) NSNumber *currentToneCurveContrast;
@property (nonatomic, copy) NSNumber *currentToneCurveMidpoint;
@property (nonatomic, copy) NSNumber *currentToneCurveHighlights;
@property (nonatomic, copy) NSNumber *currentToneCurveShadows;
@property (nonatomic, copy) NSNumber *currentToneCurveBlackLevel;
@property (nonatomic, copy) NSNumber *currentToneCurveWhiteLevel;
@property (nonatomic, copy) NSNumber *currentToneCurveVideoBlackLevel;

//---------------------------------------------------------
// Parameter Lists:
//---------------------------------------------------------
@property (nonatomic, copy) NSArray *colorScienceVersionList;
@property (nonatomic, copy) NSArray *gamutList;
@property (nonatomic, copy) NSArray *gammaList;
@property (nonatomic, copy) NSArray *isoList;
@property (nonatomic, copy) NSArray *lutModeList;

//---------------------------------------------------------
// Parameter Read Only:
//---------------------------------------------------------
@property (nonatomic, copy) NSNumber *isoReadOnly;
@property (nonatomic, copy) NSNumber *exposureReadOnly;
@property (nonatomic, copy) NSNumber *whiteBalanceKelvinReadOnly;
@property (nonatomic, copy) NSNumber *whiteBalanceTintReadOnly;
@property (nonatomic, copy) NSNumber *colorScienceVersionReadOnly;
@property (nonatomic, copy) NSNumber *gamutReadOnly;
@property (nonatomic, copy) NSNumber *gammaReadOnly;
@property (nonatomic, copy) NSNumber *highlightRecoveryReadOnly;
@property (nonatomic, copy) NSNumber *gamutCompressionReadOnly;
@property (nonatomic, copy) NSNumber *lutModeReadOnly;

@property (nonatomic, copy) NSNumber *toneCurveSaturationReadOnly;
@property (nonatomic, copy) NSNumber *toneCurveContrastReadOnly;
@property (nonatomic, copy) NSNumber *toneCurveMidpointReadOnly;
@property (nonatomic, copy) NSNumber *toneCurveHighlightsReadOnly;
@property (nonatomic, copy) NSNumber *toneCurveShadowsReadOnly;
@property (nonatomic, copy) NSNumber *toneCurveBlackLevelReadOnly;
@property (nonatomic, copy) NSNumber *toneCurveWhiteLevelReadOnly;
@property (nonatomic, copy) NSNumber *toneCurveVideoBlackLevelReadOnly;

//---------------------------------------------------------
// Parameter Ranges:
//---------------------------------------------------------
@property (nonatomic, copy) NSNumber *exposureMin;
@property (nonatomic, copy) NSNumber *exposureMax;

@property (nonatomic, copy) NSNumber *whiteBalanceKelvinMin;
@property (nonatomic, copy) NSNumber *whiteBalanceKelvinMax;

@property (nonatomic, copy) NSNumber *whiteBalanceTintMin;
@property (nonatomic, copy) NSNumber *whiteBalanceTintMax;

@property (nonatomic, copy) NSNumber *toneCurveSaturationMin;
@property (nonatomic, copy) NSNumber *toneCurveSaturationMax;

@property (nonatomic, copy) NSNumber *toneCurveContrastMin;
@property (nonatomic, copy) NSNumber *toneCurveContrastMax;

@property (nonatomic, copy) NSNumber *toneCurveMidpointMin;
@property (nonatomic, copy) NSNumber *toneCurveMidpointMax;

@property (nonatomic, copy) NSNumber *toneCurveHighlightsMin;
@property (nonatomic, copy) NSNumber *toneCurveHighlightsMax;

@property (nonatomic, copy) NSNumber *toneCurveShadowsMin;
@property (nonatomic, copy) NSNumber *toneCurveShadowsMax;

@property (nonatomic, copy) NSNumber *toneCurveBlackLevelMin;
@property (nonatomic, copy) NSNumber *toneCurveBlackLevelMax;

@property (nonatomic, copy) NSNumber *toneCurveWhiteLevelMin;
@property (nonatomic, copy) NSNumber *toneCurveWhiteLevelMax;

//---------------------------------------------------------
// "Quality" Group:
//---------------------------------------------------------
@property (nonatomic, copy) NSNumber *decodeQuality;
@property (nonatomic, copy) NSNumber *checkedDecodeQuality;

//---------------------------------------------------------
// "Frame Metadata" Group:
//---------------------------------------------------------
@property (nonatomic, copy) NSNumber *iso;
@property (nonatomic, copy) NSNumber *checkedISO;

@property (nonatomic, copy) NSNumber *exposure;
@property (nonatomic, copy) NSNumber *checkedExposure;

@property (nonatomic, copy) NSNumber *whiteBalanceKelvin;
@property (nonatomic, copy) NSNumber *checkedWhiteBalanceKelvin;

@property (nonatomic, copy) NSNumber *whiteBalanceTint;
@property (nonatomic, copy) NSNumber *checkedWhiteBalanceTint;

//---------------------------------------------------------
// "Clip Metadata" Group:
//---------------------------------------------------------
@property (nonatomic, copy) NSNumber *colorScienceGen;
@property (nonatomic, copy) NSNumber *checkedColorScienceGen;

@property (nonatomic, copy) NSNumber *gamut;
@property (nonatomic, copy) NSNumber *checkedGamut;

@property (nonatomic, copy) NSNumber *gamma;
@property (nonatomic, copy) NSNumber *checkedGamma;

@property (nonatomic, copy) NSNumber *highlightRecovery;
@property (nonatomic, copy) NSNumber *checkedHighlightRecovery;

@property (nonatomic, copy) NSNumber *gamutCompression;
@property (nonatomic, copy) NSNumber *checkedGamutCompression;

@property (nonatomic, copy) NSNumber *lutMode;
@property (nonatomic, copy) NSNumber *checkedLUTMode;

//---------------------------------------------------------
// "Custom Gamma Controls" Group::
//---------------------------------------------------------
@property (nonatomic, copy) NSNumber *toneCurveSaturation;
@property (nonatomic, copy) NSNumber *checkedToneCurveSaturation;

@property (nonatomic, copy) NSNumber *toneCurveContrast;
@property (nonatomic, copy) NSNumber *checkedToneCurveContrast;

@property (nonatomic, copy) NSNumber *toneCurveMidpoint;
@property (nonatomic, copy) NSNumber *checkedToneCurveMidpoint;

@property (nonatomic, copy) NSNumber *toneCurveHighlights;
@property (nonatomic, copy) NSNumber *checkedToneCurveHighlights;

@property (nonatomic, copy) NSNumber *toneCurveShadows;
@property (nonatomic, copy) NSNumber *checkedToneCurveShadows;

@property (nonatomic, copy) NSNumber *toneCurveBlackLevel;
@property (nonatomic, copy) NSNumber *checkedToneCurveBlackLevel;

@property (nonatomic, copy) NSNumber *toneCurveWhiteLevel;
@property (nonatomic, copy) NSNumber *checkedToneCurveWhiteLevel;

@property (nonatomic, copy) NSNumber *toneCurveVideoBlackLevel;
@property (nonatomic, copy) NSNumber *checkedToneCurveVideoBlackLevel;

@end

#endif /* BRAWParameters_h */
