{
  description = "Excaliself - self-hosted Excalidraw whiteboard";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    excaliself = {
      url = "github:maciekzygmunt/excaliself/v0.9.0";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, excaliself }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        # "x86_64-darwin"
        # "aarch64-darwin"
      ];
      pkgsFor = system: import nixpkgs { inherit system; };

    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;

          demo-vm = (nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              "${nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
              {
                services.excaliself = {
                  enable = true;
                  host = "0.0.0.0"; # reach the app through the forwarded port
                  baseUrl = "http://localhost:3000";
                };
                users.motd = ''
                  Excaliself demo. Open http://localhost:3000 on your host.
                  This VM is throwaway (fresh each run). Quit with Ctrl-A x.
                '';
                system.stateVersion = "26.11";
                networking.firewall.allowedTCPPorts = [ 3000 ];
                services.getty.autologinUser = "root";
                virtualisation = {
                  memorySize = 2048;
                  graphics = false;
                  diskImage = null; # fresh state every run
                  forwardPorts = [
                    {
                      host.address = "127.0.0.1";
                      host.port = 3000;
                      guest.port = 3000;
                    }
                  ];
                };
              }
            ];
          }).config.system.build.vm;
        in
        {
          default = pkgs.callPackage ./package.nix {
            src = excaliself;
          };
        }
        // nixpkgs.lib.optionalAttrs (nixpkgs.lib.hasSuffix "-linux" system) {
          inherit demo-vm;
        }
      );

      nixosModules.default = import ./module.nix { inherit self; };

      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          excaliself-module = pkgs.testers.nixosTest {
            name = "excaliself-module";
            nodes.machine =
              { pkgs, ... }:
              {
                imports = [ self.nixosModules.default ];
                services.excaliself.enable = true;
                environment.systemPackages = [ pkgs.curl ];
                virtualisation.memorySize = 2048;
              };
            testScript = ''
              machine.start()
              machine.wait_for_unit("excaliself.service")
              machine.wait_for_open_port(3000)
              machine.succeed("curl -fs http://127.0.0.1:3000/api/health")
            '';
          };
        }
      );
    };
}
