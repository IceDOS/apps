{ callPackage }:

callPackage ../lib/mk-craft.nix {
  pname = "gridcraft";
  description = "Open-source spreadsheet (clean-room Excel-style) in pure Rust";

  source = ./source.json;
}
