/*
* Copyright (C) 2011 The Android Open Source Project
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
* http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/
#ifndef _GLES_V1_DISPATCH_H
#define _GLES_V1_DISPATCH_H

#include "gles1_dec.h"

bool init_gles1_dispatch();
void *gles1_dispatch_get_proc_func(const char *name, void *userData);

extern gles1_decoder_context_t s_gles1;

#endif  // _GLES_V1_DISPATCH_H
