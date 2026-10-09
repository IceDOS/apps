{ alsa-lib, callPackage }:

callPackage ../lib/mk-craft.nix {
  pname = "effectcraft";
  description = "Open-source motion graphics and visual effects in pure Rust";
  extraBuildInputs = [ alsa-lib ];

  source = ./source.json;
}
