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
@interface GyroflowPlugIn : NSObject <FxTileableEffect> {}

- (NSView *_Nonnull)createViewForParameterID:(UInt32)parameterID NS_RETURNS_RETAINED;

//---------------------------------------------------------
// Cached Lens Profile Lookup:
//---------------------------------------------------------
@property (nonatomic, strong) NSDictionary * _Nullable lensProfilesLookup;

//---------------------------------------------------------
// Cached Error Images:
//---------------------------------------------------------
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> * _Nonnull cachedErrorImages;

//---------------------------------------------------------
// Progress Alert:
//---------------------------------------------------------
@property (strong) IBOutlet NSAlert* _Nullable progressAlert;

//---------------------------------------------------------
// FxPlug API Manager:
//---------------------------------------------------------
@property (nonatomic, strong) id<PROAPIAccessing> _Nonnull apiManager;

//---------------------------------------------------------
// Global Bookmark URLs:
//---------------------------------------------------------
@property (nonatomic, strong) NSMutableArray<NSURL *> * _Nonnull grantSandboxAccessURLs;

@end
