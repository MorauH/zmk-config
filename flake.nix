{
  description = "ZMK Config firmware builder (Docker-based)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        zmkBuild = pkgs.writeShellScriptBin "zmk-build" ''
          set -euo pipefail

          CONFIG_DIR="''${ZMK_CONFIG_DIR:-$PWD}"
          TARGET="''${1:-both}"

          ZMK_IMAGE="zmkfirmware/zmk-dev-arm:stable"

          echo "==> Pulling ZMK Docker image..."
          docker pull "$ZMK_IMAGE" >&2

          docker run --rm \
            -v "$CONFIG_DIR:/workspace" \
            -w /workspace \
            "$ZMK_IMAGE" \
            bash -c "
              set -e
              git config --global --add safe.directory '*'
              west init -l /workspace/config || true
              west update 2>&1
              west zephyr-export 2>&1

              build_one() {
                echo '==> Building: '\$1
                west build -d build/\$1 -b nice_nano_v2 /workspace/zmk/app -p -- \
                  -DSHIELD=\$1 \
                  -DZMK_CONFIG=/workspace/config
                cp build/\$1/zephyr/zmk.uf2 /workspace/\$1.uf2
                echo '==> Built: /workspace/'\$1.uf2
              }

              case '$TARGET' in
                both)
                  build_one corne_left
                  build_one corne_right
                  ;;
                left)
                  build_one corne_left
                  ;;
                right)
                  build_one corne_right
                  ;;
                *)
                  echo 'Usage: zmk-build [left|right|both]'
                  exit 1
                  ;;
              esac
            "

          echo ""
          echo "==> Done. Firmware files:"
          [ -f "$CONFIG_DIR/corne_left.uf2" ]  && echo "    $CONFIG_DIR/corne_left.uf2"
          [ -f "$CONFIG_DIR/corne_right.uf2" ] && echo "    $CONFIG_DIR/corne_right.uf2"
        '';

        zmkClean = pkgs.writeShellScriptBin "zmk-clean" ''
          set -euo pipefail
          CONFIG_DIR="''${ZMK_CONFIG_DIR:-$PWD}"
          rm -rf "$CONFIG_DIR/.west" \
                 "$CONFIG_DIR/zmk" \
                 "$CONFIG_DIR/zephyr" \
                 "$CONFIG_DIR/modules" \
                 "$CONFIG_DIR/tools" \
                 "$CONFIG_DIR/bootloader" \
                 "$CONFIG_DIR/build"
          echo "Cleaned west workspace"
        '';
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = [ pkgs.docker zmkBuild zmkClean ];
          shellHook = ''
            echo "ZMK build environment"
            echo "  zmk-build        - build both halves"
            echo "  zmk-build left   - build left only"
            echo "  zmk-build right  - build right only"
            echo "  zmk-clean        - remove west workspace"
          '';
        };

        packages.default = zmkBuild;
      }
    );
}
