//
//  TileableRemoteBRAWShaderTypes.h
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 17/9/2022.
//

#ifndef TileableRemoteBRAWShaderTypes_h
#define TileableRemoteBRAWShaderTypes_h

#import <simd/simd.h>

typedef enum BRAWVertexInputIndex {
    BVI_Vertices        = 0,
    BVI_ViewportSize    = 1
} BRAWVertexInputIndex;

typedef enum BRAWTextureIndex {
    BTI_InputImage  = 0
} BRAWTextureIndex;

typedef struct Vertex2D {
    vector_float2   position;
    vector_float2   textureCoordinate;
} Vertex2D;

#endif /* TileableRemoteBRAWShaderTypes_h */
