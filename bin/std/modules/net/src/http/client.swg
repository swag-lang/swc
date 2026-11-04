#global public
#global namespace Http

using Core

// Issues a bounded HTTP or HTTPS GET to `host`, `port` and an absolute request `path`.
//
// `path` must be absolute, fragment-free and already percent-encoded. HTTPS verifies the
// peer's certificate and host name using the platform trust store. On Linux, libcurl supplies
// system trust roots; `SSL_CERT_FILE` and `SSL_CERT_DIR` can override the CA file/directory.
// Linux needs `libcurl.so.4` with thread-safe initialization and asynchronous DNS support.
// Its proxy environment variables, including `NO_PROXY`, retain libcurl's native behavior.
// Redirects are returned without being followed. WinHTTP applies `timeoutMs` per phase,
// with coarse enforcement; Linux applies it to the whole transfer, including connection setup.
// The synchronous operation cannot be cancelled while a native call is blocked.
// The result owns its body and includes non-success status codes. Invalid input, transport
// errors, and responses exceeding limits fail without returning a partial result. Linux limits
// total response headers to 64 KiB and Location to 4096 bytes; Windows limits Location to
// 8192 bytes of UTF-16 storage. Linux transport failures use libcurl codes in [[Net.NetworkError]].
//
// ```swag
// #import("net")
// using Core, Net
//
// #main
// {
//     let target = try Url.parseHttp("https://example.com/")
//     let response = try Http.get(target.host, target.port, target.path, target.secure)
//     Console.println(response.status)
// }
// ```
func get(host: string, port: u16, path: string, secure = true, options: GetOptions = {})->Response fail
{
    if host.count == 0 or
       port == 0 or
       path.count == 0 or
       path[0] != '/' or
       options.timeoutMs == 0 or
       options.timeoutMs > Swag.S32.Max do
        fail Errors.BadParameterError{}
    for c in host where c <= ' ' or c == 0x7F do
        fail Errors.BadParameterError{}
    for c in path where c <= ' ' or c == 0x7F or c == '#' do
        fail Errors.BadParameterError{}
    for c in options.userAgent where c < ' ' or c == 0x7F do
        fail Errors.BadParameterError{}

    for header in options.headers
    {
        if header.name.count == 0 do
            fail Errors.BadParameterError{}
        for c in header.name
        {
            if not ((c >= 'a' and c <= 'z') or
                    (c >= 'A' and c <= 'Z') or
                    (c >= '0' and c <= '9') or
                    Utf8.indexOf("!#$%&'*+-.^_`|~", cast(rune, c)) != Swag.U64.Max) do
                fail Errors.BadParameterError{}
        }

        for c in header.value where c < ' ' or c == 0x7F do
            fail Errors.BadParameterError{}
    }

    return try getNative(host, port, path, secure, options)
}
