{ callPackage }:

callPackage ../lib/mk-craft.nix {
  pname = "cadcraft";
  description = "Open-source computer-aided design and drafting (clean-room AutoCAD-style) in pure Rust";

  source = ./source.json;
}
