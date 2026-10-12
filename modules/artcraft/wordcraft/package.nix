{ callPackage }:

callPackage ../lib/mk-craft.nix {
  pname = "wordcraft";
  description = "Open-source word processor (clean-room Word-style) in pure Rust";

  source = ./source.json;
}
