# Forge the non-desktop HDR EDID for the single output mode (width×height@refresh)
# + maxNit. Build fails if forge_edid.py rejects the mode (over the 655 MHz DTD
# ceiling) or if edid-decode --check finds a conformance failure — a bad EDID
# cannot ship.
{
  lib,
  runCommand,
  python3,
  libxcvt,
  edid-decode,
}:

{
  width,
  height,
  refresh,
  maxNit,
  manufacturer ? "VLV", # Valve → kernel EDID_QUIRK_NON_DESKTOP
  product ? 37288, # 0x91A8 = Valve Index
}:

let
  config = builtins.toJSON {
    inherit maxNit manufacturer product;
    modes = [
      {
        width = lib.toInt width;
        height = lib.toInt height;
        refreshRates = [ refresh ];
        preferred = true;
      }
    ];
  };
in
runCommand "sunshine-headless-edid"
  {
    nativeBuildInputs = [
      python3
      libxcvt
      edid-decode
    ];
    inherit config;
    passAsFile = [ "config" ];
  }
  ''
    python3 ${./forge_edid.py} "$configPath" edid.bin
    edid-decode --check edid.bin
    install -Dm444 edid.bin "$out/edid.bin"
  ''
