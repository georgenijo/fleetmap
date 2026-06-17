#include "CIOHID.h"
#include <string.h>

// Private IOKit / IOHIDFamily symbols — present in IOKit.framework but not in any
// public header. Declared here exactly as the framework exports them.
typedef CFTypeRef IOHIDEventSystemClientRef;
typedef CFTypeRef IOHIDServiceClientRef;
typedef CFTypeRef IOHIDEventRef;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern void IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef matching);
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
extern CFStringRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef property);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

// kIOHIDEventTypeTemperature = 15; the value field is (type << 16).
#define kIOHIDEventTypeTemperature 15
#define kIOHIDEventFieldTemperature (kIOHIDEventTypeTemperature << 16)

// Match the Apple vendor temperature-sensor usage page/usage.
static CFDictionaryRef temperatureMatching(void) {
    int page = 0xff00;   // kHIDPage_AppleVendor
    int usage = 0x0005;  // kHIDUsage_AppleVendor_TemperatureSensor
    CFNumberRef pageNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &page);
    CFNumberRef usageNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usage);
    const void *keys[2] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
    const void *vals[2] = { pageNum, usageNum };
    CFDictionaryRef d = CFDictionaryCreate(kCFAllocatorDefault, keys, vals, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFRelease(pageNum);
    CFRelease(usageNum);
    return d;
}

int fleet_read_temps(char *names, int stride, double *values, int maxCount) {
    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!client) return 0;

    CFDictionaryRef match = temperatureMatching();
    IOHIDEventSystemClientSetMatching(client, match);
    CFRelease(match);

    CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
    if (!services) { CFRelease(client); return 0; }

    int n = 0;
    CFIndex total = CFArrayGetCount(services);
    for (CFIndex i = 0; i < total && n < maxCount; i++) {
        IOHIDServiceClientRef svc = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
        IOHIDEventRef event = IOHIDServiceClientCopyEvent(svc, kIOHIDEventTypeTemperature, 0, 0);
        if (!event) continue;
        double v = IOHIDEventGetFloatValue(event, kIOHIDEventFieldTemperature);
        CFRelease(event);

        char *slot = names + (size_t)n * (size_t)stride;
        memset(slot, 0, stride);
        CFStringRef nameRef = IOHIDServiceClientCopyProperty(svc, CFSTR("Product"));
        if (nameRef) {
            CFStringGetCString(nameRef, slot, stride, kCFStringEncodingUTF8);
            CFRelease(nameRef);
        }
        values[n] = v;
        n++;
    }

    CFRelease(services);
    CFRelease(client);
    return n;
}
