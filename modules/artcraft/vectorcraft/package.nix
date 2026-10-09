{ callPackage }:

callPackage ../lib/mk-craft.nix {
  pname = "vectorcraft";
  description = "Open-source vector illustration (clean-room Illustrator-style) in pure Rust";

  source = ./source.json;
}
