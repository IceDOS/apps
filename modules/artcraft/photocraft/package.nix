{ callPackage }:

callPackage ../lib/mk-craft.nix {
  pname = "photocraft";
  description = "Open-source image editor (clean-room Photoshop-style) in pure Rust";

  source = ./source.json;
}
