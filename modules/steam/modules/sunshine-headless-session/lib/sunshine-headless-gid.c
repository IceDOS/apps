/* setgid-`input` exec shim for the headless Steam launcher / gamescope.
 *
 * Run as the payload of a NixOS security.wrapper (setgid `input`): the wrapper
 * sets egid=input, then execs THIS binary. It promotes that group to the REAL
 * gid (setregid) and execs its arguments. The real gid matters because bwrap
 * mirrors the *real* gid (not egid) into the physical-input mask sandbox — so
 * inside the sandbox the injected Steam is gid `input` and can open the
 * uaccess-stripped Sunshine pad, while the host desktop (not in `input`) cannot.
 *
 * The `input` group deliberately has NO human members, so this shim is the only
 * bridge to it — which makes it the security boundary. A normal user landing in
 * `input` (e.g. via the input-remapper module's mkGroupInjector, which would
 * otherwise add every IceDOS user to `input`) is mutually exclusive with this
 * shim: the module's icedos.nix assertion hard-fails the build in that case, so
 * the invariant is enforced, not assumed. Two layers:
 *
 *  1. Caller gate. Callers must be root or a member of a marker group baked in
 *     at build time (-DEXPECTED_GROUP=...). The module adds every IceDOS user
 *     to that group, so all users of this feature can use the bridge while a
 *     stray local account still cannot read /dev/input (keylogging). The marker
 *     group grants nothing by itself — only this wrapper turns it into gid
 *     `input`. Allowed targets can still exec children with the promoted gid,
 *     which is exactly what we rely on; that is fine because only members ever
 *     reach them, and they may already run steam/gamescope.
 *
 *  2. Target gate. Defense-in-depth against accidental misuse — e.g. a stray
 *     `sunshine-headless-gid /bin/sh` — not the security boundary; the caller
 *     gate above is that. Note only argv[1] (the exec target) is inspected:
 *     arguments after it, including gamescope's own `-- <cmd>`, are passed
 *     through untouched, so the promoted gid reaches whatever the target
 *     launches. The exec target must be a /nix/store binary whose store name is
 *     steam-<ver>[-bwrap] or gamescope-<ver> (resolved to its canonical path
 *     first, PATH-walking bare names). <ver> starts with a digit and continues
 *     with digits/letters/dot/plus/underscore/dash — the digit-first rule is
 *     what makes the shape tight: steam-run, steamcmd, gamescopereaper,
 *     gamescope-session all fail it, while a version-format drift (e.g.
 *     -unstable-2026-01-01) doesn't.
 *
 * MUST be a binary, not a shell script: bash drops the inherited setgid egid
 * unless invoked with -p, which is exactly what broke the first attempt.
 */
#include <grp.h>
#include <limits.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

#ifndef EXPECTED_GROUP
#define EXPECTED_GROUP ""
#endif

/* Current target versions, baked in by packages.nix (-DSTEAM_VERSION=... /
 * -DGAMESCOPE_VERSION=...) so the TEST_MAIN shape assertions always test the
 * live names rather than drifting literals. */
#ifndef STEAM_VERSION
#define STEAM_VERSION ""
#endif
#ifndef GAMESCOPE_VERSION
#define GAMESCOPE_VERSION ""
#endif

/* The remainder of a store name after the "<32-hex>-" prefix must be
 * steam-<ver>[-bwrap] or gamescope-<ver>, where <ver> starts with a digit and
 * continues with digits/letters/dot/plus/underscore/dash. The digit-first rule
 * is what kills the prefix traps (steam-run, steamcmd, steam-runtime,
 * gamescopereaper, gamescope-session all start with a non-digit after the
 * prefix); the lenient tail is so a version-format drift (gamescope
 * 3.17.0-unstable-2026-01-01, steam -beta1) doesn't break the gate, which is
 * defense-in-depth against accidental misuse, not a provenance check. The
 * -bwrap suffix (the buildFHSEnvBubblewrap launcher that `bin/steam` symlinks
 * to) is a steam shape only; gamescope has no such wrapper. */
