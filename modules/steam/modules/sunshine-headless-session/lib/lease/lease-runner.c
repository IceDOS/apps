/* lease-runner: acquire a wp_drm_lease_v1 lease for a named connector from the
 * running compositor (KWin), then run a command (gamescope --backend drm …) on
 * that lease via the libseat-dlm LD_PRELOAD shim.
 *
 *   SUNSHINE_HEADLESS_OUTPUT=HDMI-A-1 lease-runner gamescope --backend drm -- vkcube
 *
 * The lease must outlive the child, so this process HOLDS the wayland connection
 * (= holds the lease) and forks the child rather than exec-replacing itself.
 * Env passed to the child: DLM_LEASE_FD (the leased fd), LD_PRELOAD (the shim),
 * WLR_DRM_DEVICES (pin the card so wlroots probes once).
 */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <unistd.h>
#include <wayland-client.h>
#include "drm-lease-v1-client-protocol.h"

#define MAX_CONN 32

struct conn {
	struct wp_drm_lease_connector_v1 *obj;
	char name[128];
};

static struct wp_drm_lease_device_v1 *lease_device;
static struct conn conns[MAX_CONN];
static int n_conns;
static int lease_fd = -1;
static int lease_finished;

/* --- connector listener --- */
static void c_name(void *data, struct wp_drm_lease_connector_v1 *c, const char *name)
{
	(void)c;
	struct conn *cc = data;
	snprintf(cc->name, sizeof cc->name, "%s", name);
}
static void c_description(void *d, struct wp_drm_lease_connector_v1 *c, const char *s)
{
	(void)d; (void)c; (void)s;
}
static void c_connector_id(void *d, struct wp_drm_lease_connector_v1 *c, uint32_t id)
{
	(void)d; (void)c; (void)id;
}
static void c_done(void *d, struct wp_drm_lease_connector_v1 *c) { (void)d; (void)c; }
static void c_withdrawn(void *d, struct wp_drm_lease_connector_v1 *c) { (void)d; (void)c; }
static const struct wp_drm_lease_connector_v1_listener c_listener = {
	.name = c_name,
	.description = c_description,
	.connector_id = c_connector_id,
	.done = c_done,
	.withdrawn = c_withdrawn,
};

/* --- device listener --- */
static void d_drm_fd(void *d, struct wp_drm_lease_device_v1 *dev, int fd)
{
	(void)d; (void)dev;
	if (fd >= 0)
		close(fd);
}
static void d_connector(void *d, struct wp_drm_lease_device_v1 *dev,
			struct wp_drm_lease_connector_v1 *connector)
{
	(void)d; (void)dev;
	if (n_conns < MAX_CONN) {
		struct conn *cc = &conns[n_conns++];
		cc->obj = connector;
		wp_drm_lease_connector_v1_add_listener(connector, &c_listener, cc);
	}
}
static void d_done(void *d, struct wp_drm_lease_device_v1 *dev) { (void)d; (void)dev; }
static void d_released(void *d, struct wp_drm_lease_device_v1 *dev) { (void)d; (void)dev; }
static const struct wp_drm_lease_device_v1_listener d_listener = {
	.drm_fd = d_drm_fd,
	.connector = d_connector,
	.done = d_done,
	.released = d_released,
};

/* --- lease listener --- */
static void l_lease_fd(void *d, struct wp_drm_lease_v1 *l, int fd)
{
	(void)d; (void)l;
	lease_fd = fd;
}
static void l_finished(void *d, struct wp_drm_lease_v1 *l)
{
	(void)d; (void)l;
	lease_finished = 1;
}
static const struct wp_drm_lease_v1_listener l_listener = {
	.lease_fd = l_lease_fd,
	.finished = l_finished,
};

