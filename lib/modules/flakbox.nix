{ pkgs, lib, config, ... }:

let
  inherit (lib) types;
in
{

  options.flakebox = {
    lint = {
      enable = lib.mkEnableOption (lib.mdDoc "the flakebox binary integration") // {
        default = true;
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf config.flakebox.lint.enable {
      env.shellHooks = [
        ''
          if ! flakebox lint --silent; then
            >&2 echo "ℹ️  Project recommendations detected. Run 'flakebox lint' for more info."
          fi
        ''
      ];
    })
  ];
}