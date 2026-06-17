#ifndef CIOHID_H
#define CIOHID_H

#include <CoreFoundation/CoreFoundation.h>

// Read Apple Silicon die temperatures via the private IOHIDEventSystemClient API
// (the same source iStat Menus / Stats / macmon use — no sudo, no entitlement).
// Fills `names` (a flat buffer of `count` rows, each `stride` bytes, NUL-terminated
// UTF-8) and `values` (degrees C). Returns the number of sensors written, capped
// at `maxCount`. Returns 0 if the private API is unavailable (e.g. Intel).
int fleet_read_temps(char *names, int stride, double *values, int maxCount);

#endif
