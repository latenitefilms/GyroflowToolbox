//
//  GyroflowWrapper.h
//  Wrapper Application
//
//  Created by Chris Hocking on 11/12/2022.
//

#ifndef GyroflowWrapper_h
#define GyroflowWrapper_h

#include <stdio.h>
#include <stdbool.h>

bool startGyroflow(unsigned long width, unsigned long height, const char* path);
bool processPixels(int64_t* timestamp, int64_t* fov, int64_t* smoothness, int64_t* lensCorrection, int buffer, int size);
bool stopGyroflow(void);

#endif /* GyroflowWrapper_h */
