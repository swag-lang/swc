# Ed25519 projective signature verification

Verification compares cross-products of the projective coordinates. The exact
group equation and public-key subgroup check enforce the commitment's subgroup
membership. The added fixture preserves rejection of identity commitments.
All five native Ed25519 tests passed in Release and Release-safe, and 24
independent cases agreed with OpenSSL.

On AMD EPYC 9V74 CPU 3, twenty paired process CPU-time samples dropped verify
latency from 1327.8 to 852.1 µs. The paired speedup was
1.55x (95% CI 1.53–1.57x). Signing and
public-key derivation ran as controls.

[Raw trials](ed25519-projective.json).
