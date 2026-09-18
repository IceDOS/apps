// Create and destroy one never-mapped window on $DISPLAY, so nothing reaches the stream.
// Only a CreateNotify makes gamescope reconsider a game window it left out of its focus
// candidates; rewriting STEAM_GAME or GAMESCOPECTRL_BASELAYER_APPID does not.
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
  Window win = XCreateSimpleWindow(dpy, RootWindow(dpy, screen), 0, 0, 1, 1, 0,
                                   BlackPixel(dpy, screen),
                                   BlackPixel(dpy, screen));
  XSync(dpy, False);

  // gamescope reads the window's attributes on CreateNotify; destroy it too early and
  // that read fails, so it drops the window without redetermining focus.
  nanosleep(&(struct timespec){ .tv_sec = 0, .tv_nsec = 250 * 1000 * 1000 }, NULL);

  XDestroyWindow(dpy, win);
  XSync(dpy, False);
  XCloseDisplay(dpy);
  return 0;
}
