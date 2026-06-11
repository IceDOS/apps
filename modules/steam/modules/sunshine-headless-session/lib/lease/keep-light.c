/* keep-light: a minimal Wayland toplevel that keeps gamescope (and thus the
 * HDMI-A-1 connector) lit, with no ongoing GPU/CPU cost.
 *
 * gamescope only modesets/scans out a connector when it has a focused toplevel
 * to composite — an idle gamescope (`-- sleep infinity`) never lights it. This
 * creates ONE tiny black xdg_toplevel, attaches a single SHM frame, commits once,
 * then just dispatches Wayland events forever (no redraw). gamescope scales it
 * fullscreen + page-flips it every vblank (cheap, static), so HDMI-A-1 stays lit
 * in HDR at a stable capture index. Steam is launched on top of it on demand.
 */
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <wayland-client.h>
#include "xdg-shell-client-protocol.h"

static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct xdg_wm_base *wm_base;
static struct wl_surface *surface;
static struct wl_buffer *buffer;
static int committed = 0;
static char env_path[4096];

/* Record gamescope's display env so the on-demand Steam launch (prep-cmd) can
 * target THIS compositor. gamescope sets, for us (its child), DISPLAY=its
 * Xwayland and WAYLAND_DISPLAY=gamescope-0. Written only AFTER the first frame is
 * committed (connector lit) — the prep-cmd waits on this file, so its presence
 * must mean HDMI-A-1 is actually up, else Polaris enumerates it too early and the
 * capture index falls through to a desktop monitor. */
static void write_env(void)
{
	if (!env_path[0])
		return;
	FILE *f = fopen(env_path, "w");
	if (f) {
		const char *d = getenv("DISPLAY");
		const char *w = getenv("WAYLAND_DISPLAY");
		fprintf(f, "DISPLAY=%s\nWAYLAND_DISPLAY=%s\n", d ? d : "", w ? w : "");
		fclose(f);
	}
}

static void wm_base_ping(void *d, struct xdg_wm_base *b, uint32_t serial)
{
	(void)d;
	xdg_wm_base_pong(b, serial);
}
static const struct xdg_wm_base_listener wm_base_listener = {
	.ping = wm_base_ping,
};

static void reg_global(void *d, struct wl_registry *r, uint32_t name,
		       const char *iface, uint32_t ver)
{
	(void)d;
	(void)ver;
	if (strcmp(iface, wl_compositor_interface.name) == 0) {
		compositor = wl_registry_bind(r, name, &wl_compositor_interface, 4);
	} else if (strcmp(iface, wl_shm_interface.name) == 0) {
		shm = wl_registry_bind(r, name, &wl_shm_interface, 1);
	} else if (strcmp(iface, xdg_wm_base_interface.name) == 0) {
		wm_base = wl_registry_bind(r, name, &xdg_wm_base_interface, 1);
		xdg_wm_base_add_listener(wm_base, &wm_base_listener, NULL);
	}
}
static void reg_remove(void *d, struct wl_registry *r, uint32_t n)
{
	(void)d; (void)r; (void)n;
}
static const struct wl_registry_listener reg_listener = {
	.global = reg_global,
	.global_remove = reg_remove,
};

static void xdg_surface_configure(void *d, struct xdg_surface *xs, uint32_t serial)
{
	(void)d;
	xdg_surface_ack_configure(xs, serial);
	if (!committed) {
		wl_surface_attach(surface, buffer, 0, 0);
		wl_surface_damage_buffer(surface, 0, 0, INT32_MAX, INT32_MAX);
		wl_surface_commit(surface);
		committed = 1;
		write_env(); /* surface mapped → connector lighting; safe to publish env */
	}
}
static const struct xdg_surface_listener xdg_surface_listener = {
	.configure = xdg_surface_configure,
};

static void tl_configure(void *d, struct xdg_toplevel *t, int32_t w, int32_t h,
			 struct wl_array *states)
{
	(void)d; (void)t; (void)w; (void)h; (void)states;
}
static void tl_close(void *d, struct xdg_toplevel *t)
{
	(void)d; (void)t;
	exit(0);
}
static const struct xdg_toplevel_listener tl_listener = {
	.configure = tl_configure,
	.close = tl_close,
};

static struct wl_buffer *black_buffer(int w, int h)
{
	int stride = w * 4;
	int size = stride * h;
	int fd = memfd_create("keep-light", MFD_CLOEXEC);
	if (fd < 0 || ftruncate(fd, size) < 0)
		return NULL;
	void *data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (data == MAP_FAILED)
		return NULL;
	memset(data, 0, size); /* XRGB8888 zero = opaque black */
	struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size);
	struct wl_buffer *buf = wl_shm_pool_create_buffer(pool, 0, w, h, stride,
							  WL_SHM_FORMAT_XRGB8888);
	wl_shm_pool_destroy(pool);
	munmap(data, size);
	close(fd);
	return buf;
}

int main(void)
{
	struct wl_display *dpy = wl_display_connect(NULL);
	if (!dpy) {
		fprintf(stderr, "keep-light: cannot connect to Wayland\n");
		return 1;
	}
	struct wl_registry *reg = wl_display_get_registry(dpy);
	wl_registry_add_listener(reg, &reg_listener, NULL);
	wl_display_roundtrip(dpy);
	if (!compositor || !shm || !wm_base) {
		fprintf(stderr, "keep-light: missing wl_compositor/wl_shm/xdg_wm_base\n");
		return 1;
	}

	/* Compute the env path + clear any stale file from a previous instance, so the
	 * prep-cmd never sees an old env before this gamescope has lit the connector. */
	const char *rt = getenv("XDG_RUNTIME_DIR");
	if (rt) {
		snprintf(env_path, sizeof env_path, "%s/sunshine-headless.env", rt);
		unlink(env_path);
	}

	buffer = black_buffer(64, 64);
	if (!buffer) {
		fprintf(stderr, "keep-light: couldn't create buffer\n");
		return 1;
	}

	surface = wl_compositor_create_surface(compositor);
	struct xdg_surface *xs = xdg_wm_base_get_xdg_surface(wm_base, surface);
	xdg_surface_add_listener(xs, &xdg_surface_listener, NULL);
	struct xdg_toplevel *tl = xdg_surface_get_toplevel(xs);
	xdg_toplevel_add_listener(tl, &tl_listener, NULL);
	xdg_toplevel_set_title(tl, "sunshine-headless-keeplight");
	xdg_toplevel_set_app_id(tl, "sunshine-headless-keeplight");
	wl_surface_commit(surface); /* trigger first configure → attach in handler */

	while (wl_display_dispatch(dpy) != -1)
		;
	return 0;
}
