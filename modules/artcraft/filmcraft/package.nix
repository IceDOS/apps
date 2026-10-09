{ alsa-lib, callPackage }:

callPackage ../lib/mk-craft.nix {
  pname = "filmcraft";
  description = "Open-source video editor (clean-room Premiere Pro-style) in pure Rust";
  extraBuildInputs = [ alsa-lib ];

  source = ./source.json;
}
