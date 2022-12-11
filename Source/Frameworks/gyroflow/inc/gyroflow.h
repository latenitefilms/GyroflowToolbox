//
//  gyroflow.h
//  Gyroflow for Final Cut Pro
//
//  Created by Chris Hocking on 11/12/2022.
//

bool start_gyroflow(unsigned long width, unsigned long height, const char* path);
bool process_pixels(int64_t* timestamp, int64_t* fov, int64_t* smoothness, int64_t* lensCorrection, uint8_t* buffer, unsigned long bufferSize);
bool stop_gyroflow(void);
