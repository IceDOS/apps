#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>

// AWT's GTK loader forces GDK_BACKEND=x11, which drops Nucleus Tao to XWayland where
// native views (the plugin login webview) render behind the GL surface.
int putenv(char *string)
{
    static int (*real_putenv)(char *);
    if (!real_putenv)
        real_putenv = dlsym(RTLD_NEXT, "putenv");
    if (strcmp(string, "GDK_BACKEND=x11") == 0 && getenv("WAYLAND_DISPLAY"))
        return 0;
    return real_putenv(string);
}
