# SHA instruction encoding and lowering

The typed x64 operations cover SHA-1 and SHA-256 round and message-schedule
instructions. The compiler dispatches through the existing CPU feature query.

The Linux DevMode compiler passed all 1,751 C++ tests, including the ten SHA
encoding cases. Micro validation passed 13 reference cases. All 12 standard
benchmark checksums and final Micro instructions matched after normalizing
generated names that contain the build path. Cross-emitted Windows COFF includes
the guarded SHA-1 and SHA-256 round instructions. Executed checks ran on Linux.
