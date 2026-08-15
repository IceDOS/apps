/* Exec shim for the headless session — ONE binary, two wrapper configs: mode A (setgid `input`, gamescope/injected Steam) promotes egid to the real gid so bwrap mirrors `input` into the sandbox; mode B (setuid root, the daemon only) keeps the caller's gids and adds `input` supplementary — gid=input would fail the portal's /proc/<pid>/root ptrace check (503).
 * `input` has NO human members, so the shim is the security boundary: caller gate (root or the baked-in marker group) + target gate (steam-<ver>[-bwrap]/gamescope-<ver>/sunshine-<ver> shapes). MUST be a binary: bash drops the inherited setgid egid. */
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

/* Target versions baked in by packages.nix (-DSTEAM_VERSION/-DGAMESCOPE_VERSION/
 * -DSUNSHINE_VERSION) so TEST_MAIN asserts live names, not drifting literals. */
#ifndef STEAM_VERSION
#define STEAM_VERSION ""
#endif
#ifndef GAMESCOPE_VERSION
#define GAMESCOPE_VERSION ""
#endif
#ifndef SUNSHINE_VERSION
#define SUNSHINE_VERSION ""
#endif
/* The group whose access the shim grants (mode B adds it as supplementary;
 * mode A's wrapper bit is baked into the wrapper config, group "input"). */
#ifndef INPUT_GROUP
#define INPUT_GROUP "input"
#endif

/* Store-name shape after the "<32-hex>-" prefix: steam-<ver>[-bwrap] / gamescope-<ver> / sunshine-<ver> (per mode), <ver> digit-first then lenient — digit-first kills the prefix traps (steam-run, steamcmd, gamescopereaper, gamescope-session, sunshine-headless); defense-in-depth, not provenance.
 * -bwrap (the buildFHSEnvBubblewrap launcher `bin/steam` symlinks to) is a steam shape only. */
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
	/* -bwrap is a steam shape only: reject it for gamescope/sunshine explicitly
	 * (the lenient tail would otherwise accept the dash). */
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

/* Mode B (root/daemon) accepts sunshine-<ver> only. Same store-path shape
 * parsing as IsAllowedTarget. */
static int IsSunshineTarget(const char *szPath)
{
	static const char k_szStore[] = "/nix/store/";
	if (strncmp(szPath, k_szStore, sizeof(k_szStore) - 1) != 0)
		return 0;
	const char *szName = szPath + sizeof(k_szStore) - 1;

	if (strlen(szName) < 33 || szName[ 32 ] != '-')
		return 0;
	szName += 33;

	size_t cName = strcspn(szName, "/");
	if (cName == 0)
		return 0;

	if (cName > 9 && strncmp(szName, "sunshine-", 9) == 0)
		return IsVersionSuffix(szName + 9, cName - 9, 0);
	return 0;
}

#ifndef TEST_MAIN
/* Resolve argv[1] to a canonical path, walking PATH for bare names like execvp does.
 * Returns 0 (szOut untouched) when nothing canonical and executable resolves. */
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
/* No args: run the built-in shape assertions; with args each must pass the gate — '/' = resolve
 * like the real gate, else a bare store-name shape. packages.nix tests the real store paths. */
