// Copyright (C) 2015 The Android Open Source Project
//
// This software is licensed under the terms of the GNU General Public
// License version 2, as published by the Free Software Foundation, and
// may be copied, distributed, and modified under those terms.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

/* NOTE:
 * This file contains thin wrappers around actual system related library
 * functions from android/base/system/System.h.
 * Keep this lean. DO NOT implement any real functionality here.
 */
#include "android/base/system/System.h"

// This is a very thin wrapper around C++ implementations of some functions
// NOTE: cpp headers need to go before this so that inttypes.h doesn't pollute
// types.
#include "android/utils/system.h"

using android::base::System;

int64_t get_user_time_ms() {
    return static_cast<int64_t>(System::get()->getProcessTimes().userMs);
}

int64_t get_system_time_ms() {
    return static_cast<int64_t>(System::get()->getProcessTimes().systemMs);
}
