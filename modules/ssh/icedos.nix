{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      {
        services.openssh.enable = true;
        programs.zsh.shellAliases.ssh = "TERM=xterm-256color ssh";
      }
    ];

  meta.name = "ssh";
}
