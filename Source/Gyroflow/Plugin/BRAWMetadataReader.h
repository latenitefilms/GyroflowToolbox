//
//  BRAWMetadataReader.h
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 28/9/2022.
//

#import <Foundation/Foundation.h>

#import "BRAWMetadataReader.h"
#import "BRAWParameters.h"

@interface BRAWMetadataReader : NSObject

- (nullable BRAWParameters*)readMetadataFromPath:(nonnull NSString*)brawFilePath;

@end
