{ callPackage }:

callPackage ../lib/mk-craft.nix {
  pname = "materialcraft";
  description = "Open-source, node-based procedural material designer in pure Rust";

  source = ./source.json;
}
