// Make gamescope reconsider game windows left out of focus: a CreateNotify re-runs focus, and
// synthetic ConfigureNotifies refresh its cached geometry and override-redirect, which can go stale.
#include <X11/Xlib.h>
#include <stdio.h>
#include <time.h>

int main(void) {
  Display *dpy = XOpenDisplay(NULL);
  if (!dpy) {
    fprintf(stderr, "sunshine-headless-xnudge: cannot open display\n");
    return 1;
  }

  int screen = DefaultScreen(dpy);
  Window root = RootWindow(dpy, screen);
  Window win = XCreateSimpleWindow(dpy, root, 0, 0, 1, 1, 0,
                                   BlackPixel(dpy, screen),
                                   BlackPixel(dpy, screen));
  XSync(dpy, False);

  // gamescope reads the window's attributes on CreateNotify; destroy it too early and
  // that read fails, so it drops the window without redetermining focus.
  nanosleep(&(struct timespec){ .tv_sec = 0, .tv_nsec = 250 * 1000 * 1000 }, NULL);

  XDestroyWindow(dpy, win);
  XSync(dpy, False);

  // Only root's SubstructureNotify listeners (gamescope) see these; the windows do not.
  Window root_ret, parent_ret, *children = NULL;
  unsigned int n = 0;
  if (XQueryTree(dpy, root, &root_ret, &parent_ret, &children, &n)) {
    // XQueryTree lists bottom to top, so the sibling below children[i] is children[i - 1].
    for (unsigned int i = 0; i < n; i++) {
      XWindowAttributes a;
      if (!XGetWindowAttributes(dpy, children[i], &a) || a.map_state != IsViewable)
        continue;
      XEvent ev = { 0 };
      ev.xconfigure.type = ConfigureNotify;
      ev.xconfigure.event = root;
      ev.xconfigure.window = children[i];
      ev.xconfigure.x = a.x;
      ev.xconfigure.y = a.y;
      ev.xconfigure.width = a.width;
      ev.xconfigure.height = a.height;
      ev.xconfigure.border_width = a.border_width;
      ev.xconfigure.above = i > 0 ? children[i - 1] : None;
      ev.xconfigure.override_redirect = a.override_redirect;
      XSendEvent(dpy, root, False, SubstructureNotifyMask, &ev);
    }
    if (children)
      XFree(children);
  }

  XSync(dpy, False);
  XCloseDisplay(dpy);
  return 0;
}
