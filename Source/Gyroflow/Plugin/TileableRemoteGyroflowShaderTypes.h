//
//  TileableRemoteGyroflowShaderTypes.h
//  Gyroflow for Final Cut Pro
//
//  Created by Chris Hocking on 10/12/2022.
//

#ifndef TileableRemoteGyroflowShaderTypes_h
#define TileableRemoteGyroflowShaderTypes_h

#import <simd/simd.h>

typedef enum GyroflowVertexInputIndex {
    BVI_Vertices        = 0,
    BVI_ViewportSize    = 1
} GyroflowVertexInputIndex;

typedef enum GyroflowTextureIndex {
    BTI_InputImage  = 0
} GyroflowTextureIndex;

typedef struct Vertex2D {
    vector_float2   position;
    vector_float2   textureCoordinate;
} Vertex2D;

#endif /* TileableRemoteGyroflowShaderTypes_h */

