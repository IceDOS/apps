{ callPackage }:

callPackage ../lib/mk-craft.nix {
  pname = "figcraft";
  description = "Open-source UI design and prototyping tool (clean-room Figma-style) in pure Rust";

  source = ./source.json;
}
