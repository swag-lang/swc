#global public

#foreignlib("advapi32")
using Swag

alias ACCESS_MASK = DWORD
alias REGSAM      = ACCESS_MASK
alias HKEY        = const *void?
alias LSTATUS     = LONG

const HKEY_CLASSES_ROOT                = cast(HKEY, cast(u64, 0x80000000))
const HKEY_CURRENT_USER                = cast(HKEY, cast(u64, 0x80000001))
const HKEY_LOCAL_MACHINE               = cast(HKEY, cast(u64, 0x80000002))
const HKEY_USERS                       = cast(HKEY, cast(u64, 0x80000003))
const HKEY_PERFORMANCE_DATA            = cast(HKEY, cast(u64, 0x80000004))
const HKEY_PERFORMANCE_TEXT            = cast(HKEY, cast(u64, 0x80000050))
const HKEY_PERFORMANCE_NLSTEXT         = cast(HKEY, cast(u64, 0x80000060))
const HKEY_CURRENT_CONFIG              = cast(HKEY, cast(u64, 0x80000005))
const HKEY_DYN_DATA                    = cast(HKEY, cast(u64, 0x80000006))
const HKEY_CURRENT_USER_LOCAL_SETTINGS = cast(HKEY, cast(u64, 0x80000007))

const REG_OPTION_NON_VOLATILE = 0x00000000

const KEY_QUERY_VALUE        = 0x0001
const KEY_SET_VALUE          = 0x0002
const KEY_CREATE_SUB_KEY     = 0x0004
const KEY_ENUMERATE_SUB_KEYS = 0x0008
const KEY_NOTIFY             = 0x0010
const KEY_CREATE_LINK        = 0x0020
const KEY_WOW64_32KEY        = 0x0200
const KEY_WOW64_64KEY        = 0x0100
const KEY_WOW64_RES          = 0x0300
const KEY_READ               = 0x00020019

alias PSECURITY_DESCRIPTOR = *void?
const SDDL_REVISION_1 = 1_u32

const REG_NONE                       = 0_u32     // No value type
const REG_SZ                         = 1_u32     // Unicode nul terminated string
const REG_EXPAND_SZ                  = 2_u32     // Unicode nul terminated string
const REG_BINARY                     = 3_u32     // Free form binary
const REG_DWORD                      = 4_u32     // 32-bit number
const REG_DWORD_LITTLE_ENDIAN        = 4_u32     // 32-bit number (same as REG_DWORD)
const REG_DWORD_BIG_ENDIAN           = 5_u32     // 32-bit number
const REG_LINK                       = 6_u32     // Symbolic Link (unicode)
const REG_MULTI_SZ                   = 7_u32     // Multiple Unicode strings
const REG_RESOURCE_LIST              = 8_u32     // Resource list in the resource map
const REG_FULL_RESOURCE_DESCRIPTOR   = 9_u32     // Resource list in the hardware description
const REG_RESOURCE_REQUIREMENTS_LIST = 10_u32
const REG_QWORD                      = 11_u32     // 64-bit number
const REG_QWORD_LITTLE_ENDIAN        = 11_u32     // 64-bit number (same as REG_QWORD)

#[Foreign("advapi32", callconv: Swag.CallConv.C), Swag.Discardable]
{
    func ConvertStringSecurityDescriptorToSecurityDescriptorW(StringSecurityDescriptor: LPCWSTR, StringSDRevision: DWORD, SecurityDescriptor: *PSECURITY_DESCRIPTOR, SecurityDescriptorSize: LPDWORD)->BOOL
    func GetSecurityDescriptorLength(pSecurityDescriptor: PSECURITY_DESCRIPTOR)->DWORD
    func RegCreateKeyExA(hKey: HKEY, lpSubKey: LPCSTR, reserved: DWORD, lpClass: LPSTR?, dwOptions: DWORD, samDesired: REGSAM, lpSecurityAttributes: const *SECURITY_ATTRIBUTES?, hkResult: *HKEY, lpdwDisposition: LPDWORD)->LSTATUS
    func RegCreateKeyExW(hKey: HKEY, lpSubKey: LPCWSTR, reserved: DWORD, lpClass: LPWSTR?, dwOptions: DWORD, samDesired: REGSAM, lpSecurityAttributes: const *SECURITY_ATTRIBUTES?, hkResult: *HKEY, lpdwDisposition: LPDWORD)->LSTATUS
    func RegOpenCurrentUser(samDesired: REGSAM, phkResult: *HKEY)->LSTATUS
    func RegOpenKeyExW(hKey: HKEY, lpSubKey: LPCWSTR, ulOptions: DWORD, samDesired: REGSAM, phkResult: *HKEY)->LSTATUS
    func RegQueryValueExW(hKey: HKEY, lpValueName: LPCWSTR?, lpReserved: *DWORD?, lpType: *DWORD?, lpData: *BYTE?, lpcbData: *DWORD?)->LSTATUS
    func RegSetValueExA(hKey: HKEY, lpValueName: LPCSTR, reserved: DWORD, dwType: DWORD, lpData: const *BYTE?, cbData: DWORD)->LSTATUS
    func RegSetValueExW(hKey: HKEY, lpValueName: LPCWSTR?, reserved: DWORD, dwType: DWORD, lpData: const *BYTE?, cbData: DWORD)->LSTATUS
    func RegCloseKey(hKey: HKEY)->LSTATUS
    func RegDeleteValueW(hKey: HKEY, lpValueName: LPCWSTR)->LSTATUS
}

// Imports `RtlGenRandom` through the `SystemFunction036` export in `advapi32.dll`.
//
// `ntsecapi.h` declares it under that name too; there is no export named `RtlGenRandom`.
#[Foreign("advapi32", "SystemFunction036", callconv: Swag.CallConv.C)]
func RtlGenRandom(RandomBuffer: [*] u8, RandomBufferLength: ULONG)->BOOLEAN
