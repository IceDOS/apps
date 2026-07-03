/* libseat-dlm: LD_PRELOAD shim replacing libseat so an unmodified wlroots
 * compositor (gamescope --backend drm) runs on a DRM lease instead of taking
 * DRM master via logind.
 *
 * The lease fd is acquired by `lease-runner` (a wp_drm_lease_v1 client) and
 * passed to the child via the env var DLM_LEASE_FD. This shim returns that fd
 * for DRM-node opens and the real device for everything else (input).
 */
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <sys/eventfd.h>
#include <sys/ioctl.h>
#include <unistd.h>

/* libseat ABI (opaque pointers + the seat listener struct). */
struct libseat;

struct libseat_seat_listener {
	void (*enable_seat)(struct libseat *seat, void *data);
	void (*disable_seat)(struct libseat *seat, void *data);
};

enum libseat_log_level {
	LIBSEAT_LOG_LEVEL_SILENT = 0,
	LIBSEAT_LOG_LEVEL_ERROR = 1,
	LIBSEAT_LOG_LEVEL_INFO = 2,
	LIBSEAT_LOG_LEVEL_DEBUG = 3,
	LIBSEAT_LOG_LEVEL_LAST,
};

struct libseat_dlm {
	struct libseat_seat_listener listener;
	void *user_data;
	int event_fd;
};

static struct libseat_dlm state = { .event_fd = -1 };

static int dlm_lease_fd(void)
{
	const char *s = getenv("DLM_LEASE_FD");
	if (!s || !*s)
		return -1;
	return (int)strtol(s, NULL, 10);
}

struct libseat *libseat_open_seat(const struct libseat_seat_listener *listener,
				  void *data)
{
	state.listener = *listener;
	state.user_data = data;

	state.event_fd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
	if (state.event_fd < 0)
		return NULL;

	/* Signal the seat active immediately (matches the proven sway shim:
	 * wlroots' session loops on dispatch until active, so synchronous enable
	 * just satisfies it on the first check). */
	if (state.listener.enable_seat)
		state.listener.enable_seat((struct libseat *)&state, data);

	return (struct libseat *)&state;
}

const char *libseat_seat_name(struct libseat *seat)
{
	(void)seat;
	return "seat0";
}

int libseat_open_device(struct libseat *seat, const char *path, int *fd)
{
	(void)seat;

	int out;
	if (strncmp(path, "/dev/dri/", 9) == 0) {
		int lease = dlm_lease_fd();
		if (lease < 0) {
			errno = EINVAL;
			return -1;
		}
		out = fcntl(lease, F_DUPFD_CLOEXEC, 0);
	} else if (getenv("DLM_NO_INPUT")) {
		/* Safety for headless smoke tests: deny input devices so gamescope
		 * can't grab the keyboard/mouse off the live desktop. */
		errno = EACCES;
		return -1;
	} else {
		/* Input and other devices: open for real (the input-passthrough
		 * fix — the original shim returned the lease fd here too). */
		out = open(path, O_RDWR | O_NONBLOCK | O_CLOEXEC);
	}

	if (out < 0)
		return -1;

	/* Optional input allowlist: when DLM_INPUT_ALLOW is set, only expose
	 * /dev/input devices whose evdev name contains it (e.g. "Sunshine" virtual
	 * pads). Keeps a leased gamescope from grabbing the real desktop
	 * keyboard/mouse while the host session is in use. */
	const char *allow = getenv("DLM_INPUT_ALLOW");
	if (allow && *allow && strncmp(path, "/dev/input/", 11) == 0) {
		char name[256] = { 0 };
		if (ioctl(out, EVIOCGNAME(sizeof name), name) < 0
		    || strstr(name, allow) == NULL) {
			close(out);
			errno = EACCES;
			return -1;
		}
	}

	*fd = out;
	return out; /* device_id == fd, so close_device can close it directly */
}

int libseat_close_device(struct libseat *seat, int device_id)
{
	(void)seat;
	if (device_id >= 0)
		close(device_id);
	return 0;
}

int libseat_get_fd(struct libseat *seat)
{
	(void)seat;
	return state.event_fd;
}

int libseat_dispatch(struct libseat *seat, int timeout)
{
	(void)seat;
	(void)timeout;
	return 0;
}

int libseat_disable_seat(struct libseat *seat)
{
	(void)seat;
	return 0;
}

int libseat_switch_session(struct libseat *seat, int session)
{
	(void)seat;
	(void)session;
	errno = ENOSYS;
	return -1;
}

void libseat_close_seat(struct libseat *seat)
{
	(void)seat;
	if (state.event_fd >= 0) {
		close(state.event_fd);
		state.event_fd = -1;
	}
}

void libseat_set_log_handler(void (*handler)(enum libseat_log_level,
					     const char *, va_list))
{
	(void)handler;
}

void libseat_set_log_level(enum libseat_log_level level)
{
	(void)level;
}
