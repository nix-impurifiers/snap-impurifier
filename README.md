# snap-impurifier

Build native classic-confinement snaps for Nix applications. Snapd owns the
SquashFS files, mounts, revisions and user data; Nix owns application closures.
Original code is MIT licensed. Upstream snapd, Nix, Go and other dependencies
retain their original licenses and notices.

```nix
let
  impurifier = inputs.snap-impurifier.lib.snap-impurifier { inherit pkgs; };
in impurifier.makeOfflineSnap { pkg = pkgs.hello; }
```

Install through native Snap:

```
sudo snap install --dangerous --classic ./hello-2.12.3.snap
sudo snap-impurifier prepare --owner "$USER" hello
snap run hello
```

`--dangerous` is the native policy for a locally built snap without Store
assertions. Production Store publication and classic-confinement review are
separate workflows. Classic confinement gives the app access to the host,
including its Nix store and daemon; this is not a strict-sandbox adapter.
The host must already provide Nix and this project's matching helper package.
Providing Nix through an impure native package remains a deferred goal.

`makeNetSnap` omits offline caches; `makeOfflineSnap` includes application and
tool caches. `makePackage` returns a net/offline pair. `name` selects the native
Snap name and `program` selects the Nix executable. The current SDK targets
Linux x86_64 and emits `amd64` metadata. Snapd's native `bare` and system-snap
dependencies must be installed or available to the native installer; offline
Nix caches do not replace those native dependencies.

Preparation queries the real snapd Unix API for the active revision. It imports
only Nix store data, then registers existing immutable deployment symlinks as
the requested owner. It does not run application code as root or change host
Nix daemon trust settings. A normal user can prepare through trusted
substituters; unsigned caches need explicit trusted preparation. Repeat
preparation for a new offline revision. Launch uses pinned Python/Nix tools and
the native Nix API to retain the application without rewriting its mount.

Native `snap revert` selects a retained revision and its existing Nix root.
Removing an old revision releases that revision's root; `snap remove --purge`
removes the snap and its native data. Nix GC then releases unused closures.
Optional `hardware` accepts the shared explicit library/program mapping and
captures host ELF libraries into immutable snapshots at each launch. Snapshots
live under `SNAP_USER_COMMON`; run `snap-impurifier prune` as the owner after
retiring revisions to release their snapshots. Native purge also removes those
user-data roots. Real GPU/kernel ABI compatibility is not claimed.

The VM suite uses upstream snapd 2.78, real systemd user scopes, SquashFS mounts,
and snap-confine's exact upstream cgroup-v2 file-capability list. It installs
the official signed `bare` revision 5 and `snapd` revision 28254 through native
assertion verification. The test adapts NixOS's generated configuration
directories into writable directories so snapd can manage its own systemd,
D-Bus and udev files. Native state and revision databases are never synthesized.

Coverage includes native install/run/removal, net failure, rejected untrusted
cache preparation, offline recovery, unchanged package hashes, revision
updates/revert/retention/removal, host-library replacement and Nix GC. Strict
confinement, AppArmor enforcement, services, Snap Store publication, snapshot
restore and other architectures require additional coverage.

## Prepared native payloads and bundled clients

`makeNativeSnap { name; version; payload; program; architecture ? "amd64"; }`
packs a complete prepared application tree with `bin/<program>`. It adds no
engine, Nix SDK or activation. The producer supplies target-compatible files;
this does not relocate binaries. Native snaps retain classic confinement and
`bare` base requirements. The actual snapd VM executes a static native payload,
upgrades it and removes it, and separately executes its installed binary in an
isolated root without `/nix`. This is not a complete Nix-free host boot test.

Nix-backed constructors accept `bundledNixStore` and `bundledNixNotices` (a list
of upstream notice files). Supply a static ELF client. The app carries that
client privately and omits the SDK CLI. Launch prefers a compatible external
client, then the supplied client; explicit `IMPURIFIER_NIX_STORE` disables
fallback. Selection happens before registration or hardware capture. The
trusted host preparation helper still uses host tools and never executes the
application-owned client as root. This requires an existing Nix store, daemon
and initial SDK preparation; it is not a Nix installer. A separate bundled VM
repeats the revision, retention, hardware and GC lifecycle with an incompatible
external candidate.
