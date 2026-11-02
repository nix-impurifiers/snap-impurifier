The assertion files are unchanged public Snap Store assertion chains obtained
with the real `snap download` client. They are third-party signed data, not
original code covered by this project's MIT license.

- `bare.assert`: Canonical bare base, snap ID
  `EISPgh06mRh1vordZY9OZ34QHdd7OrdR`, revision 5, version 1.0.
- `snapd.assert`: Canonical system snap, snap ID
  `PMrrV4ml8uWuEUDBT8dSGnKUYbevVhc4`, revision 28254, version 2.77.1,
  GPL-3.0 as declared by its native metadata.

The payloads are fixed-hash downloads from the official Snap Store URLs in
`tests/default.nix`. Native `snap ack` and installation verify the assertion
chains against snapd's production trust roots. No test signing keys are built
into the SDK. The bare base contains directories and native package metadata.
The system snap retains its upstream notices.

The SDK preserves snapd source and complete vendored dependency source as
archives, plus the snapd and Go runtime license texts. It uses upstream's
normal `nosecboot` desktop build tag; Ubuntu Core secure-boot workflows are
not part of this VM fixture.
