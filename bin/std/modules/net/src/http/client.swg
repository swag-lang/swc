#global public
#global namespace Http

using Core

// Issues a bounded HTTP or HTTPS GET to `host`, `port` and an absolute request `path`. For IPv6,
// pass the unbracketed address, such as `::1`; [[Net.Url.parseHttp]] returns it in this form.
//
// `path` must be absolute, fragment-free and already percent-encoded. HTTPS verifies the
// peer's certificate and host name using the platform trust store. On Linux, libcurl supplies
// system trust roots; `SSL_CERT_FILE` and `SSL_CERT_DIR` can override the CA file/directory.
// Linux needs `libcurl.so.4` with thread-safe initialization and asynchronous DNS support.
// Its proxy environment variables, including `NO_PROXY`, retain libcurl's native behavior.
// Redirects are returned without being followed unless `maxRedirects` is nonzero. Redirect
// following is GET-only, limited to HTTP and HTTPS, and HTTPS requests cannot downgrade to HTTP.
// Do not combine redirect following with Host, Authorization, Cookie, or Proxy-Authorization
// headers because those values could be sent to another origin. WinHTTP applies `timeoutMs` per phase,
// with coarse enforcement; Linux applies it to the whole transfer, including connection setup.
// The synchronous operation cannot be cancelled while a native call is blocked.
// The result owns its body and includes non-success status codes. When `bodyHandler` is supplied,
// it receives body chunks during the transfer and `Response.body` remains empty. All final
// response headers are returned in received order, preserving duplicate names; `Response.location`
// contains the first Location value. Returning false
// stops the transfer and reports a network error. Invalid input, transport errors, a reached
// redirect limit, and responses exceeding limits fail without returning a partial result. Linux limits
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
    try validateHttpRequest(host, port, path, options, false)
    return try getNative(host, port, path, secure, options)
}

// Issues a bounded POST with a request body produced incrementally by `bodyReader`.
//
// `requestBodyLength` is exact; the reader must provide that many bytes. The callback receives
// writable chunks and its state is borrowed for the duration of the call. A missing reader is
// valid only for an empty body. POST requests do not follow redirects; `maxRedirects` must be
// zero. Response handling, certificate validation, timeouts, and cancellation follow
// [[Net.Http.get]].
func post(host: string, port: u16, path: string, secure = true, options: PostOptions = {})->Response fail
{
    try validateHttpRequest(host, port, path, options, true)
    if options.requestBodyLength > Swag.U32.Max or
       options.requestBodyLength != 0 and
       not options.bodyReader do
        fail Errors.BadParameterError{}
    return try postNative(host, port, path, secure, options)
}

private func validateHttpRequest(host: string, port: u16, path: string, options: GetOptions, hasRequestBody: bool) fail
{
    if host.count == 0 or
       port == 0 or
       path.count == 0 or
       path[0] != '/' or
       not isValidRequestPath(path) or
       options.timeoutMs == 0 or
       options.timeoutMs > Swag.S32.Max or
       options.maxRedirects > 10 or
       hasRequestBody and
       options.maxRedirects > 0 do
        fail Errors.BadParameterError{}
    for c in host where c <= ' ' or c == 0x7F do
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
        let isContentLength = header.name.count == 14 and
                              Utf8.indexOf(header.name, "content-length", 0, .Latin1NoCase) == 0
        let isTransferEncoding = header.name.count == 17 and
                                 Utf8.indexOf(header.name, "transfer-encoding", 0, .Latin1NoCase) == 0
        let isRedirectSensitive =
            (header.name.count == 4 and Utf8.indexOf(header.name, "host", 0, .Latin1NoCase) == 0) or
            (header.name.count == 13 and Utf8.indexOf(header.name, "authorization", 0, .Latin1NoCase) == 0) or
            (header.name.count == 6 and Utf8.indexOf(header.name, "cookie", 0, .Latin1NoCase) == 0) or
            (header.name.count == 19 and Utf8.indexOf(header.name, "proxy-authorization", 0, .Latin1NoCase) == 0)
        if hasRequestBody and (isContentLength or isTransferEncoding) do
            fail Errors.BadParameterError{}
        if options.maxRedirects > 0 and isRedirectSensitive do
            fail Errors.BadParameterError{}
    }
}

