{ alsa-lib, callPackage }:

callPackage ../lib/mk-craft.nix {
  pname = "deckcraft";
  description = "Open-source presentations and slide shows (clean-room PowerPoint-style) in pure Rust";
  extraBuildInputs = [ alsa-lib ];

  source = ./source.json;
}
