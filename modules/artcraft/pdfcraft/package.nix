{ callPackage }:

callPackage ../lib/mk-craft.nix {
  pname = "pdfcraft";
  description = "Open-source PDF workbench (clean-room Acrobat-style) in pure Rust";

  source = ./source.json;
}
