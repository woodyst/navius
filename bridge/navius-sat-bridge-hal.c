/*
 * navius-sat-bridge-hal.c
 * Accede al GPS hardware (ubuntu-platform-hardware-api) directamente como root,
 * sin pasar por lomiri-location-service ni el trust-store.
 * Escribe /run/navius-sat.txt con datos de satélites para que Navius los lea.
 *
 * Compilar en el dispositivo:
 *   gcc -O2 navius-sat-bridge-hal.c -o navius-sat-bridge-hal \
 *       -I/usr/include/ubuntu -lubuntu_platform_hardware_api
 */
#include <stdbool.h>
#include <ubuntu/hardware/gps.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <signal.h>
#include <sys/types.h>
#include <unistd.h>

#define OUTPUT_FILE "/run/user/32011/navius.woodyst/navius-sat.txt"
#define OUTPUT_TMP  "/run/user/32011/navius.woodyst/navius-sat.txt.tmp"
#define PHABLET_UID 32011
#define PHABLET_GID 32011

static volatile int g_running = 1;

/* Last known position — updated by location_cb, written by sv_status_cb. */
static double g_lat = 0, g_lon = 0, g_acc = -1, g_speed = -1;
static int    g_has_fix = 0;

static int guess_system(int prn) {
    if (prn >= 1  && prn <= 32) return 1;  /* GPS */
    if (prn >= 65 && prn <= 96) return 2;  /* GLONASS */
    if (prn >= 33 && prn <= 64) return 1;  /* SBAS */
    return 0;
}

static void sv_status_cb(UHardwareGpsSvStatus *sv, void *ctx) {
    (void)ctx;
    fprintf(stderr, "[bridge-hal] sv_status: %d sats\n", sv->num_svs);

    FILE *f = fopen(OUTPUT_TMP, "w");
    if (!f) { perror("[bridge-hal] fopen"); return; }

    /* Line 1: timestamp  Line 2: sat count  Line 3: pos (lat lon acc speed has_fix) */
    fprintf(f, "%ld\n%d\n%.8f %.8f %.2f %.2f %d\n",
            (long)time(NULL), sv->num_svs,
            g_lat, g_lon, g_acc, g_speed, g_has_fix);
    for (int i = 0; i < sv->num_svs && i < U_HARDWARE_GPS_MAX_SVS; i++) {
        UHardwareGpsSvInfo *s = &sv->sv_list[i];
        int used = (i < 32 && (sv->used_in_fix_mask & (1u << i))) ? 1 : 0;
        fprintf(f, "%d %.2f %.2f %.2f %d %d\n",
                s->prn, s->snr, s->azimuth, s->elevation,
                used, guess_system(s->prn));
    }
    fclose(f);
    chown(OUTPUT_TMP, PHABLET_UID, PHABLET_GID);
    rename(OUTPUT_TMP, OUTPUT_FILE);
    fflush(stderr);
}

static void location_cb(UHardwareGpsLocation *loc, void *ctx) {
    (void)ctx;
    g_lat     = loc->latitude;
    g_lon     = loc->longitude;
    g_acc     = (loc->flags & U_HARDWARE_GPS_LOCATION_HAS_ACCURACY) ? loc->accuracy : -1;
    g_speed   = (loc->flags & U_HARDWARE_GPS_LOCATION_HAS_SPEED)    ? loc->speed    : -1;
    g_has_fix = 1;
    fprintf(stderr, "[bridge-hal] location: lat=%.5f lon=%.5f acc=%.1fm\n",
            g_lat, g_lon, g_acc);
}

static void status_cb(uint16_t status, void *ctx) {
    (void)ctx;
    fprintf(stderr, "[bridge-hal] gps status: %d\n", (int)status);
}

static void nmea_cb(int64_t ts, const char *nmea, int len, void *ctx) {
    (void)ts; (void)len; (void)ctx;
    /* Could parse NMEA for satellites, but sv_status_cb is cleaner. */
}

static void set_capabilities_cb(uint32_t caps, void *ctx) {
    (void)ctx;
    fprintf(stderr, "[bridge-hal] capabilities: 0x%x\n", caps);
}

static void request_utc_time_cb(void *ctx)                             { (void)ctx; }
static void xtra_download_cb(void *ctx)                                { (void)ctx; }
static void agps_status_cb(UHardwareGpsAGpsStatus *s, void *ctx)       { (void)s; (void)ctx; }
static void gps_ni_notify_cb(UHardwareGpsNiNotification *n, void *ctx) { (void)n; (void)ctx; }
static void request_setid_cb(uint32_t f, void *ctx)                    { (void)f; (void)ctx; }
static void request_refloc_cb(uint32_t f, void *ctx)                   { (void)f; (void)ctx; }

static void handle_signal(int sig) { (void)sig; g_running = 0; }

int main(void) {
    signal(SIGINT,  handle_signal);
    signal(SIGTERM, handle_signal);

    UHardwareGpsParams params = {0};
    params.location_cb               = location_cb;
    params.status_cb                 = status_cb;
    params.sv_status_cb              = sv_status_cb;
    params.nmea_cb                   = nmea_cb;
    params.set_capabilities_cb       = set_capabilities_cb;
    params.request_utc_time_cb       = request_utc_time_cb;
    params.xtra_download_request_cb  = xtra_download_cb;
    params.agps_status_cb            = agps_status_cb;
    params.gps_ni_notify_cb          = gps_ni_notify_cb;
    params.request_setid_cb          = request_setid_cb;
    params.request_refloc_cb         = request_refloc_cb;
    params.context                   = NULL;

    fprintf(stderr, "[bridge-hal] u_hardware_gps_new...\n");
    UHardwareGps gps = u_hardware_gps_new(&params);
    if (!gps) {
        fprintf(stderr, "[bridge-hal] ERROR: returned NULL\n");
        return 1;
    }
    fprintf(stderr, "[bridge-hal] handle=%p\n", (void *)gps);

    u_hardware_gps_set_position_mode(
        gps,
        U_HARDWARE_GPS_POSITION_MODE_STANDALONE,
        U_HARDWARE_GPS_POSITION_RECURRENCE_PERIODIC,
        1000, 0, 0);

    if (!u_hardware_gps_start(gps)) {
        fprintf(stderr, "[bridge-hal] ERROR: start failed\n");
        u_hardware_gps_delete(gps);
        return 1;
    }
    fprintf(stderr, "[bridge-hal] GPS started, esperando satélites...\n");

    while (g_running) sleep(1);

    fprintf(stderr, "[bridge-hal] deteniendo\n");
    u_hardware_gps_stop(gps);
    u_hardware_gps_delete(gps);
    remove(OUTPUT_FILE);
    return 0;
}
