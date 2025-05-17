//
//  GyroflowPlugIn.h
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 10/12/2022.
//

#import <Foundation/Foundation.h>
#import <FxPlug/FxPlugSDK.h>

#include "gyroflow.h"

#import "GyroflowParameters.h"
#import "GyroflowConstants.h"
#import "BRAWToolboxXMLReader.h"

#import "CustomButtonView.h"
#import "CustomDropZoneView.h"

#import "HeaderView.h"

#import "TileableRemoteBRAWShaderTypes.h"
#import "MetalDeviceCache.h"

#import <IOSurface/IOSurfaceObjC.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <unistd.h>
#include <sys/types.h>
#include <pwd.h>
#include <assert.h>

#include <ImageIO/ImageIO.h>

#import <Metal/Metal.h>
#import <AVFoundation/AVFoundation.h>

#import <CoreImage/CoreImage.h>

//---------------------------------------------------------
// Metal Performance Shaders for scaling:
//---------------------------------------------------------
#import <simd/simd.h>
#import <MetalKit/MetalKit.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>

#import <Foundation/Foundation.h>

//---------------------------------------------------------
// NSMenu Addition:
//---------------------------------------------------------
@interface NSMenu ()
- (BOOL)popUpMenuPositioningItem:(nullable NSMenuItem *)item atLocation:(NSPoint)location inView:(nullable NSView *)view appearance:(nullable NSAppearance *)appearance NS_AVAILABLE_MAC(10_6);
@end

//---------------------------------------------------------
// Gyroflow Plugin:
//---------------------------------------------------------
@interface GyroflowPlugIn : NSObject <FxTileableEffect> {    
    //---------------------------------------------------------
    // Cached Custom Views:
    //---------------------------------------------------------
    NSView* launchGyroflowView;
    NSView* importGyroflowProjectView;
    NSView* importMediaFileView;
    NSView* reloadGyroflowProjectView;
    NSView* loadLastGyroflowProjectView;
    NSView* dropZoneView;
    NSView* revealInFinderView;
    NSView* headerView;
    NSView* loadPresetLensProfileView;
    NSView* exportGyroflowProjectView;
    NSView* openUserGuideView;
    NSView* settingsView;
    
    //---------------------------------------------------------
    // Cached Lens Profile Lookup:
    //---------------------------------------------------------
    NSDictionary *lensProfilesLookup;

    //---------------------------------------------------------
    // Cached Error Images:
    //---------------------------------------------------------
    NSMutableDictionary<NSString *, id>  *_cachedErrorImages;
}

//---------------------------------------------------------
// A map from errorMessageID → CGImageRef (bridged to id)
//---------------------------------------------------------
@property (nonatomic, retain) NSMutableDictionary<NSString *, id> * _Nonnull cachedErrorImages;

//---------------------------------------------------------
// Progress Alert:
//---------------------------------------------------------
@property (weak) IBOutlet NSAlert* _Nullable        progressAlert;

//---------------------------------------------------------
// FxPlug API Manager:
//---------------------------------------------------------
@property (assign) id<PROAPIAccessing> _Nonnull     apiManager;

//---------------------------------------------------------
// Global Bookmark URLs:
//---------------------------------------------------------
@property (assign) NSMutableArray* _Nonnull         grantSandboxAccessURLs;

@end
