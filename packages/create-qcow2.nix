{ pkgs, ... }:

pkgs.writeShellApplication {
  name = "create-qcow2";
  runtimeInputs = [ pkgs.qemu ];
  text = ''
    set -euo pipefail

    usage() {
      echo "Usage: create-qcow2 <image-path> <size> [--force]" >&2
      echo "  <image-path>: absolute or relative path to qcow2 image" >&2
      echo "  <size>: size like 20G, 100G, 50M" >&2
      echo "  --force: overwrite existing file if present" >&2
    }

    if [ "$#" -lt 2 ]; then
      usage
      exit 2
    fi

    IMAGE_PATH="$1"; shift
    SIZE="$1"; shift
    FORCE=0
    if [ "''${1:-}" = "--force" ]; then
      FORCE=1
    fi

    if [ -e "$IMAGE_PATH" ] && [ "$FORCE" -ne 1 ]; then
      echo "Refusing to overwrite existing file: $IMAGE_PATH (use --force)" >&2
      exit 1
    fi

    # Ensure parent directory exists
    PARENT_DIR=$(dirname "$IMAGE_PATH")
    mkdir -p "$PARENT_DIR"

    echo "Creating qcow2 image at $IMAGE_PATH with size $SIZE"
    if [ "$FORCE" -eq 1 ]; then
      rm -f "$IMAGE_PATH"
    fi
    qemu-img create -f qcow2 "$IMAGE_PATH" "$SIZE"

    echo "Created qcow2 image: $IMAGE_PATH"
    echo "You can now use this as the vfkit root disk (virtio)."
  '';
}
