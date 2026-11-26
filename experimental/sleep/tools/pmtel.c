// pmtel: sample an IOReport group (default pmtelemetry_cpu) every 0.25 s for N seconds and print per-channel totals.
// The PUNIT counters in pmtelemetry_* are 16-bit and wrap (brandonedley, S0ixStandby #7): totals sum (b - a) & 0xFFFF
// per interval, so sample faster than one wrap. PC3_DMI_NOT_BLOCKED: 0 on a clean ADL boot, ~587/s once DPOF latched.
//   clang -O2 -o pmtel pmtel.c -framework CoreFoundation -lIOReport
//   ./pmtel [seconds=10] [group=pmtelemetry_cpu] [filter-substring]
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct IOReportSubscriptionRef *IOReportSubscriptionRef;
extern CFMutableDictionaryRef IOReportCopyChannelsInGroup(CFStringRef, CFStringRef, uint64_t, uint64_t, uint64_t);
extern IOReportSubscriptionRef IOReportCreateSubscription(void *, CFMutableDictionaryRef, CFMutableDictionaryRef *, uint64_t, CFTypeRef);
extern CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef, CFMutableDictionaryRef, CFTypeRef);
extern int64_t IOReportSimpleGetIntegerValue(CFDictionaryRef, int32_t *);
extern CFStringRef IOReportChannelGetChannelName(CFDictionaryRef);
extern CFStringRef IOReportChannelGetSubGroup(CFDictionaryRef);
extern int IOReportChannelGetFormat(CFDictionaryRef);

#define MAXCH 512
static char names[MAXCH][160];
static int64_t last[MAXCH], total[MAXCH], firstv[MAXCH], lastv[MAXCH];
static int nch;

static void cstr(CFStringRef s, char *out, size_t n) { out[0] = 0; if (s) CFStringGetCString(s, out, (CFIndex)n, kCFStringEncodingUTF8); }

static int sample(IOReportSubscriptionRef sub, CFMutableDictionaryRef subCh, int first)
{
	CFDictionaryRef smp = IOReportCreateSamples(sub, subCh, NULL);
	if (!smp) return -1;
	CFArrayRef arr = CFDictionaryGetValue(smp, CFSTR("IOReportChannels"));
	int n = arr ? (int)CFArrayGetCount(arr) : 0;
	for (int i = 0; i < n && i < MAXCH; i++) {
		CFDictionaryRef ch = CFArrayGetValueAtIndex(arr, i);
		int64_t v = IOReportSimpleGetIntegerValue(ch, NULL);
		if (first) {
			char a[64], b[96];
			cstr(IOReportChannelGetSubGroup(ch), a, sizeof(a)); cstr(IOReportChannelGetChannelName(ch), b, sizeof(b));
			snprintf(names[i], sizeof(names[i]), "%s/%s (fmt %d)", a, b, IOReportChannelGetFormat(ch));
			firstv[i] = v;
		} else total[i] += (v - last[i]) & 0xFFFF;
		last[i] = lastv[i] = v;
	}
	if (first) nch = n < MAXCH ? n : MAXCH;
	CFRelease(smp);
	return n;
}

int main(int argc, char **argv)
{
	double secs = argc > 1 ? atof(argv[1]) : 10;
	const char *grp = argc > 2 ? argv[2] : "pmtelemetry_cpu", *filt = argc > 3 ? argv[3] : NULL;
	CFStringRef g = CFStringCreateWithCString(NULL, grp, kCFStringEncodingUTF8);
	CFMutableDictionaryRef ch = IOReportCopyChannelsInGroup(g, NULL, 0, 0, 0);
	if (!ch) { fprintf(stderr, "no channels in group %s\n", grp); return 1; }
	CFMutableDictionaryRef subCh = NULL;
	IOReportSubscriptionRef sub = IOReportCreateSubscription(NULL, ch, &subCh, 0, NULL);
	if (!sub) { fprintf(stderr, "subscription failed\n"); return 1; }
	if (sample(sub, subCh, 1) <= 0) { fprintf(stderr, "no samples\n"); return 1; }
	int steps = (int)(secs / 0.25);
	for (int s = 0; s < steps; s++) { usleep(250000); sample(sub, subCh, 0); }
	printf("group %s, %d channels, %.1f s (16-bit wrap-aware deltas every 0.25 s)\n", grp, nch, steps * 0.25);
	for (int i = 0; i < nch; i++) {
		if (filt && !strstr(names[i], filt)) continue;
		if (!filt && total[i] == 0) continue;
		printf("  %-60s total %10lld  %9.1f/s   raw %lld -> %lld\n", names[i], (long long)total[i],
		       total[i] / (steps * 0.25), (long long)firstv[i], (long long)lastv[i]);
	}
	return 0;
}
