{ icedosLib, lib, ... }:

{
  options.icedos.applications.samba =
    let
      inherit (lib)
        head
        readFile
        ;
      inherit (icedosLib)
        mkAttrsOption
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
      extraGlobalSettings = mkAttrsOption { default = { }; };

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
          extraSettings = mkAttrsOption { default = extraSettings; };
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

          inherit (config.icedos.applications.samba)
            aioReadSize
            aioWriteSize
            enableNmbd
            enableWsdd
            extraGlobalSettings
            guestAccount
            logFile
            mapToGuest
            maxLogSize
            minProtocol
            openFirewall
            serverRole
            serverString
            shares
            socketOptions
            useSendfile
            workgroup
            ;

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

          shareSettings = listToAttrs (map mkShare shares);

          globalSettings = {
            "workgroup" = workgroup;
            "server string" = serverString;
            "server role" = serverRole;
            "map to guest" = mapToGuest;
            "guest account" = guestAccount;
            "min protocol" = minProtocol;
            "use sendfile" = boolYN useSendfile;
            "aio read size" = toString aioReadSize;
            "aio write size" = toString aioWriteSize;
            "socket options" = socketOptions;
            "log file" = logFile;
            "max log size" = toString maxLogSize;
          }
          // extraGlobalSettings;
        in
        {
          assertions = map (s: {
            assertion = s.name != "" && s.path != "";
            message = "icedos.applications.samba.shares: 'name' and 'path' must be non-empty for every share.";
          }) shares;

          services.samba = {
            inherit openFirewall;

            enable = true;
            nmbd.enable = enableNmbd;
            settings = {
              global = globalSettings;
            }
            // shareSettings;
          };

          services.samba-wsdd = mkIf enableWsdd {
            inherit openFirewall;

            enable = true;
          };
        }
      )
    ];

  meta.name = "samba";
}
