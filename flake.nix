{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      in {
        devShells.${system}.default = pkgs.mkShell {
          packages = [
            pkgs.odin
            pkgs.ols
            pkgs.entr
            pkgs.raylib # raylib is dynamically linked and the odin package doesn't provide it
            pkgs.mesa   # tested on Intel Iris GPU
          ];
          # Outside NixOS, Nix's libglvnd looks for the GPU driver in /run/opengl-driver,
          # which doesn't exist: point it to Nix's Mesa instead. Works with Mesa GPUs
          # (Intel, AMD), not with the proprietary NVIDIA driver.
          __EGL_VENDOR_LIBRARY_DIRS = "${pkgs.mesa}/share/glvnd/egl_vendor.d";
        };
      };
}
