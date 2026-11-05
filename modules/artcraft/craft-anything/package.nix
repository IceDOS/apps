{ callPackage }:

callPackage ../lib/mk-craft.nix {
  pname = "craft-anything";
  description = "Open-source tool to study how software works and build your own version";

  source = ./source.json;
}
