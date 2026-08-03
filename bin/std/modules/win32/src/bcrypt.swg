#global export

#foreignlib("bcrypt")

using Swag

alias BCRYPT_ALG_HANDLE = #null *void
alias NTSTATUS          = s32

const BCRYPT_USE_SYSTEM_PREFERRED_RNG = 0x00000002'u32

#[Foreign("bcrypt")]
func BCryptGenRandom(hAlgorithm: BCRYPT_ALG_HANDLE, pbBuffer: [*] u8, cbBuffer: ULONG, dwFlags: ULONG)->NTSTATUS