/* --- registry --- */
static void reg_global(void *d, struct wl_registry *r, uint32_t name,
		       const char *iface, uint32_t ver)
{
	(void)d; (void)ver;
	if (strcmp(iface, wp_drm_lease_device_v1_interface.name) == 0) {
		lease_device = wl_registry_bind(r, name,
						&wp_drm_lease_device_v1_interface, 1);
		wp_drm_lease_device_v1_add_listener(lease_device, &d_listener, NULL);
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

int main(int argc, char **argv)
{
	if (argc < 2) {
		fprintf(stderr, "usage: lease-runner <cmd> [args...]\n");
		return 2;
	}

	const char *output = getenv("SUNSHINE_HEADLESS_OUTPUT");
	if (!output || !*output)
		output = "HDMI-A-1";
	const char *shim = getenv("LIBSEAT_DLM_SO");
	if (!shim || !*shim) {
		fprintf(stderr, "lease-runner: LIBSEAT_DLM_SO not set\n");
		return 2;
	}
	const char *card = getenv("WLR_DRM_DEVICES");
	if (!card || !*card)
		card = "/dev/dri/card1";

	struct wl_display *dpy = wl_display_connect(NULL);
	if (!dpy) {
		fprintf(stderr, "lease-runner: cannot connect to Wayland\n");
		return 2;
	}
	struct wl_registry *reg = wl_display_get_registry(dpy);
	wl_registry_add_listener(reg, &reg_listener, NULL);
	wl_display_roundtrip(dpy); /* globals */
	if (!lease_device) {
		fprintf(stderr, "lease-runner: compositor offers no wp_drm_lease_device_v1\n");
		return 2;
	}
	wl_display_roundtrip(dpy); /* connector objects */
	wl_display_roundtrip(dpy); /* connector names */

	struct conn *target = NULL;
	for (int i = 0; i < n_conns; i++)
		if (strcmp(conns[i].name, output) == 0) {
			target = &conns[i];
			break;
		}
	if (!target) {
		fprintf(stderr, "lease-runner: connector '%s' not offered for lease\n", output);
		return 1;
	}

	struct wp_drm_lease_request_v1 *req =
		wp_drm_lease_device_v1_create_lease_request(lease_device);
	wp_drm_lease_request_v1_request_connector(req, target->obj);
	struct wp_drm_lease_v1 *lease = wp_drm_lease_request_v1_submit(req);
	wp_drm_lease_v1_add_listener(lease, &l_listener, NULL);

	while (lease_fd < 0 && !lease_finished)
		if (wl_display_dispatch(dpy) < 0)
			break;
	if (lease_fd < 0) {
		fprintf(stderr, "lease-runner: lease request failed\n");
		return 1;
	}
	fprintf(stderr, "lease-runner: leased %s (fd %d), launching %s\n",
		output, lease_fd, argv[1]);

	pid_t pid = fork();
	if (pid < 0) {
		perror("fork");
		return 1;
	}
	if (pid == 0) {
		/* If lease-runner dies for ANY reason (crash, SIGKILL, lease revoke),
		 * take gamescope down with SIGKILL — it catches SIGTERM but hangs in its
		 * DRM/lease-teardown handler, so it would otherwise orphan and keep the
		 * connector leased. Survives the gamescope wrapper's execve (not setuid). */
		prctl(PR_SET_PDEATHSIG, SIGKILL);
		int flags = fcntl(lease_fd, F_GETFD);
		if (flags >= 0)
			fcntl(lease_fd, F_SETFD, flags & ~FD_CLOEXEC);
		char fdbuf[16];
		snprintf(fdbuf, sizeof fdbuf, "%d", lease_fd);
		setenv("DLM_LEASE_FD", fdbuf, 1);
		setenv("LD_PRELOAD", shim, 1);
		setenv("WLR_DRM_DEVICES", card, 1);
		execvp(argv[1], &argv[1]);
		perror("execvp");
		_exit(127);
	}

	/* Parent holds the wayland connection (= holds the lease) until the
	 * child exits; revoke (finished) → kill the child. */
	int wstatus = 0;
	struct pollfd pfd = { .fd = wl_display_get_fd(dpy), .events = POLLIN };
	for (;;) {
		wl_display_flush(dpy);
		if (lease_finished)
			kill(pid, SIGTERM);
		int pr = poll(&pfd, 1, 200);
		if (pr > 0 && (pfd.revents & POLLIN))
			wl_display_dispatch(dpy);
		else
			wl_display_dispatch_pending(dpy);
		if (waitpid(pid, &wstatus, WNOHANG) == pid)
			break;
	}

	wp_drm_lease_v1_destroy(lease);
	wl_display_roundtrip(dpy);
	wl_display_disconnect(dpy);
	return WIFEXITED(wstatus) ? WEXITSTATUS(wstatus) : 1;
}
