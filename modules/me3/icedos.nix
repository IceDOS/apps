{ icedosLib, lib, ... }:

{
  options.icedos.applications.me3.games =
    let
      inherit (lib)
        attrValues
        genAttrs
        head
        mapAttrs
        mkOption
        readFile
        ;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.me3) games;

      inherit (icedosLib) mkSubmoduleAttrsOption mkSubmoduleListOption;

      sampleGame = head (attrValues games);
      sampleProfile = head sampleGame.profiles;

      # Each TOML key on the sample entry becomes an untyped option whose default
      # mirrors the parsed stub — the zsh-module pattern at apps/modules/zsh/icedos.nix:4-11,
      # lifted to a whole attrset so we don't have to enumerate keys by hand.
      optionsFromAttrs = attrs: mapAttrs (_: v: mkOption { default = v; }) attrs;

      # Nullable per-profile overrides that fall through to the game's defaults.
      overridableScalars = [
        "profileVersion"
        "savefile"
        "start_online"
        "disable_arxan"
        "patch_mem"
      ];
      nullOverrides = genAttrs overridableScalars (_: mkOption { default = null; });
    in
    mkSubmoduleAttrsOption { default = games; } (
      (optionsFromAttrs (removeAttrs sampleGame [ "profiles" ]))
      // {
        profiles = mkSubmoduleListOption { default = [ ]; } (
          (optionsFromAttrs sampleProfile) // nullOverrides
        );
      }
    );

  outputs.nixosModules =
    { ... }:

    [
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:
        {
          environment.systemPackages = with pkgs; [ me3 ];

          home-manager.sharedModules =
            let
              inherit (icedosLib) abortIf;

              inherit (lib)
                attrNames
                concatMap
                concatMapStringsSep
                concatStringsSep
                escape
                filter
                findFirst
                isAttrs
                isBool
                isInt
                isList
                isString
                length
                listToAttrs
                mapAttrsToList
                optionalString
                boolToString
                unique
                ;

              inherit (config.icedos) applications;
              userGames = removeAttrs applications.me3.games [ "__sample" ];

              toTOMLValue =
                v:
                if isString v then
                  "\"${escape [ "\"" "\\" ] v}\""
                else if isBool v then
                  boolToString v
                else if isInt v then
                  toString v
                else if isList v then
                  "[ ${concatMapStringsSep ", " toTOMLValue v} ]"
                else if isAttrs v then
                  "{ ${concatStringsSep ", " (mapAttrsToList (k: val: "${k} = ${toTOMLValue val}") v)} }"
                else
                  throw "me3 renderer: unsupported TOML value ${toString v}";

              renderEntry = attrs: concatStringsSep "\n" (mapAttrsToList (k: v: "${k} = ${toTOMLValue v}") attrs);

              renderTable =
                name: entries: concatMapStringsSep "\n\n" (e: "[[${name}]]\n${renderEntry e}") entries;

              pick = override: default: if override == null then default else override;

              allProfiles = concatMap (
                gameName:
                let
                  game = userGames.${gameName};
                in
                map (p: {
                  inherit gameName game p;
                }) game.profiles
              ) (attrNames userGames);

              profileNames = map (x: x.p.name) allProfiles;

              renderProfile =
                gameName: game: p:
                let
                  lookupProfile =
                    depName:
                    let
                      hit = findFirst (pr: pr.name == depName) null game.profiles;
                    in
                    if hit == null then
                      throw ''me3 profile "${p.name}" (game "${gameName}"): unknown dependency "${depName}"''
                    else
                      hit;

                  resolveRefs =
                    seen: pr:
                    let
                      cycleFree = abortIf (builtins.elem pr.name seen) ''me3 profile dependency cycle in game "${gameName}": ${
                        concatStringsSep " -> " (seen ++ [ pr.name ])
                      }'';
                      seen' = seen ++ [ pr.name ];
                      depsResolved = map (d: resolveRefs seen' (lookupProfile d)) pr.dependencies;
                      merged = {
                        natives = unique ((concatMap (r: r.natives) depsResolved) ++ pr.natives);
                        packages = unique ((concatMap (r: r.packages) depsResolved) ++ pr.packages);
                      };
                    in
                    if cycleFree then merged else merged;

                  refs = resolveRefs [ ] p;

                  lookupNative =
                    ref:
                    let
                      hit = findFirst (n: n.name == ref) null game.natives;
                    in
                    if hit == null then
                      throw ''me3 profile "${p.name}" (game "${gameName}"): no native named "${ref}"''
                    else
                      removeAttrs hit [ "name" ];

                  lookupPackage =
                    ref:
                    let
                      hit = findFirst (pkg: pkg.id == ref) null game.packages;
                    in
                    if hit == null then
                      throw ''me3 profile "${p.name}" (game "${gameName}"): no package id "${ref}"''
                    else
                      hit;

                  natives = map lookupNative refs.natives;
                  packages = map lookupPackage refs.packages;

                  supports = if game.supports == [ ] then [ { game = gameName; } ] else game.supports;

                  profileVersion = pick p.profileVersion game.profileVersion;
                  savefile = pick p.savefile game.savefile;
                  start_online = pick p.start_online game.start_online;
                  disable_arxan = pick p.disable_arxan game.disable_arxan;
                  patch_mem = pick p.patch_mem game.patch_mem;

                  scalarLines = filter (s: s != "") [
                    (optionalString (profileVersion != "") ''profileVersion = "${profileVersion}"'')
                    (optionalString (savefile != "") ''savefile = "${savefile}"'')
                    (optionalString start_online "start_online = true")
                    (optionalString disable_arxan "disable_arxan = true")
                    (optionalString patch_mem "patch_mem = true")
                  ];
                in
                concatStringsSep "\n\n" (
                  filter (s: s != "") [
                    (concatStringsSep "\n" scalarLines)
                    (renderTable "supports" supports)
                    (if natives != [ ] then renderTable "natives" natives else "")
                    (if packages != [ ] then renderTable "packages" packages else "")
                    p.config
                  ]
                );

              mkHomeFile =
                {
                  gameName,
                  game,
                  p,
                }:
                let
                  duplicateCount = length (filter (n: n == p.name) profileNames);
                  entry = {
                    name = ".config/me3/profiles/${p.name}.me3";
                    value.text = ''
                      ${renderProfile gameName game p}
                    '';
                  };
                in
                if
                  (abortIf (duplicateCount > 1)
                    ''${toString duplicateCount} me3 profiles named "${p.name}" detected - profile names have to be unique!''
                  )
                then
                  entry
                else
                  entry;
            in
            [
              { home.file = listToAttrs (map mkHomeFile allProfiles); }
            ];
        }
      )
    ];

  meta.name = "me3";
}
