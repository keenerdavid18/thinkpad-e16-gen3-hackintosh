// vtbgra.dylib: make AirPlay to Mac / iPhone Mirroring show a picture on this Iris Xe (NootedGreen) stack.
// Idea from gianguyen14's airplayfix (b00t0x/WhateverXe#144, Tiger Lake): the iPhone stream is decoded to YUV 4:2:0
// ('420f'); WindowServer's YUV->RGB composite of it blanks the whole panel (and AppleGVA's scaler asserts, see
// ../gva-off). Forcing the decoder output to BGRA avoids both. Pair with `defaults write -g enableGVATransfer -bool NO`
// (pixel transfers on the CPU instead of AppleGVA).
// Interposes VTDecompressionSessionCreate(WithOptions) and rewrites the destination pixel format, only in the
// processes listed in kProcs; everywhere else it passes through untouched.
#include <VideoToolbox/VideoToolbox.h>
#include <CoreVideo/CoreVideo.h>
#include <os/log.h>
#include <stdlib.h>
#include <string.h>

#define INTERPOSE(repl, orig) __attribute__((used)) static struct { const void *r, *o; } _ip_##orig \
    __attribute__((section("__DATA,__interpose"))) = { (const void *)&repl, (const void *)&orig };

static const char *kProcs[] = { "ControlCenter", "iPhone Mirroring", "ScreenContinuityAgent", "AirPlayXPCHelper", NULL };
static int active(void) {
    static int v = -1;
    if (v < 0) { v = 0; const char *n = getprogname(); for (int i = 0; kProcs[i]; i++) if (!strcmp(n, kProcs[i])) v = 1; }
    return v;
}
__attribute__((constructor)) static void init(void) { if (active()) os_log(OS_LOG_DEFAULT, "[vtbgra] loaded in %{public}s[%d]", getprogname(), getpid()); }

static CFDictionaryRef bgra(CFDictionaryRef dest) {
    CFMutableDictionaryRef d = dest ? CFDictionaryCreateMutableCopy(NULL, 0, dest)
                                    : CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    int f = kCVPixelFormatType_32BGRA;
    CFNumberRef n = CFNumberCreate(NULL, kCFNumberSInt32Type, &f);
    CFDictionarySetValue(d, kCVPixelBufferPixelFormatTypeKey, n);
    CFRelease(n);
    return d;
}

// optional (VTBGRA_SW=1 in ControlCenter's environment): software decoder. Tried against the tiled picture in AirPlayed
// app video (YouTube 1080p); it did not help (the GPU YUV->BGRA conversion is the suspect), so it is off by default.
static CFDictionaryRef swspec(CFDictionaryRef spec) {
    if (!getenv("VTBGRA_SW")) return spec ? CFRetain(spec) : NULL;
    CFMutableDictionaryRef d = spec ? CFDictionaryCreateMutableCopy(NULL, 0, spec)
                                    : CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(d, kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder, kCFBooleanFalse);
    CFDictionarySetValue(d, kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder, kCFBooleanFalse);
    return d;
}
static void rel(CFTypeRef x) { if (x) CFRelease(x); }

static OSStatus my_create(CFAllocatorRef a, CMVideoFormatDescriptionRef f, CFDictionaryRef spec, CFDictionaryRef dest,
                          const VTDecompressionOutputCallbackRecord *cb, VTDecompressionSessionRef *out) {
    if (!active()) return VTDecompressionSessionCreate(a, f, spec, dest, cb, out);
    CFDictionaryRef nd = bgra(dest), ns = swspec(spec);
    OSStatus s = VTDecompressionSessionCreate(a, f, ns, nd, cb, out);
    CFRelease(nd); rel(ns);
    os_log(OS_LOG_DEFAULT, "[vtbgra] %{public}s: VTDecompressionSessionCreate -> BGRA, status %d", getprogname(), (int)s);
    return s;
}
INTERPOSE(my_create, VTDecompressionSessionCreate)

// private variant (8 arguments, the 4th is the destination attributes dictionary), used by AirPlay on 15.x/26.x
extern OSStatus VTDecompressionSessionCreateWithOptions(void *, void *, void *, void *, void *, void *, void *, void *);
static OSStatus my_cwo(void *a, void *b, void *c, void *d, void *e, void *f, void *g, void *h) {
    if (!active() || (d && CFGetTypeID((CFTypeRef)d) != CFDictionaryGetTypeID()))
        return VTDecompressionSessionCreateWithOptions(a, b, c, d, e, f, g, h);
    int cdict = !c || CFGetTypeID((CFTypeRef)c) == CFDictionaryGetTypeID();
    CFDictionaryRef nd = bgra((CFDictionaryRef)d), ns = cdict ? swspec((CFDictionaryRef)c) : NULL;
    OSStatus s = VTDecompressionSessionCreateWithOptions(a, b, cdict ? (void *)ns : c, (void *)nd, e, f, g, h);
    CFRelease(nd); rel(ns);
    os_log(OS_LOG_DEFAULT, "[vtbgra] %{public}s: VTDecompressionSessionCreateWithOptions -> BGRA, %{public}s decoder, spec %{public}@, status %d",
           getprogname(), cdict && getenv("VTBGRA_SW") ? "software" : "default", cdict ? (CFTypeRef)c : CFSTR("(not a dict)"), (int)s);
    return s;
}
INTERPOSE(my_cwo, VTDecompressionSessionCreateWithOptions)
