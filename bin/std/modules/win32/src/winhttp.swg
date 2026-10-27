#global export

#foreignlib("winhttp")
using Swag

alias HINTERNET     = const *void?
alias INTERNET_PORT = u16

const WINHTTP_ACCESS_TYPE_DEFAULT_PROXY       = 0
const WINHTTP_FLAG_SECURE                     = 0x00800000'u32
const WINHTTP_OPTION_REDIRECT_POLICY          = 88'u32
const WINHTTP_OPTION_RECEIVE_RESPONSE_TIMEOUT = 7'u32
const WINHTTP_OPTION_REDIRECT_POLICY_NEVER    = 0'u32
const WINHTTP_QUERY_STATUS_CODE               = 19'u32
const WINHTTP_QUERY_LOCATION                  = 33'u32
const WINHTTP_QUERY_FLAG_NUMBER               = 0x20000000'u32
const ERROR_WINHTTP_HEADER_NOT_FOUND          = 12150'u32

#[Foreign("winhttp", callconv: Swag.CallConv.C)]
{
    func WinHttpOpen(agent: LPCWSTR, accessType: DWORD, proxy, bypass: LPCWSTR, flags: DWORD)->HINTERNET
    func WinHttpConnect(session: HINTERNET, server: LPCWSTR, port: INTERNET_PORT, reserved: DWORD)->HINTERNET
    func WinHttpOpenRequest(connection: HINTERNET, verb, objectName, version, referrer: LPCWSTR, acceptTypes: const [*] LPCWSTR?, flags: DWORD)->HINTERNET
    func WinHttpSetTimeouts(handle: HINTERNET, resolveTimeout, connectTimeout, sendTimeout, receiveTimeout: s32)->BOOL
    func WinHttpSetOption(handle: HINTERNET, option: DWORD, buffer: LPVOID, length: DWORD)->BOOL
    func WinHttpSendRequest(request: HINTERNET, headers: LPCWSTR, headersLength: DWORD, optional: LPVOID, optionalLength, totalLength: DWORD, context: DWORD_PTR)->BOOL
    func WinHttpReceiveResponse(request: HINTERNET, reserved: LPVOID)->BOOL
    func WinHttpQueryHeaders(request: HINTERNET, infoLevel: DWORD, name: LPCWSTR, buffer: LPVOID, bufferLength, index: LPDWORD)->BOOL
    func WinHttpReadData(request: HINTERNET, buffer: LPVOID, bytesToRead: DWORD, bytesRead: LPDWORD)->BOOL
    func WinHttpCloseHandle(handle: HINTERNET)->BOOL
}
