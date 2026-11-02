# SPDX-License-Identifier: MIT
{
  pkgs,
  coreSrc,
  sourceInfo ? { },
}:
let
  inherit (pkgs) lib;
  tools = import ./tools.nix { inherit pkgs; };
  registerRoot = import ./register-root.nix { inherit pkgs; };
  core = import (coreSrc + "/nix") {
    inherit pkgs;
    namespace = "snap-impurifier";
  };
  sdk = pkgs.linkFarm "snap-impurifier-sdk" [
    {
      name = "python";
      path = pkgs.python3;
    }
    {
      name = "nix";
      path = pkgs.nix;
    }
    {
      name = "register-root";
      path = registerRoot;
    }
  ];
  package = pkgs.writeShellApplication {
    name = "snap-impurifier";
    runtimeInputs = [
      pkgs.nix
      pkgs.python3
      registerRoot
    ];
    text = ''
      case "''${1:-}" in
        prune) shift; exec ${sdk}/python/bin/python3 ${../src/prune.py} ;;
        prepare) shift; exec ${sdk}/python/bin/python3 ${../src/prepare.py} "$@" ;;
        *) echo 'usage: snap-impurifier prepare [--owner USER] SNAP' >&2; exit 2 ;;
      esac
    '';
  };
  makeSnap =
    {
      pkg,
      name ? pkg.pname,
      program ? pkg.meta.mainProgram or pkg.pname,
      offline ? false,
      hardware ? null,
    }:
    assert lib.assertMsg (builtins.match "[a-z][a-z0-9-]{0,39}" name != null) "invalid snap name";
    assert lib.assertMsg (
      builtins.match "[A-Za-z0-9_+-][A-Za-z0-9_.+-]*" program != null
    ) "invalid program";
    assert lib.assertMsg (
      pkgs.stdenv.hostPlatform.system == "x86_64-linux"
    ) "Snap SDK currently supports x86_64-linux";
    assert lib.assertMsg (
      hardware == null || lib.elem program (hardware.programs or [ ])
    ) "hardware must select this program";
    pkgs.runCommand "${name}-${pkg.version}.snap"
      {
        nativeBuildInputs = [ pkgs.squashfsTools ];
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
      }
      ''
        mkdir -p root/meta root/bin
        cp ${../src/launch.py} root/launch.py
        cp ${coreSrc}/src/engine.py root/engine.py
        cp ${../LICENSE} root/LICENSE
        cp ${
          pkgs.writeText "application.json" (
            builtins.toJSON {
              inherit program;
              hardware = if hardware == null then null else { preload = [ ]; } // hardware;
              nixBin = "${pkgs.nix}/bin";
              registerRoot = "${registerRoot}/bin/impurifier-register-root";
            }
          )
        } root/application.json
        ln -s ${sdk} root/sdk-root
        ln -s ${pkg} root/nix-root
        printf '#!${pkgs.python3}/bin/python3\nimport runpy\nfrom pathlib import Path\nrunpy.run_path(str(Path(__file__).resolve().parent.parent / "launch.py"), run_name="__main__")\n' > root/bin/impurifier-launch
        chmod 755 root/bin/impurifier-launch
        ${lib.optionalString offline ''
          cp -r ${core.offlineCache pkg} root/cache
          cp -r ${core.offlineCache sdk} root/sdk-cache
        ''}
        cat > root/meta/snap.yaml <<'YAML'
        name: ${name}
        version: ${builtins.toJSON pkg.version}
        summary: Nix application in a native Snap
        description: Native Snap ownership and immutable roots for a Nix application closure.
        architectures: [amd64]
        grade: devel
        confinement: classic
        base: bare
        apps:
          ${name}:
            command: bin/impurifier-launch
        YAML
        ${tools.package}/usr/bin/snap pack root . --filename projection.snap
        mv projection.snap $out
      '';
in
{
  inherit
    tools
    package
    sdk
    makeSnap
    ;
  makeNetSnap = args: makeSnap (args // { offline = false; });
  makeOfflineSnap = args: makeSnap (args // { offline = true; });
  makePackage = args: {
    net = makeSnap (args // { offline = false; });
    offline = makeSnap (args // { offline = true; });
  };
}