// The caller supplies the request target, so it must already use valid ASCII URI syntax with
// complete percent escapes before either native HTTP backend sees it.
private func isValidRequestPath(path: string)->bool
{
    var index = 0'u64
    while index < path.count
    {
        let c = path[index]
        if not ((c >= 'a' and c <= 'z') or
                (c >= 'A' and c <= 'Z') or
                Latin1.isDigit(c) or
                Utf8.indexOf("-._~:/?@!$&'()*+,;=%", cast(rune, c)) != Swag.U64.Max) do
            return false

        if c == '%'
        {
            if path.count - index < 3 or
               not Latin1.isHexDigit(path[index + 1]) or
               not Latin1.isHexDigit(path[index + 2]) do
                return false
            index += 2
        }

        index += 1
    }

    return true
}

private struct ResponseHeaderParser
{
    lastHeaderIndex:     u64
    locationHeaderIndex: u64
    overflow:            bool
}

private func appendResponseHeader(response: *Response, parser: *ResponseHeaderParser, line: string)->bool
{
    var end = line.count
    while end > 0 and (line[end - 1] == '\r' or line[end - 1] == '\n') do
        end -= 1
    let text = line[0 until end]
    if text.count == 0 do
        return true
    if text[0] == ' ' or text[0] == '\t'
    {
        if parser.lastHeaderIndex == Swag.U64.Max do
            return false
        var start = 0'u64
        while start < text.count and (text[start] == ' ' or text[start] == '\t') do
            start += 1
        while end > start and (text[end - 1] == ' ' or text[end - 1] == '\t') do
            end -= 1
        if end == start do
            return true
        let value  = text[start until end]
        let header = &response.headers[parser.lastHeaderIndex]
        if header.value.count + 1 + value.count > 65536
        {
            parser.overflow = true
            return false
        }

        if not header.value.isEmpty() do
            header.value += " "
        header.value += value
        if parser.lastHeaderIndex == parser.locationHeaderIndex
        {
            if response.location.count + 1 + value.count > 4096
            {
                parser.overflow = true
                return false
            }

            if not response.location.isEmpty() do
                response.location += " "
            response.location += value
        }

        return true
    }

    let colon = Utf8.indexOf(text, ':')
    if colon == Swag.U64.Max or colon == 0 do
        return false
    let name = text[0 until colon]
    for c in name
    {
        if not ((c >= 'a' and c <= 'z') or
                (c >= 'A' and c <= 'Z') or
                (c >= '0' and c <= '9') or
                Utf8.indexOf("!#$%&'*+-.^_`|~", cast(rune, c)) != Swag.U64.Max) do
            return false
    }

    var start = colon + 1
    end = text.count
    while start < end and (text[start] == ' ' or text[start] == '\t') do
        start += 1
    while end > start and (text[end - 1] == ' ' or text[end - 1] == '\t') do
        end -= 1
    let value = text[start until end]
    for c in value where (c < ' ' and c != '\t') or c == 0x7F do
        return false
    response.headers.add({name: String.from(name), value: String.from(value)})
    parser.lastHeaderIndex = response.headers.count - 1
    if name.count == 8 and
       Utf8.indexOf(name, "location", 0, .Latin1NoCase) == 0 and
       parser.locationHeaderIndex == Swag.U64.Max
    {
        if value.count > 4096
        {
            parser.overflow = true
            return false
        }

        response.location = String.from(value)
        parser.locationHeaderIndex = response.headers.count - 1
    }

    return true
}

private func parseResponseHeaders(raw: string, response: *Response) fail
{
    if raw.count > 65536 do
        fail Errors.OverflowError{}
    var parser = ResponseHeaderParser{lastHeaderIndex: Swag.U64.Max,
                                      locationHeaderIndex: Swag.U64.Max}
    var inHeaders = false
    var lineStart = 0'u64
    var index     = 0'u64
    while index < raw.count
    {
        if raw[index] == '\n'
        {
            let line = raw[lineStart until index + 1]
            if Utf8.startsWith(line, "HTTP/")
            {
                response.headers.clear()
                response.location.clear()
                parser.lastHeaderIndex     = Swag.U64.Max
                parser.locationHeaderIndex = Swag.U64.Max
                inHeaders = true
            }
            elif line == "\r\n" or line == "\n"
            {
                inHeaders = false
                parser.lastHeaderIndex = Swag.U64.Max
            }
            elif inHeaders and not appendResponseHeader(response, &parser, line)
            {
                if parser.overflow do
                    fail Errors.OverflowError{}
                fail NetworkError{"malformed HTTP response header", code: 0}
            }

            lineStart = index + 1
        }

        index += 1
    }

    if lineStart < raw.count and
       inHeaders and
       not appendResponseHeader(response, &parser, raw[lineStart to])
    {
        if parser.overflow do
            fail Errors.OverflowError{}
        fail NetworkError{"malformed HTTP response header", code: 0}
    }
}