static int IsVersionSuffix(const char *szRest, size_t cRest, int bwrapAllowed)
{
	size_t c = cRest;
	if (bwrapAllowed && c >= 6 && strncmp(szRest + c - 6, "-bwrap", 6) == 0)
		c -= 6;
	if (c == 0 || szRest[ 0 ] < '0' || szRest[ 0 ] > '9')
		return 0;
	for (size_t i = 1; i < c; i++) {
		const unsigned char ch = (const unsigned char)szRest[ i ];
		if (!((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'z') ||
		      (ch >= 'A' && ch <= 'Z') || ch == '.' || ch == '+' || ch == '_' || ch == '-'))
			return 0;
	}
	/* -bwrap is a steam shape only: a real gamescope store name never carries
	 * it, so reject it explicitly — the lenient tail would otherwise accept
	 * the dash. */
	if (!bwrapAllowed && c >= 6 && strncmp(szRest + c - 6, "-bwrap", 6) == 0)
		return 0;
	return 1;
}

/* Pure string check (no filesystem access) — exercised by the TEST_MAIN build
 * in packages.nix, so the boundary fails the build, not just the system. */
static int IsAllowedTarget(const char *szPath)
{
	static const char k_szStore[] = "/nix/store/";
	if (strncmp(szPath, k_szStore, sizeof(k_szStore) - 1) != 0)
		return 0;
	const char *szName = szPath + sizeof(k_szStore) - 1;

	/* Skip the "<32-hex>-" prefix. */
	if (strlen(szName) < 33 || szName[ 32 ] != '-')
		return 0;
	szName += 33;

	/* Only the first path component (the store name) decides. */
	size_t cName = strcspn(szName, "/");
	if (cName == 0)
		return 0;

	if (cName > 6 && strncmp(szName, "steam-", 6) == 0)
		return IsVersionSuffix(szName + 6, cName - 6, 1);
	if (cName > 10 && strncmp(szName, "gamescope-", 10) == 0)
		return IsVersionSuffix(szName + 10, cName - 10, 0);
	return 0;
}

#ifndef TEST_MAIN
/* Resolve argv[1] to a canonical path, walking PATH for bare names like
 * execvp does. Returns 0 (and leaves szOut untouched) when nothing canonical
 * and executable resolves. */
static int ResolveTarget(const char *szName, char *szOut)
{
	if (strchr(szName, '/') != NULL)
		return realpath(szName, szOut) != NULL;

	const char *szPath = getenv("PATH");
	if (szPath == NULL || *szPath == '\0')
		szPath = "/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin";

	char szPathCopy[ 8192 ];
	size_t cPath = strlen(szPath);
	if (cPath >= sizeof(szPathCopy))
		cPath = sizeof(szPathCopy) - 1;
	memcpy(szPathCopy, szPath, cPath);
	szPathCopy[ cPath ] = '\0';

	char *pszSave = NULL;
	char szCandidate[ PATH_MAX ];
	for (char *pszDir = strtok_r(szPathCopy, ":", &pszSave); pszDir != NULL;
	     pszDir = strtok_r(NULL, ":", &pszSave)) {
		if (*pszDir == '\0')
			pszDir = ".";
		if (snprintf(szCandidate, sizeof(szCandidate), "%s/%s", pszDir, szName) <
		        (int)sizeof(szCandidate) &&
		    access(szCandidate, X_OK) == 0 && realpath(szCandidate, szOut) != NULL)
			return 1;
	}
	return 0;
}

static int UserAllowed(void)
{
	if (getuid() == 0)
		return 1;
	if (EXPECTED_GROUP[ 0 ] == '\0')
		return 0;
	const struct passwd *pw = getpwuid(getuid());
	if (pw == NULL)
		return 0;
	const struct group *gr = getgrnam(EXPECTED_GROUP);
	if (gr == NULL)
		return 0;
	if (pw->pw_gid == gr->gr_gid)
		return 1;

	gid_t groups[ NGROUPS_MAX + 1 ];
	int n = (int)(NGROUPS_MAX + 1);
	if (getgrouplist(pw->pw_name, pw->pw_gid, groups, &n) < 0)
		return 0;
	for (int i = 0; i < n; i++) {
		if (groups[ i ] == gr->gr_gid)
			return 1;
	}
	return 0;
}
#endif /* TEST_MAIN */

#ifdef TEST_MAIN
#include <assert.h>
/* With no args, run the built-in shape assertions. With args, demand each one
 * passes the gate: a leading '/' is treated as a path to resolve and check
 * (like the real gate does); anything else is a bare store-name shape (e.g.
 * "steam-1.0.0.87") checked against the name gate without touching the
 * filesystem. The derivation in packages.nix runs this against the module's
 * actual ${gamescopePkg}/bin/gamescope and steam-${pkgs.steam.version}, so a
 * real target drifting out of the shape fails the build. */
