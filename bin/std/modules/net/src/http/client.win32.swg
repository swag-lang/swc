#global if #os == Swag.TargetOs.Windows
#global internal
#global namespace Http

using Core, Win32

private func queryLocation(request: HINTERNET)->String fail
{
    var length: u32
    if not WinHttpQueryHeaders(request, WINHTTP_QUERY_LOCATION, null, null, &length, null)
    {
        let code = GetLastError()
        if code == ERROR_WINHTTP_HEADER_NOT_FOUND do
            return {}
        if code != ERROR_INSUFFICIENT_BUFFER do
            fail NetworkError{code: cast(s32, code)}
    }

    if length > 8192 or length % 2 != 0 do
        fail Errors.OverflowError{}
    var buffer: Array'u16
    buffer.resize(length / 2)
    if not WinHttpQueryHeaders(request, WINHTTP_QUERY_LOCATION, null, buffer.storage(), &length, null) do
        fail NetworkError{code: cast(s32, GetLastError())}
    return Utf8.fromUtf16(buffer.toSlice()[0 until length / 2])
}

func getNative(host: string, port: u16, path: string, secure = true, options: GetOptions = {})->Response fail
{
    return try requestNative(host, port, path, secure, options, false)
}

func postNative(host: string, port: u16, path: string, secure: bool, options: PostOptions)->Response fail
{
    return try requestNative(host, port, path, secure, options, true)
}

private func writeRequestBody(request: HINTERNET, options: PostOptions) fail
{
    var remaining = options.requestBodyLength
    var chunk: [8192] u8
    while remaining > 0
    {
        let requested = Math.min(remaining, chunk.count)
        let reader    = unwrap options.bodyReader
        let read      = reader(options.requestContext, chunk[until requested])
        if read == 0 or read > requested do
            fail NetworkError{"HTTP request body reader did not provide its declared length", code: 0}

        var offset = 0'u64
        while offset < read
        {
            var written: u32
            let count = cast(u32, read - offset)
            if not WinHttpWriteData(request, &chunk[offset], count, &written) do
                fail NetworkError{code: cast(s32, GetLastError())}
            if written == 0 do
                fail NetworkError{"HTTP transport stopped accepting request bytes", code: 0}
            offset += written
        }

        remaining -= read
    }
}

private func requestNative(host: string, port: u16, path: string, secure: bool, options: GetOptions, post: bool)->Response fail
{
    var headers: String
    for header in options.headers
    {
        headers += header.name
        headers += ": "
        headers += header.value
        headers += "\r\n"
    }

    let agent         = Utf16.toZeroTerminated(options.userAgent)
    let server        = Utf16.toZeroTerminated(host)
    let objectName    = Utf16.toZeroTerminated(path)
    let nativeHeaders = Utf16.toZeroTerminated(headers)
    let verb          = Utf16.toZeroTerminated(post ? "POST" : "GET")
    let session       = WinHttpOpen(agent.buffer, WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, null, null, 0)
    if not session do
        fail NetworkError{code: cast(s32, GetLastError())}
    defer discard WinHttpCloseHandle(session)

    let timeout = cast(s32, options.timeoutMs)
    if not WinHttpSetTimeouts(session, timeout, timeout, timeout, timeout) do
        fail NetworkError{code: cast(s32, GetLastError())}
    let connection = WinHttpConnect(session, server.buffer, port, 0)
    if not connection do
        fail NetworkError{code: cast(s32, GetLastError())}
    defer discard WinHttpCloseHandle(connection)
    let request = WinHttpOpenRequest(connection, verb.buffer, objectName.buffer, null, null, null, secure ? WINHTTP_FLAG_SECURE : 0)
    if not request do
        fail NetworkError{code: cast(s32, GetLastError())}
    defer discard WinHttpCloseHandle(request)

    if not WinHttpSetTimeouts(request, timeout, timeout, timeout, timeout) do
        fail NetworkError{code: cast(s32, GetLastError())}
    var responseTimeout = options.timeoutMs
    if not WinHttpSetOption(request, WINHTTP_OPTION_RECEIVE_RESPONSE_TIMEOUT, &responseTimeout, #sizeof(u32)) do
        fail NetworkError{code: cast(s32, GetLastError())}

    var redirectPolicy = WINHTTP_OPTION_REDIRECT_POLICY_NEVER
    if options.maxRedirects > 0 do
        redirectPolicy = WINHTTP_OPTION_REDIRECT_POLICY_ALWAYS | WINHTTP_OPTION_REDIRECT_POLICY_DISALLOW_HTTPS_TO_HTTP
    if not WinHttpSetOption(request, WINHTTP_OPTION_REDIRECT_POLICY, &redirectPolicy, #sizeof(u32)) do
        fail NetworkError{code: cast(s32, GetLastError())}
    if options.maxRedirects > 0
    {
        var maximumRedirects = cast(u32, options.maxRedirects)
        if not WinHttpSetOption(request, WINHTTP_OPTION_MAX_HTTP_AUTOMATIC_REDIRECTS, &maximumRedirects, #sizeof(u32)) do
            fail NetworkError{code: cast(s32, GetLastError())}
    }

    let bodyLength = post ? cast(u32, options.requestBodyLength) : 0'u32
    if not WinHttpSendRequest(request, nativeHeaders.buffer, Swag.U32.Max, null, 0, bodyLength, 0) do
        fail NetworkError{code: cast(s32, GetLastError())}
    if post and options.requestBodyLength > 0 do
        try writeRequestBody(request, options)
    if not WinHttpReceiveResponse(request, null) do
        fail NetworkError{code: cast(s32, GetLastError())}

    var result: Response
    var statusSize = cast(u32, #sizeof(u32))
    if not WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, null, &result.status, &statusSize, null) do
        fail NetworkError{code: cast(s32, GetLastError())}
    result.location = try queryLocation(request)

    var chunk: [8192] u8
    var bodyBytes = 0'u64
    while true
    {
        var received: u32
        if not WinHttpReadData(request, &chunk[0], chunk.count, &received) do
            fail NetworkError{code: cast(s32, GetLastError())}
        if received == 0 do
            break
        if received > options.maxBodyBytes - Math.min(options.maxBodyBytes, bodyBytes) do
            fail Errors.OverflowError{}
        bodyBytes += received
        if options.bodyHandler
        {
            if not options.bodyHandler(options.bodyContext, chunk[0 until received]) do
                fail NetworkError{"HTTP response body handler stopped the transfer", code: 995}
        }
        else
        {
            result.body.add(chunk[0 until received])
        }
    }

    return result
}
