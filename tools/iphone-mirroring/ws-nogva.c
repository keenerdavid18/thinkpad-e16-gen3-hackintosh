// ws-nogva: turn off WindowServer's AppleGVA (hardware video engine) scaler, which crashes WindowServer on this
// NootedGreen stack (assert in AVFPixelProcessCore_PrepareToTransferImages when iPhone Mirroring is scaled).
// SkyLight (macOS 26.7.1 25G241): set_debug_options -> WSCompositorSetLayerDetachment: 0x80000122 sets the flag
// gWSGVAEnabled = 1, which render_scaled_iosurface_to_dest_internal / supported_detachable_format read as
// "skip GVA" (the name is inverted); 0x80000121 clears it (GVA back on). Not an Apple-internal-only option.
// The caller needs the com.apple.private.CoreGraphics.debugging entitlement (works with amfi_get_out_of_my_way=1).
// Lost when WindowServer restarts: run at every login (LaunchAgent).
//   ws-nogva        GVA scaler off      ws-nogva on     GVA scaler back on (default)
#include <stdio.h>
#include <string.h>
#include <stdint.h>
extern int32_t SLSSetDebugOptions(uint32_t options);
extern int32_t SLSMainConnectionID(void);
int main(int argc, char **argv) {
    uint32_t opt = (argc > 1 && !strcmp(argv[1], "on")) ? 0x80000121 : 0x80000122;
    SLSMainConnectionID();   // opens the WindowServer connection (else MACH_SEND_INVALID_DEST)
    int32_t r = SLSSetDebugOptions(opt);
    printf("SLSSetDebugOptions(0x%08x) = %d  (WindowServer GVA scaler %s)\n", opt, r, opt == 0x80000122 ? "OFF" : "ON");
    return r != 0;
}
