/*
 * icedos: no-op shim for GDK's deprecated thread-lock API, installed as
 * libgdk-3.so.0 and placed first in LD_LIBRARY_PATH.
 *
 * The bundled JDK arms the GDK lock (gtk3_interface.c calls gdk_threads_init
 * before gtk_init_check) and the app's GTK webview parks while holding it, so
 * AWT's URL open (gdk_threads_enter) deadlocks and KWin kills the app. Keeping
 * the lock unarmed makes enter/leave no-ops, so links open normally.
 *
 * A copy of the real libgdk-3.so.0 (renamed libgdk3-real.so.0, see nightly.nix)
 * is linked in as a dependency, so every other GDK symbol still resolves.
 */

void gdk_threads_init(void) {}
void gdk_threads_enter(void) {}
void gdk_threads_leave(void) {}
void gdk_threads_lock(void) {}
void gdk_threads_unlock(void) {}
void gdk_threads_set_lock_default(void) {}
void gdk_threads_set_lock_functions(void (*enter)(void), void (*leave)(void))
{
    (void)enter;
    (void)leave;
}