int main(int argc, char **argv)
{
	/* Caller-gate sanity (UserAllowed is compiled out under TEST_MAIN): assert the marker
	 * group was baked in — and isn't `input` itself, which would no-op the gate. */
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
			if (!IsAllowedTarget(szShape) && !IsSunshineTarget(szShape)) {
				fprintf(stderr, "TEST: gate rejected '%s' (expanded to '%s')\n",
				        szArg, szShape);
				return 1;
			}
		}
		return 0;
	}

	/* Genuine targets pass — versions are baked in by packages.nix, so a nixpkgs bump
	 * re-tests live names instead of drifting literals. */
	assert(IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-steam-" STEAM_VERSION "/bin/steam"));
	assert(IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-steam-" STEAM_VERSION "-bwrap"));
	assert(IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-gamescope-" GAMESCOPE_VERSION "/bin/gamescope"));
	assert(IsSunshineTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-sunshine-" SUNSHINE_VERSION "/bin/sunshine"));
	assert(!IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-sunshine-" SUNSHINE_VERSION "/bin/sunshine"));

	/* Grammar fixtures — deliberately NOT the live versions (tested above):
	 * a digit-first version with a lenient tail is still a valid shape. */
	assert(IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-steam-1.0.0.87-beta1/bin/steam"));
	assert(IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-steam-1.0.0.87-unstable-2026-01-01/bin/steam"));
	assert(IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-gamescope-3.17.0-unstable-2026-01-01/bin/gamescope"));
	assert(IsSunshineTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-sunshine-2026.516.143833-beta1/bin/sunshine"));

	/* Name-prefix traps fail. The version is a placeholder — these fail on the
	 * prefix, so its value is irrelevant. */
	assert(!IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-steam-run-1/bin/steam-run"));
	assert(!IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-steamcmd-1/bin/steamcmd"));
	assert(!IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-steam-runtime-1/bin/steam-runtime"));
	assert(!IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-gamescopereaper-1/bin/gamescopereaper"));
	assert(!IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-gamescope-session-1/bin/gamescope-session"));
	assert(!IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-sunshine-headless-1/bin/sunshine"));
	assert(!IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-sunshine-portal-1/bin/sunshine"));
	assert(!IsSunshineTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-sunshine-headless-1/bin/sunshine"));
	assert(!IsSunshineTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-sunshine-portal-1/bin/sunshine"));
	assert(!IsSunshineTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-steam-" STEAM_VERSION "/bin/steam"));
	assert(!IsSunshineTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-gamescope-" GAMESCOPE_VERSION "/bin/gamescope"));

	assert(!IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-gamescope-" GAMESCOPE_VERSION "-bwrap"));
	assert(!IsAllowedTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-sunshine-" SUNSHINE_VERSION "-bwrap"));
	assert(!IsSunshineTarget("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-sunshine-" SUNSHINE_VERSION "-bwrap"));

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
		        "%s: refusing to exec '%s': only members of the '%s' group (and root) may use the input bridge\n",
		        argv[ 0 ], argv[ 1 ], EXPECTED_GROUP);
		return 2;
	}

	char szResolved[ PATH_MAX ];
	if (!ResolveTarget(argv[ 1 ], szResolved)) {
		fprintf(stderr,
		        "%s: refusing to exec '%s': target cannot be resolved\n",
		        argv[ 0 ], argv[ 1 ]);
		return 2;
	}

	if (geteuid() == 0) {
		/* Mode B — ROOT (the headless DAEMON's wrapper, setuid root): keeps the caller's gids and adds `input` supplementary — gid=input would deny /proc/<pid>/root (503).
		 * Bounded setuid window: gates only, then drop to the caller's uid before exec. */
		if (!IsSunshineTarget(szResolved)) {
			fprintf(stderr,
			        "%s: refusing to exec '%s': target name is not a /nix/store sunshine-* binary\n",
			        argv[ 0 ], argv[ 1 ]);
			return 2;
		}
		const struct group *gr = getgrnam(INPUT_GROUP);
		if (gr == NULL) {
			fprintf(stderr, "%s: refusing to exec '%s': unknown group '%s'\n",
			        argv[ 0 ], argv[ 1 ], INPUT_GROUP);
			return 1;
		}
		gid_t groups[ NGROUPS_MAX + 1 ];
		int ng = getgroups(NGROUPS_MAX + 1, groups);
		if (ng < 0)
			ng = 0;
		int found = 0;
		for (int i = 0; i < ng; i++) {
			if (groups[ i ] == gr->gr_gid) {
				found = 1;
				break;
			}
		}
		if (!found)
			groups[ ng++ ] = gr->gr_gid;
		if (setgroups(ng, groups) != 0) {
			perror("setgroups");
			return 1;
		}
		/* Drop root before exec (still privileged here, so setgid/setuid reset the real, effective
		 * AND saved ids): the daemon must be an ordinary, capability-less user process. */
		gid_t g = getgid();
		uid_t u = getuid();
		if (setgid(g) != 0) {
			perror("setgid");
			return 1;
		}
		if (setuid(u) != 0) {
			perror("setuid");
			return 1;
		}
		execv(szResolved, &argv[ 1 ]);
		perror("execv");
		return 127;
	}

	if (getegid() != getgid()) {
		/* Mode A — SETGID-INPUT (gamescope / injected Steam): promote the wrapper group to the real
		 * gid so bwrap mirrors `input` into the sandbox; these never talk to the portal. */
		if (!IsAllowedTarget(szResolved)) {
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

	fprintf(stderr,
	        "%s: refusing to exec '%s': wrapper misconfigured (expected setuid root or setgid %s)\n",
	        argv[ 0 ], argv[ 1 ], INPUT_GROUP);
	return 2;
}
#endif
