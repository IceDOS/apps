/* setgid-`input` exec shim for the headless Steam launcher.
 *
 * Run as the payload of a NixOS security.wrapper (setgid `input`): the wrapper
 * sets egid=input, then execs THIS binary. It promotes that group to the REAL
 * gid (setregid) and execs its arguments. The real gid matters because bwrap
 * mirrors the *real* gid (not egid) into the physical-input mask sandbox — so
 * inside the sandbox the injected Steam is gid `input` and can open the
 * uaccess-stripped Sunshine pad, while the host desktop (not in `input`) cannot.
 *
 * MUST be a binary, not a shell script: bash drops the inherited setgid egid
 * unless invoked with -p, which is exactly what broke the first attempt.
 */
#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	if (argc < 2) {
		fprintf(stderr, "usage: %s command [args...]\n", argv[0]);
		return 2;
	}

	gid_t g = getegid();
	if (setregid(g, g) != 0) {
		perror("setregid");
		return 1;
	}

	execvp(argv[1], &argv[1]);
	perror("execvp");
	return 127;
}
