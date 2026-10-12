{ alsa-lib, callPackage }:

callPackage ../lib/mk-craft.nix {
  pname = "soundcraft";
  description = "Open-source digital audio workstation (clean-room Pro Tools-style) in pure Rust";
  extraBuildInputs = [ alsa-lib ];

  source = ./source.json;
}