int main(int argc, char **argv)
{
	/* Caller-gate sanity: UserAllowed() is compiled out under TEST_MAIN, so the
	 * build would not notice a dropped -DEXPECTED_GROUP=... flag (which would
	 * silently fail-closed for every caller). Assert the marker group was baked
	 * in — plus that it isn't `input` itself, which would make the marker group
	 * gate a no-op. */
	assert(EXPECTED_GROUP[ 0 ] != '\0');
	assert(strcmp(EXPECTED_GROUP, "input") != 0);

	if (argc > 1) {
		static const char k_szStore[] = "/nix/store/";
		for (int i = 1; i < argc; i++) {
			const char *szArg = argv[ i ];
			const char *szShape;
			char szResolved[ PATH_MAX ];
			char szBare[ 256 ];
			if (szArg[ 0 ] == '/') {
				if (!realpath(szArg, szResolved)) {
					fprintf(stderr, "TEST: cannot resolve '%s'\n", szArg);
					return 1;
				}
				szShape = szResolved;
			} else {
				if (snprintf(szBare, sizeof(szBare),
				             "%saaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-%s",
				             k_szStore, szArg) >= (int)sizeof(szBare)) {
					fprintf(stderr, "TEST: arg too long: '%s'\n", szArg);
					return 1;
				}
				szShape = szBare;
			}
			if (!IsAllowedTarget(szShape)) {
				fprintf(stderr, "TEST: gate rejected '%s' (expanded to '%s')\n",
				        szArg, szShape);
				return 1;
			}
		}
		return 0;
	}

	/* Genuine targets pass. The current versions are baked in by packages.nix
	 * (-DSTEAM_VERSION/-DGAMESCOPE_VERSION), so a nixpkgs bump re-tests the
	 * live names instead of drifting like a literal would. */
	assert(IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-steam-" STEAM_VERSION "/bin/steam"));
	assert(IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-steam-" STEAM_VERSION "-bwrap"));
	assert(IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-gamescope-" GAMESCOPE_VERSION "/bin/gamescope"));

	/* Version-string drift survives: a digit-first version with a lenient
	 * tail is still a steam/gamescope shape (beta / -unstable-<date>). */
	assert(IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-steam-1.0.0.87-beta1/bin/steam"));
	assert(IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-steam-1.0.0.87-unstable-2026-01-01/bin/steam"));
	assert(IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-gamescope-3.17.0-unstable-2026-01-01/bin/gamescope"));

	/* Name-prefix traps fail. The version is a placeholder — these fail on the
	 * prefix, so its value is irrelevant. */
	assert(!IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-steam-run-1/bin/steam-run"));
	assert(!IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-steamcmd-1/bin/steamcmd"));
	assert(!IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-steam-runtime-1/bin/steam-runtime"));
	assert(!IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-gamescopereaper-1/bin/gamescopereaper"));
	assert(!IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-gamescope-session-1/bin/gamescope-session"));

	/* -bwrap is a steam shape; gamescope never gets it. */
	assert(!IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-gamescope-" GAMESCOPE_VERSION "-bwrap"));

	/* Outside the store fails. */
	assert(!IsAllowedTarget("/bin/sh"));
	assert(!IsAllowedTarget("/nix/store/foo"));

	/* Malformed store paths fail. */
	assert(!IsAllowedTarget("/nix/store/steam-" STEAM_VERSION "/bin/steam"));
	assert(!IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-steam"));
	assert(!IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-gamescope"));
	return 0;
}
#else
int main(int argc, char **argv)
{
	if (argc < 2) {
		fprintf(stderr, "usage: %s command [args...]\n", argv[0]);
		return 2;
	}

	if (!UserAllowed()) {
		fprintf(stderr,
		        "%s: refusing to exec '%s': only members of the '%s' group (and root) may use the setgid-input bridge\n",
		        argv[ 0 ], argv[ 1 ], EXPECTED_GROUP);
		return 2;
	}

	char szResolved[ PATH_MAX ];
	if (!ResolveTarget(argv[ 1 ], szResolved) ||
	    !IsAllowedTarget(szResolved)) {
		fprintf(stderr,
		        "%s: refusing to exec '%s': target name is not a /nix/store steam-*/gamescope-* binary\n",
		        argv[ 0 ], argv[ 1 ]);
		return 2;
	}

	gid_t g = getegid();
	if (setregid(g, g) != 0) {
		perror("setregid");
		return 1;
	}

	execv(szResolved, &argv[ 1 ]);
	perror("execv");
	return 127;
}
#endif
