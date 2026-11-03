# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  coreSrc,
  tools,
  bundled ? false,
}:
let
  app = pkgs.writeShellScriptBin "snap-app" "echo nix-in-snap" // {
    pname = "snap-app";
    version = "1";
  };
  app2 = pkgs.writeShellScriptBin "snap-app" "echo upgraded-nix-snap" // {
    pname = "snap-app";
    version = "2";
  };
  staticNix = import (coreSrc + "/tests/static-nix.nix") { inherit pkgs; };
  bundleArgs = pkgs.lib.optionalAttrs bundled {
    bundledNixStore = "${staticNix}/bin/nix-store";
    bundledNixNotices = [ "${pkgs.nix.src}/COPYING" ];
  };
  builder = impurifier // {
    makeNetSnap = args: impurifier.makeNetSnap (args // bundleArgs);
    makeOfflineSnap = args: impurifier.makeOfflineSnap (args // bundleArgs);
  };
  net = builder.makeNetSnap { pkg = app; };
  offline = builder.makeOfflineSnap { pkg = app; };
  update = builder.makeOfflineSnap { pkg = app2; };
  fixture = import (coreSrc + "/tests/hardware-fixture.nix") { inherit pkgs; };
  hardware = builder.makeOfflineSnap {
    pkg = fixture.tool;
    inherit (fixture) hardware;
  };
  systemSnap = pkgs.fetchurl {
    url = "https://api.snapcraft.io/api/v1/snaps/download/PMrrV4ml8uWuEUDBT8dSGnKUYbevVhc4_28254.snap";
    hash = "sha256-lEe/4hWsDSxCaZR3mqtU4cpmdZsdpZG7q/GLmVUmtDg=";
  };
  bare = pkgs.fetchurl {
    url = "https://api.snapcraft.io/api/v1/snaps/download/EISPgh06mRh1vordZY9OZ34QHdd7OrdR_5.snap";
    hash = "sha256-A9Ci62LhuIYeVX94dfLXT1n1bImsC0d1++bQDEZfyEs=";
  };
  nativePayload =
    version:
    pkgs.runCommand "native-snap-payload-${version}"
      {
        nativeBuildInputs = [ pkgs.pkgsStatic.stdenv.cc ];
      }
      ''
        mkdir -p $out/bin
        cat > proof.c <<'C'
        #include <stdio.h>
        int main(void) { puts("native-snap-${version}"); return 0; }
        C
        $CC -static proof.c -o $out/bin/marker
      '';
  marker = impurifier.makeNativeSnap {
    name = "native-marker";
    version = "1";
    payload = nativePayload "1";
    program = "marker";
  };
  marker2 = impurifier.makeNativeSnap {
    name = "native-marker";
    version = "2";
    payload = nativePayload "2";
    program = "marker";
  };
in
{
  native-vm = pkgs.testers.runNixOSTest {
    name = "snap-native-contract${pkgs.lib.optionalString bundled "-bundled"}";
    requiredFeatures = {
      kvm = false;
      devnet = false;
    };
    nodes.machine = { lib, ... }: {
      virtualisation.qemu.package = lib.mkForce pkgs.qemu;
      virtualisation.qemu.forceAccel = false;
      virtualisation.memorySize = 3072;
      virtualisation.diskSize = 12288;
      environment.systemPackages = [
        impurifier.package
        pkgs.nix
        pkgs.squashfsTools
        pkgs.util-linux
        pkgs.dbus
        pkgs.udev
      ];
      nix.settings.substituters = lib.mkForce [ ];
      environment.etc = lib.optionalAttrs bundled {
        "impurifier-bundle-test".text = "bundled";
      };
      system.activationScripts.bundle-test = lib.mkIf bundled {
        deps = [
          "users"
          "native-snapd"
        ];
        text = ''
          printf '#!${pkgs.runtimeShell}\necho incompatible-client\n' > /usr/bin/nix-store
          chmod 755 /usr/bin/nix-store
          printf 'export PATH=/usr/bin:${pkgs.systemd}/bin:${impurifier.package}/bin\n' > /home/consumer/.bash_profile
          chown consumer:users /home/consumer/.bash_profile
        '';
      };
      boot.supportedFilesystems = [ "squashfs" ];
      users.users.consumer.isNormalUser = true;
      system.activationScripts.native-snapd.deps = [ "etc" ];
      system.activationScripts.native-snapd.text = ''
        for directory in /etc/systemd/system /etc/systemd/user /etc/udev/rules.d /etc/dbus-1 /etc/dbus-1/system.d /etc/dbus-1/session.d; do
          if test -L "$directory"; then
            original=$(readlink -f "$directory")
            rm "$directory"
            cp -r "$original" "$directory"
          fi
          mkdir -p "$directory"
          chmod -R u+w "$directory"
        done
        while IFS= read -r directory; do mkdir -p "/$directory"; done < ${tools.source}/packaging/ubuntu-16.04/snapd.dirs
        mkdir -p /usr/bin /usr/lib/snapd /snap /var/lib/snapd /usr/lib/systemd/system-generators
        cp -r ${tools.package}/usr/lib/snapd/. /usr/lib/snapd/
        cp ${tools.package}/usr/bin/snap /usr/bin/snap
        chmod 755 /usr/lib/snapd/snap-confine
        ${pkgs.libcap}/bin/setcap "$(cat /usr/lib/snapd/snap-confine.v2-only.caps)" /usr/lib/snapd/snap-confine
        install -d -m 111 /var/lib/snapd/void
        for tool in ${pkgs.util-linux}/bin/* ${pkgs.coreutils}/bin/*; do
          ln -sf "$tool" /usr/bin/"$(basename "$tool")"
        done
        ln -sf ${pkgs.systemd}/bin/systemctl /usr/bin/systemctl
        ln -sf ${pkgs.systemd}/bin/systemd-detect-virt /usr/bin/systemd-detect-virt
        ln -sf ${pkgs.udev}/bin/udevadm /usr/bin/udevadm
        ln -sf ${pkgs.squashfsTools}/bin/unsquashfs /usr/bin/unsquashfs
      '';
      systemd.sockets.snapd = {
        wantedBy = [ "sockets.target" ];
        listenStreams = [
          "/run/snapd.socket"
          "/run/snapd-snap.socket"
        ];
        socketConfig.SocketMode = "0666";
      };
      systemd.services.snapd = {
        requires = [ "snapd.socket" ];
        after = [ "snapd.socket" ];
        wantedBy = [ "multi-user.target" ];
        environment = {
          SNAP_REEXEC = "0";
          PATH = lib.mkForce "/usr/bin:/run/current-system/sw/bin";
        };
        serviceConfig = {
          ExecStart = "/usr/lib/snapd/snapd";
          Type = "notify";
          NotifyAccess = "all";
        };
      };
    };
    testScript = ''
      import shlex
      start_all()
      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("snapd.service")
      machine.succeed("cp ${hardware} /home/consumer/hardware.snap; cp ${net} /home/consumer/net.snap; cp ${offline} /home/consumer/offline.snap; cp ${update} /home/consumer/update.snap")
      machine.succeed("/usr/bin/snap version")
      machine.succeed("timeout 60 /usr/bin/snap wait system seed.loaded")
      machine.succeed("/usr/bin/snap ack ${./fixtures/snapd.assert}; /usr/bin/snap install ${systemSnap}")
      machine.succeed("/usr/bin/snap ack ${./fixtures/bare.assert}; /usr/bin/snap install ${bare}")
      machine.succeed("/usr/bin/snap install --dangerous --classic ${marker}")
      machine.succeed("/usr/bin/snap list")
      machine.succeed("loginctl enable-linger consumer")
      machine.wait_for_unit("user@1000.service")
      assert machine.succeed("su - consumer -c 'XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus systemd-run --user --scope --quiet /usr/bin/snap run native-marker'").strip() == "native-snap-1"
      machine.succeed("mkdir -p /srv/native/bin; cp /snap/native-marker/current/bin/marker /srv/native/bin/marker")
      assert machine.succeed("chroot /srv/native /bin/marker").strip() == "native-snap-1"
      machine.succeed("test ! -e /srv/native/nix; test ! -e /snap/native-marker/current/launch.py")
      machine.succeed("/usr/bin/snap install --dangerous --classic ${marker2}")
      assert machine.succeed("su - consumer -c 'XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus systemd-run --user --scope --quiet /usr/bin/snap run native-marker'").strip() == "native-snap-2"
      machine.succeed("/usr/bin/snap remove --purge native-marker")
      machine.succeed("test ! -e /snap/native-marker/current")
      machine.succeed("mkdir -p /root/drivers /usr/lib; cp ${fixture.driver "1"}/usr/lib/libimpurifier-driver.so.1 /root/drivers/1.so; cp ${fixture.driver "2"}/usr/lib/libimpurifier-driver.so.1 /root/drivers/2.so")
      def user_command(command):
          return "su - consumer -c " + shlex.quote("XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus systemd-run --user --scope --quiet " + command)
      def run_app():
          return machine.succeed(user_command("/usr/bin/snap run snap-app")).strip()
      ${pkgs.lib.optionalString bundled ''
        assert machine.succeed("su - consumer -c 'nix-store --version'").strip() == "incompatible-client"
      ''}
      machine.succeed("/usr/bin/snap set system refresh.retain=3")
      machine.succeed("nix-store --gc; test ! -e ${builtins.unsafeDiscardStringContext (toString app)}")
      machine.succeed("/usr/bin/snap install --dangerous --classic /home/consumer/net.snap")
      machine.fail(user_command("/usr/bin/snap run snap-app"))
      machine.succeed("/usr/bin/snap install --dangerous --classic /home/consumer/offline.snap")
      image_hash = machine.succeed("sha256sum /var/lib/snapd/snaps/snap-app_x2.snap")
      machine.fail(user_command("snap-impurifier prepare snap-app"))
      machine.succeed("snap-impurifier prepare --owner consumer snap-app")
      machine.succeed("nix-store --gc")
      assert run_app() == "nix-in-snap"
      assert machine.succeed("sha256sum /var/lib/snapd/snaps/snap-app_x2.snap") == image_hash
      machine.succeed("/usr/bin/snap install --dangerous --classic /home/consumer/update.snap")
      machine.fail(user_command("/usr/bin/snap run snap-app"))
      machine.succeed("snap-impurifier prepare --owner consumer snap-app")
      assert run_app() == "upgraded-nix-snap"
      machine.succeed("/usr/bin/snap revert snap-app --revision=x2")
      assert run_app() == "nix-in-snap"
      machine.succeed("/usr/bin/snap revert snap-app --revision=x3")
      assert run_app() == "upgraded-nix-snap"
      machine.succeed("nix-store --gc; test -e ${builtins.unsafeDiscardStringContext (toString app)}; test -e ${builtins.unsafeDiscardStringContext (toString app2)}")
      machine.succeed("/usr/bin/snap remove snap-app --revision=x1; /usr/bin/snap remove snap-app --revision=x2")
      machine.succeed("nix-store --gc; test ! -e ${builtins.unsafeDiscardStringContext (toString app)}; test -e ${builtins.unsafeDiscardStringContext (toString app2)}")
      machine.succeed("/usr/bin/snap remove --purge snap-app")
      machine.succeed("nix-store --gc; test ! -e ${builtins.unsafeDiscardStringContext (toString app2)}")
      machine.succeed("/usr/bin/snap install --dangerous --classic /home/consumer/hardware.snap")
      machine.succeed("snap-impurifier prepare --owner consumer hardware-tool; cp /root/drivers/1.so /usr/lib/libimpurifier-driver.so.1")
      assert machine.succeed(user_command("/usr/bin/snap run hardware-tool")).strip() == "1"
      machine.succeed("cp /root/drivers/2.so /usr/lib/libimpurifier-driver.so.1")
      assert machine.succeed(user_command("/usr/bin/snap run hardware-tool")).strip() == "2"
      machine.succeed("/usr/bin/snap remove --purge hardware-tool")
      machine.succeed(user_command("snap-impurifier prune"))
      machine.succeed("nix-store --gc; test ! -e ${builtins.unsafeDiscardStringContext (toString fixture.tool)}")
    '';
  };
}
