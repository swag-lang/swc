#global public
#global namespace Http

using Core

// Bounds one HTTP server connection's request headers and decoded body.
struct ServerOptions
{
    public
    {
        maxHeaderBytes:             u64 = 64 * 1024     // Maximum request line, header fields, and trailers.
        maxBodyBytes:               u64 = 4 * 1024 * 1024 // Maximum decoded request body.
        maxRequestsPerConnection:   u32 = 1              // Maximum requests served on one connection; values above one require an idle timeout.
        idleTimeoutMs:              u32                  // Maximum time for each blocking read in milliseconds; zero disables it.
    }
}

// A parsed HTTP/1.0 or HTTP/1.1 request with an owned, bounded body.
struct ServerHeader
{
    public
    {
        name:  String // Owned field name.
        value: String // Owned field value.
    }
}

// A parsed request whose headers and bounded body are owned by the value.
struct ServerRequest
{
    public
    {
        method:  String         // Request method token.
        target:  String         // Origin-form request target.
        version: String         // `HTTP/1.0` or `HTTP/1.1`.
        headers: Array'ServerHeader // Request headers in wire order.
        body:    Array'u8       // Request body after Content-Length or chunked decoding.
    }
}

// Owns a blocking HTTP listener with bounded per-connection request policies.
#[Swag.NoCopy]
struct Server
{
    listener: TcpListener
    options:  ServerOptions
}

// Owns one HTTP connection; its request limit and idle timeout come from its server.
#[Swag.NoCopy]
struct ServerConnection
{
    stream:          TcpStream
    options:         ServerOptions
    responseStarted: bool
    responseFinished: bool
    input:            [4096] u8
    inputOffset:      u64
    inputCount:       u64
    requestsServed:   u32
    requestPending:   bool
    requestKeepAlive: bool
}

private func httpTokenByte(value: u8)->bool
{
    return (value >= 'a' and value <= 'z') or
           (value >= 'A' and value <= 'Z') or
           (value >= '0' and value <= '9') or
           Utf8.indexOf("!#$%&'*+-.^_`|~", cast(rune, value)) != Swag.U64.Max
}

private func httpHeaderNameEquals(name: string, expected: string)->bool
{
    return name.count == expected.count and Utf8.indexOf(name, expected, 0, .Latin1NoCase) == 0
}

private func httpHeaderContainsToken(value: string, token: string)->bool
{
    var start = 0'u64
    while start < value.count
    {
        let separator = Utf8.indexOf(value, ",", start)
        let end = separator == Swag.U64.Max ? value.count : separator
        let part = Latin1.trim(value[start until end])
        if part.count == token.count and Utf8.indexOf(part, token, 0, .Latin1NoCase) == 0 do
            return true
        if separator == Swag.U64.Max do
            break
        start = separator + 1
    }
    return false
}

private func httpReasonPhrase(status: u32)->string
{
    switch status
    {
    case 200: return "OK"
    case 201: return "Created"
    case 204: return "No Content"
    case 301: return "Moved Permanently"
    case 302: return "Found"
    case 304: return "Not Modified"
    case 400: return "Bad Request"
    case 401: return "Unauthorized"
    case 403: return "Forbidden"
    case 404: return "Not Found"
    case 405: return "Method Not Allowed"
    case 413: return "Payload Too Large"
    case 415: return "Unsupported Media Type"
    case 426: return "Upgrade Required"
    case 500: return "Internal Server Error"
    case 501: return "Not Implemented"
    case 503: return "Service Unavailable"
    default: return "Response"
    }
}

private struct HeaderByteCount
{
    value: u64
}

