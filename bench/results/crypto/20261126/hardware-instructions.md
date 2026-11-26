# CPU feature discovery and AES instructions

Swag can query the running CPU and guard AES, carry-less multiplication and SHA
instruction paths. The runtime caches CPUID results in one atomic word. AES block
rounds and key operations have typed packed-vector instructions.

The Linux DevMode compiler passed all 1,751 C++ tests, including x64 encoding cases.
The CPUID and AES native vector cases passed with Micro validation. The complete
Linux language reference passed with the Release compiler, and the VS Code grammar
parsed successfully. The supported spelling and examples are in the reference.

The 12 standard benchmark programs all reproduced their checksums and their timed
Micro functions were identical. On Windows, cross-emitted PE/COFF assembly verified
CPUID and preservation of the nonvolatile RBX register. Executed tests ran on Linux.
