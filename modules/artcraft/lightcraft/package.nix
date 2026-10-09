{ callPackage }:

callPackage ../lib/mk-craft.nix {
  pname = "lightcraft";
  description = "Open-source photo library and raw developer (clean-room Lightroom-style) in pure Rust";

  source = ./source.json;
}
