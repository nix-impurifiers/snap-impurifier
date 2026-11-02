# SPDX-License-Identifier: MIT
{ pkgs }:
let
  source = pkgs.fetchFromGitHub {
    owner = "canonical";
    repo = "snapd";
    rev = "00b63144e44cdb7bd059e40e947e720b942c55ec";
    hash = "sha256-bgeBD3yVVa4HZmejJhBxxWb9myvV/SNo9E06ET0cDxw=";
  };
  goLicense =
    pkgs.runCommand "go-runtime-LICENSE"
      {
        nativeBuildInputs = [
          pkgs.gnutar
          pkgs.gzip
        ];
      }
      ''
        tar -xOf ${pkgs.go.src} go/LICENSE > $out
      '';
  package = pkgs.buildGoModule {
    pname = "native-snapd";
    version = "2.78";
    src = source;
    nativeBuildInputs = [
      pkgs.go
      pkgs.pkg-config
      pkgs.autoconf
      pkgs.autoconf-archive
      pkgs.automake
      pkgs.libtool
      pkgs.git
      pkgs.python3
      pkgs.gettext
      pkgs.which
    ];
    buildInputs = [
      pkgs.xfsprogs.dev
      pkgs.libcap
      pkgs.libseccomp
      pkgs.libapparmor
      pkgs.systemd
      pkgs.glib
    ];
    vendorHash = "sha256-zvqVKcHbVOPQYVAZ06AitfjF9C4JXSFUTIzdYGXHdEI=";
    doCheck = false;
    dontAutoreconf = true;
    enableParallelBuilding = true;
    buildPhase = ''
      runHook preBuild
      export HOME=$TMPDIR/home GOPATH=$TMPDIR/gopath GOCACHE=$TMPDIR/go-cache
      mkdir -p "$HOME" build/bin
      ./mkversion.sh 2.78
      for name in snapd snapctl snap-update-ns snap-seccomp; do
        go build -mod=vendor -tags nosecboot -o build/bin/$name ./cmd/$name
      done
      (cd cmd; autoreconf -fi; ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --libexecdir=/usr/lib/snapd --without-unit-tests; make -j$NIX_BUILD_CORES STATIC_LDFLAGS="-static -L${pkgs.glibc.static}/lib")
      runHook postBuild
    '';
    installPhase = ''
      mkdir -p $out/usr/bin $out/usr/lib/snapd $out/share/src/snapd
      ln -s ../lib/snapd/snapd $out/usr/bin/snap
      cp build/bin/{snapd,snapctl,snap-update-ns,snap-seccomp} $out/usr/lib/snapd/
      cp data/info $out/usr/lib/snapd/info
      make -C cmd DESTDIR=$out install
      chmod u+r $out/var/lib/snapd/void
      ln -s snapctl $out/usr/lib/snapd/snap-exec
      ln -s snapd-tool-wrap $out/usr/lib/snapd/snapd-apparmor
      tar --sort=name --mtime=@1 --owner=0 --group=0 -cf $out/share/src/snapd/source.tar -C ${source} .
      tar --sort=name --mtime=@1 --owner=0 --group=0 -cf $out/share/src/snapd/vendor.tar -C vendor .
      mkdir -p $out/share/licenses/snapd
      cp ${source}/COPYING $out/share/licenses/snapd/COPYING
      mkdir -p $out/share/licenses/go
      cp ${goLicense} $out/share/licenses/go/LICENSE
    '';
  };
in
{
  inherit package source;
}
