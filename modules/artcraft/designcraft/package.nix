{ callPackage }:

callPackage ../lib/mk-craft.nix {
  pname = "designcraft";
  description = "Open-source page layout and publishing in pure Rust";

  source = ./source.json;
}
