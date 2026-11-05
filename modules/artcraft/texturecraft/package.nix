{ callPackage }:

callPackage ../lib/mk-craft.nix {
  pname = "texturecraft";
  description = "Open-source 3D texture painting in pure Rust";

  source = ./source.json;
}
