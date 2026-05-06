{ icedosLib, lib, ... }:

{
  options.icedos.applications.me3.games =
    let
      inherit (lib)
        attrValues
        head
        isAttrs
        isBool
        isInt
        isList
        isString
        mapAttrs
        readFile
        types
        ;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.me3) games;
      inherit (icedosLib)
        mkAttrsOption
        mkBoolOption
        mkListOption
        mkNullableOption
        mkNumberOption
        mkNumberListOption
        mkStrListOption
        mkStrOption
        mkSubmoduleAttrsOption
        mkSubmoduleListOption
        ;

      sampleGame = head (attrValues games);
      sampleProfile = head sampleGame.profiles;

      # Auto-derive the most precise wrapper for each TOML-shaped value so the
      # generated submodule fields stay typed without enumerating each key by
      # hand. Empty lists fall back to `listOf anything` because the sample TOML
      # has no element to inspect, but real entries may differ in shape (e.g.
      # game-level natives are attrs while profile-level natives are refs).
      typedOptionFor =
        v:
        if isBool v then
          mkBoolOption { default = v; }
        else if isInt v then
          mkNumberOption { default = v; }
        else if isString v then
          mkStrOption { default = v; }
        else if isList v then
          if v == [ ] then
            mkListOption { default = v; } types.anything
          else
            let
              head' = head v;
            in
            if isString head' then
              mkStrListOption { default = v; }
            else if isInt head' then
              mkNumberListOption { default = v; }
            else
              mkListOption { default = v; } types.attrs
        else if isAttrs v then
          mkAttrsOption { default = v; }
        else
          mkAttrsOption { default = v; };

      optionsFromAttrs = attrs: mapAttrs (_: typedOptionFor) attrs;

      # Nullable per-profile overrides that fall through to the game's defaults.
      overridableScalarTypes = {
        profileVersion = types.str;
        savefile = types.str;
        start_online = types.bool;
        disable_arxan = types.bool;
        patch_mem = types.bool;
      };

      nullOverrides = mapAttrs (_: t: mkNullableOption { default = null; } t) overridableScalarTypes;
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
              inherit (icedosLib) validate;

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
                  validate.abort {
                    when = true;
                    path = "icedos.applications.me3.renderer";
                    msg = "unsupported TOML value '${toString v}'";
                  };

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
                      validate.abort {
                        when = true;
                        path = ''icedos.applications.me3.games."${gameName}".profiles."${p.name}".dependencies'';
                        msg = ''unknown dependency "${depName}"'';
                      }
                    else
                      hit;

                  resolveRefs =
                    seen: pr:
                    let
                      cycleFree = validate.abort {
                        when = builtins.elem pr.name seen;
                        path = ''icedos.applications.me3.games."${gameName}".profiles'';
                        msg = "dependency cycle: ${concatStringsSep " -> " (seen ++ [ pr.name ])}";
                      };
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
                      validate.abort {
                        when = true;
                        path = ''icedos.applications.me3.games."${gameName}".profiles."${p.name}".natives'';
                        msg = ''no native named "${ref}"'';
                      }
                    else
                      removeAttrs hit [ "name" ];

                  lookupPackage =
                    ref:
                    let
                      hit = findFirst (pkg: pkg.id == ref) null game.packages;
                    in
                    if hit == null then
                      validate.abort {
                        when = true;
                        path = ''icedos.applications.me3.games."${gameName}".profiles."${p.name}".packages'';
                        msg = ''no package id "${ref}"'';
                      }
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
                    name = "me3/profiles/${p.name}.me3";
                    value.text = ''
                      ${renderProfile gameName game p}
                    '';
                  };
                  unique' = validate.abort {
                    when = duplicateCount > 1;
                    path = ''icedos.applications.me3.profiles."${p.name}"'';
                    msg = ''${toString duplicateCount} profiles named "${p.name}" detected - profile names must be unique'';
                  };
                in
                if unique' then entry else entry;
            in
            [
              { xdg.configFile = listToAttrs (map mkHomeFile allProfiles); }
            ];
        }
      )
    ];

  meta.name = "me3";
}