impl Server
{
    // Binds a blocking HTTP listener for IPv4 or IPv6 requests.
    //
    // Connections serve one request by default. A larger request limit requires a nonzero
    // `idleTimeoutMs`, which bounds each blocking read while parsing requests.
    func listen(endpoint: SocketEndpoint, options: ServerOptions = {})->Server fail
    {
        if options.maxHeaderBytes < 16 or options.maxRequestsPerConnection == 0 or
           options.maxRequestsPerConnection > 1 and options.idleTimeoutMs == 0 do
            fail Errors.BadParameterError{}
        var listener = try TcpListener.listen(endpoint)
        return {listener: #move listener, options: options}
    }

    // Binds an IPv4 HTTP listener.
    func listen(endpoint: Endpoint, options: ServerOptions = {})->Server fail
    {
        return try .listen(endpoint.toSocketEndpoint(), options)
    }

    // Returns the bound local IPv4 or IPv6 address and port.
    mtd localAddress()->SocketEndpoint fail => try .listener.localAddress()

    // Stops accepting new connections; connections already returned by `accept` remain owned by callers.
    mtd close() => .listener.close()

    // Blocks until a peer connects and returns an independently owned connection.
    mtd accept()->ServerConnection fail
    {
        var stream = try .listener.accept()
        if .options.idleTimeoutMs do
            try stream.setReadTimeout(.options.idleTimeoutMs)
        return {stream: #move stream, options: .options}
    }
}

impl ServerConnection
{
    // Closes the connection; repeated calls do nothing.
    mtd close() => .stream.close()

    // Closes the connection when this owner is dropped.
    mtd opDrop() { .close() }

    private mtd readByte()->u8 fail
    {
        if .inputOffset == .inputCount
        {
            .inputOffset = 0
            .inputCount = try .stream.read(.input)
            if .inputCount == 0 do
                fail Errors.InvalidFormatError{"unexpected end of HTTP request"}
        }
        let byte = .input[.inputOffset]
        .inputOffset += 1
        return byte
    }

    private mtd readLine(maxBytes: u64)->String fail
    {
        var line: String
        while line.count <= maxBytes
        {
            let value = try .readByte()
            if value == '\r'
            {
                if try .readByte() != '\n' do
                    fail Errors.InvalidFormatError{"HTTP lines must end with CRLF"}
                return line
            }
            if value == '\n' or value < ' ' and value != '\t' or value == 0x7F do
                fail Errors.InvalidFormatError{"HTTP line contains a control character"}
            line.append(value)
        }
        fail Errors.OverflowError{"HTTP request headers exceed the configured limit"}
    }

    private mtd readExact(buffer: [..] u8) fail
    {
        var offset = 0'u64
        while offset < buffer.count
        {
            if .inputOffset < .inputCount
            {
                let count = Math.min(buffer.count - offset, .inputCount - .inputOffset)
                Memory.copy(buffer.buffer + offset, .input.buffer + .inputOffset, count)
                .inputOffset += count
                offset += count
                continue
            }
            let count = try .stream.read(buffer[offset to])
            if count == 0 do
                fail Errors.InvalidFormatError{"HTTP request body ended early"}
            offset += count
        }
    }

    private mtd readChunkedBody(request: *ServerRequest, headerBytes: *HeaderByteCount) fail
    {
        for
        {
            let line = try .readLine(128)
            headerBytes.value += line.count + 2
            if headerBytes.value > .options.maxHeaderBytes do
                fail Errors.OverflowError{"HTTP request headers exceed the configured limit"}
            let separator = Utf8.indexOf(line, ";")
            let sizeText = separator == Swag.U64.Max ? line.toString() : line[until separator]
            let parsedSize = catch StrConv.parseX64(sizeText) { fail Errors.InvalidFormatError{"invalid HTTP chunk size"} }
            if parsedSize.ovf or parsedSize.eat != sizeText.count do
                fail Errors.InvalidFormatError{"invalid HTTP chunk size"}
            let size = parsedSize.value
            if size == 0
            {
                for
                {
                    let trailer = try .readLine(.options.maxHeaderBytes - Math.min(.options.maxHeaderBytes, headerBytes.value))
                    headerBytes.value += trailer.count + 2
                    if headerBytes.value > .options.maxHeaderBytes do
                        fail Errors.OverflowError{"HTTP request headers exceed the configured limit"}
                    if trailer.isEmpty() do
                        return
                    let colon = Utf8.indexOf(trailer, ":")
                    if colon == 0 or colon == Swag.U64.Max do
                        fail Errors.InvalidFormatError{"invalid HTTP trailer field"}
                    let name = trailer[until colon]
                    for byte in name do
                        if not httpTokenByte(byte) do
                            fail Errors.InvalidFormatError{"invalid HTTP trailer name"}
                    if httpHeaderNameEquals(name, "content-length") or
                       httpHeaderNameEquals(name, "transfer-encoding") or
                       httpHeaderNameEquals(name, "host") do
                        fail Errors.InvalidFormatError{"forbidden HTTP trailer field"}
                    for byte in trailer[colon + 1 to] do
                        if (byte < ' ' and byte != '\t') or byte == 0x7F do
                            fail Errors.InvalidFormatError{"invalid HTTP trailer value"}
                }
            }

            if size > .options.maxBodyBytes - Math.min(.options.maxBodyBytes, request.body.count) do
                fail Errors.OverflowError{"HTTP request body exceeds the configured limit"}
            let start = request.body.count
            request.body.resize(start + size)
            try .readExact(request.body[start to])
            if try .readByte() != '\r' or try .readByte() != '\n' do
                fail Errors.InvalidFormatError{"HTTP chunk is not followed by CRLF"}
        }
    }

    // Reads and validates one bounded request, including Content-Length and chunked bodies.
    mtd readRequest()->ServerRequest fail
    {
        if .responseStarted or .requestPending do
            fail Errors.BadParameterError{}
        var request: ServerRequest
        var headerBytes = HeaderByteCount{}
        let requestLine = try .readLine(.options.maxHeaderBytes)
        headerBytes.value = requestLine.count + 2
        let firstSpace = Utf8.indexOf(requestLine, " ")
        let secondSpace = firstSpace == Swag.U64.Max ? firstSpace : Utf8.indexOf(requestLine, " ", firstSpace + 1)
        if firstSpace == 0 or secondSpace == Swag.U64.Max or secondSpace + 1 >= requestLine.count do
            fail Errors.InvalidFormatError{"invalid HTTP request line"}
        let method = requestLine[until firstSpace]
        for value in method do
            if not httpTokenByte(value) do
                fail Errors.InvalidFormatError{"invalid HTTP method"}
        let target = requestLine[firstSpace + 1 until secondSpace]
        let version = requestLine[secondSpace + 1 to]
        if target.count == 0 or target[0] != '/' or (version != "HTTP/1.0" and version != "HTTP/1.1") do
            fail Errors.InvalidFormatError{"unsupported HTTP request target or version"}
        request.method = String.from(method)
        request.target = String.from(target)
        request.version = String.from(version)

        var hasContentLength = false
        var contentLength = 0'u64
        var isChunked = false
        var connectionClose = false
        var connectionKeepAlive = false
        for
        {
            let line = try .readLine(.options.maxHeaderBytes - Math.min(.options.maxHeaderBytes, headerBytes.value))
            headerBytes.value += line.count + 2
            if headerBytes.value > .options.maxHeaderBytes do
                fail Errors.OverflowError{"HTTP request headers exceed the configured limit"}
            if line.isEmpty() do
                break
            if line[0] == ' ' or line[0] == '\t' do
                fail Errors.InvalidFormatError{"obsolete folded HTTP headers are not accepted"}
            let colon = Utf8.indexOf(line, ":")
            if colon == 0 or colon == Swag.U64.Max do
                fail Errors.InvalidFormatError{"invalid HTTP header field"}
            let name = line[until colon]
            for value in name do
                if not httpTokenByte(value) do
                    fail Errors.InvalidFormatError{"invalid HTTP header name"}
            let value = Latin1.trim(line[colon + 1 to])
            for byte in value do
                if byte < ' ' and byte != '\t' or byte == 0x7F do
                    fail Errors.InvalidFormatError{"invalid HTTP header value"}
            if httpHeaderNameEquals(name, "content-length")
            {
                let parsed = catch StrConv.toU64(value) { fail Errors.InvalidFormatError{"invalid HTTP Content-Length"} }
                if hasContentLength and parsed != contentLength do
                    fail Errors.InvalidFormatError{"conflicting HTTP Content-Length fields"}
                hasContentLength = true
                contentLength = parsed
            }
            elif httpHeaderNameEquals(name, "transfer-encoding")
            {
                if isChunked or Utf8.indexOf(value, "chunked", 0, .Latin1NoCase) != 0 or value.count != 7 do
                    fail Errors.InvalidFormatError{"unsupported HTTP Transfer-Encoding"}
                isChunked = true
            }
            elif httpHeaderNameEquals(name, "connection")
            {
                connectionClose = connectionClose or httpHeaderContainsToken(value, "close")
                connectionKeepAlive = connectionKeepAlive or httpHeaderContainsToken(value, "keep-alive")
            }
            request.headers.add({name: String.from(name), value: String.from(value)})
        }

        if isChunked and hasContentLength do
            fail Errors.InvalidFormatError{"HTTP request cannot combine Transfer-Encoding and Content-Length"}
        if isChunked
        {
            try .readChunkedBody(&request, &headerBytes)
        }
        else
        {
            if contentLength > .options.maxBodyBytes do
                fail Errors.OverflowError{"HTTP request body exceeds the configured limit"}
            request.body.resize(contentLength)
            try .readExact(request.body.toSlice())
        }

        .requestsServed += 1
        .requestPending = true
        .requestKeepAlive = .requestsServed < .options.maxRequestsPerConnection and
                            not connectionClose and
                            (version == "HTTP/1.1" or connectionKeepAlive)
        return request
    }

    private mtd writeAll(bytes: const [..] u8) fail
    {
        var offset = 0'u64
        while offset < bytes.count
        {
            let count = try .stream.write(bytes[offset to])
            if count == 0 do
                fail NetworkError{"HTTP connection stopped accepting response bytes", code: 0}
            offset += count
        }
    }

    private mtd validateResponseHeaders(headers: const [..] Header) fail
    {
        for header in headers
        {
            if header.name.count == 0 or httpHeaderNameEquals(header.name, "content-length") or
               httpHeaderNameEquals(header.name, "transfer-encoding") or
               httpHeaderNameEquals(header.name, "connection") do
                fail Errors.BadParameterError{}
            for value in header.name do
                if not httpTokenByte(value) do
                    fail Errors.BadParameterError{}
            for value in header.value do
                if (value < ' ' and value != '\t') or value == 0x7F do
                    fail Errors.BadParameterError{}
        }
    }

    private mtd writeResponseHead(status: u32, headers: const [..] Header, chunked: bool, bodyLength: u64) fail
    {
        if not .requestPending or .responseStarted or status < 200 or status > 599 do
            fail Errors.BadParameterError{}
        try .validateResponseHeaders(headers)
        var text = Format.toString("HTTP/1.1 % %\r\n", status, httpReasonPhrase(status))
        for header in headers do
            text += Format.toString("%: %\r\n", header.name, header.value)
        if chunked
        {
            text += "Transfer-Encoding: chunked\r\n"
        }
        else do
            text += Format.toString("Content-Length: %\r\n", bodyLength)
        text += .requestKeepAlive ? "Connection: keep-alive\r\n\r\n" : "Connection: close\r\n\r\n"
        try .writeAll(cast(const [..] u8, text))
        .responseStarted = true
    }

    // Writes a complete response with a known body length and applies the connection policy.
    mtd respond(status: u32, body: const [..] u8, headers: const [..] Header = []) fail
    {
        try .writeResponseHead(status, headers, false, body.count)
        try .writeAll(body)
        .completeResponse()
    }

    // Starts a chunked response for a body whose length is not known in advance.
    mtd beginChunkedResponse(status: u32, headers: const [..] Header = []) fail
    {
        try .writeResponseHead(status, headers, true, 0)
    }

    // Completes an RFC 6455 upgrade and transfers this connection to a WebSocket owner.
    mtd upgradeWebSocket(request: ServerRequest, options: WebSocketOptions = {})->WebSocket fail
    {
        if not .requestPending or .responseStarted do
            fail Errors.BadParameterError{}
        let accept = try webSocketValidateUpgrade(request)
        let response = Format.toString("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %\r\n\r\n", accept)
        try .writeAll(cast(const [..] u8, response))
        .responseStarted = true
        .requestPending = false
        var result = WebSocket{stream: #move .stream, side: .Server, options: options,
                               input: #move .input, inputOffset: .inputOffset, inputCount: .inputCount, open: true}
        .inputOffset = .inputCount
        return result
    }

    // Writes one chunk of a response started by [[Net.Http.ServerConnection.beginChunkedResponse]].
    mtd writeBody(bytes: const [..] u8) fail
    {
        if not .responseStarted or .responseFinished do
            fail Errors.BadParameterError{}
        if bytes.count == 0 do
            return
        let prefix = Format.toString("%{X}\r\n", bytes.count)
        try .writeAll(cast(const [..] u8, prefix))
        try .writeAll(bytes)
        try .writeAll(cast(const [..] u8, "\r\n"))
    }

    // Completes the chunked response and applies the connection policy.
    mtd finishResponse() fail
    {
        if not .responseStarted or .responseFinished do
            fail Errors.BadParameterError{}
        try .writeAll(cast(const [..] u8, "0\r\n\r\n"))
        .completeResponse()
    }

    private mtd completeResponse()
    {
        .responseFinished = true
        .requestPending = false
        if .requestKeepAlive
        {
            .responseStarted = false
            .responseFinished = false
            .requestKeepAlive = false
        }
        else do
            .stream.close()
    }
}
