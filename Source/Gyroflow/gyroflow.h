//
//  gyroflow.h
//  Gyroflow for Final Cut Pro
//
//  Created by Chris Hocking on 11/12/2022.
//

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int processFrame(unsigned long width, unsigned long height, const char* path, int64_t* timestamp, int64_t* fov, int64_t* smoothness, int64_t* lensCorrection, uint8_t* buffer, unsigned long bufferSize);
