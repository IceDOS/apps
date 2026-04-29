{ icedosLib, lib, ... }:

{
  options.icedos.applications.samba =
    let
      inherit (lib)
        head
        mkOption
        readFile
        types
        ;
      inherit (icedosLib)
        mkBoolOption
        mkNumberOption
        mkStrListOption
        mkStrOption
        mkSubmoduleListOption
        ;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.samba)
        workgroup
        serverString
        serverRole
        minProtocol
        mapToGuest
        guestAccount
        useSendfile
        aioReadSize
        aioWriteSize
        socketOptions
        logFile
        maxLogSize
        openFirewall
        enableWsdd
        enableNmbd
        ;

      inherit ((fromTOML (readFile ./shares.toml)).icedos.applications.samba)
        shares
        ;
    in
    {
      workgroup = mkStrOption { default = workgroup; };
      serverString = mkStrOption { default = serverString; };
      serverRole = mkStrOption { default = serverRole; };
      minProtocol = mkStrOption { default = minProtocol; };
      mapToGuest = mkStrOption { default = mapToGuest; };
      guestAccount = mkStrOption { default = guestAccount; };
      useSendfile = mkBoolOption { default = useSendfile; };
      aioReadSize = mkNumberOption { default = aioReadSize; };
      aioWriteSize = mkNumberOption { default = aioWriteSize; };
      socketOptions = mkStrOption { default = socketOptions; };
      logFile = mkStrOption { default = logFile; };
      maxLogSize = mkNumberOption { default = maxLogSize; };
      openFirewall = mkBoolOption { default = openFirewall; };
      enableWsdd = mkBoolOption { default = enableWsdd; };
      enableNmbd = mkBoolOption { default = enableNmbd; };

      extraGlobalSettings = mkOption {
        type = types.attrs;
        default = { };
      };

      shares =
        let
          inherit (head shares)
            name
            path
            comment
            browseable
            readOnly
            guestOk
            forceUser
            forceGroup
            validUsers
            writeList
            createMask
            directoryMask
            extraSettings
            ;
        in
        mkSubmoduleListOption { default = [ ]; } {
          name = mkStrOption { default = name; };
          path = mkStrOption { default = path; };
          comment = mkStrOption { default = comment; };
          browseable = mkBoolOption { default = browseable; };
          readOnly = mkBoolOption { default = readOnly; };
          guestOk = mkBoolOption { default = guestOk; };
          forceUser = mkStrOption { default = forceUser; };
          forceGroup = mkStrOption { default = forceGroup; };
          validUsers = mkStrListOption { default = validUsers; };
          writeList = mkStrListOption { default = writeList; };
          createMask = mkStrOption { default = createMask; };
          directoryMask = mkStrOption { default = directoryMask; };
          extraSettings = mkOption {
            type = types.attrs;
            default = extraSettings;
          };
        };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          lib,
          ...
        }:

        let
          inherit (lib)
            concatStringsSep
            listToAttrs
            mkIf
            optionalAttrs
            ;

          cfg = config.icedos.applications.samba;

          boolYN = b: if b then "yes" else "no";

          mkShare = share: {
            name = share.name;
            value = {
              "path" = share.path;
              "browseable" = boolYN share.browseable;
              "read only" = boolYN share.readOnly;
              "guest ok" = boolYN share.guestOk;
              "create mask" = share.createMask;
              "directory mask" = share.directoryMask;
            }
            // optionalAttrs (share.comment != "") { "comment" = share.comment; }
            // optionalAttrs (share.forceUser != "") { "force user" = share.forceUser; }
            // optionalAttrs (share.forceGroup != "") { "force group" = share.forceGroup; }
            // optionalAttrs (share.validUsers != [ ]) {
              "valid users" = concatStringsSep " " share.validUsers;
            }
            // optionalAttrs (share.writeList != [ ]) {
              "write list" = concatStringsSep " " share.writeList;
            }
            // share.extraSettings;
          };

          shareSettings = listToAttrs (map mkShare cfg.shares);

          globalSettings = {
            "workgroup" = cfg.workgroup;
            "server string" = cfg.serverString;
            "server role" = cfg.serverRole;
            "map to guest" = cfg.mapToGuest;
            "guest account" = cfg.guestAccount;
            "min protocol" = cfg.minProtocol;
            "use sendfile" = boolYN cfg.useSendfile;
            "aio read size" = toString cfg.aioReadSize;
            "aio write size" = toString cfg.aioWriteSize;
            "socket options" = cfg.socketOptions;
            "log file" = cfg.logFile;
            "max log size" = toString cfg.maxLogSize;
          }
          // cfg.extraGlobalSettings;
        in
        {
          assertions = map (s: {
            assertion = s.name != "" && s.path != "";
            message = "icedos.applications.samba.shares: 'name' and 'path' must be non-empty for every share.";
          }) cfg.shares;

          services.samba = {
            enable = true;
            openFirewall = cfg.openFirewall;
            nmbd.enable = cfg.enableNmbd;
            settings = {
              global = globalSettings;
            }
            // shareSettings;
          };

          services.samba-wsdd = mkIf cfg.enableWsdd {
            enable = true;
            openFirewall = cfg.openFirewall;
          };
        }
      )
    ];

  meta.name = "samba";
}
