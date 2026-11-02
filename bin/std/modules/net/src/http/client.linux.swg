#global if #os == Swag.TargetOs.Linux
#global namespace Http

using Core

private struct CurlLibrary
{
    library:       NativeLibrary
    globalInit:    Curl.curl_global_init_fn
    globalCleanup: Curl.curl_global_cleanup_fn
    versionInfo:   Curl.curl_version_info_fn
    easyInit:      Curl.curl_easy_init_fn
    easyCleanup:   Curl.curl_easy_cleanup_fn
    setOption:     Curl.curl_easy_setopt_fn
    getInfo:       Curl.curl_easy_getinfo_fn
    perform:       Curl.curl_easy_perform_fn
    appendHeader:  Curl.curl_slist_append_fn
    freeHeaders:   Curl.curl_slist_free_all_fn
    createUrl:     Curl.curl_url_fn
    freeUrl:       Curl.curl_url_cleanup_fn
    setUrlPart:    Curl.curl_url_set_fn
}

private var g_Curl:      CurlLibrary
private var g_CurlReady: bool
private var g_CurlMutex: Swag.Mutex

private func checkCurl(code: s32) fail
{
    if code != Curl.CURLE_OK do
        fail NetworkError{code: code}
}

private func ensureCurl()->*CurlLibrary fail
{
    func(T) symbol(library: const *NativeLibrary, name: string)->T fail
    {
        let address = library.symbol(name)
        if not address do
            fail NetworkError{"required libcurl symbol is unavailable", code: Curl.CURLE_NOT_BUILT_IN}
        return cast(T, address)
    }

    g_CurlMutex.lock()
    defer g_CurlMutex.unlock()
    if g_CurlReady do
        return &g_Curl
    var state: CurlLibrary
    state.library = catch NativeLibrary.load("libcurl.so.4")
    {
        fail NetworkError{"cannot load libcurl.so.4", code: Curl.CURLE_FAILED_INIT}
    }

    state.globalInit    = try symbol'Curl.curl_global_init_fn(&state.library, "curl_global_init")
    state.globalCleanup = try symbol'Curl.curl_global_cleanup_fn(&state.library, "curl_global_cleanup")
    state.versionInfo   = try symbol'Curl.curl_version_info_fn(&state.library, "curl_version_info")
    state.easyInit      = try symbol'Curl.curl_easy_init_fn(&state.library, "curl_easy_init")
    state.easyCleanup   = try symbol'Curl.curl_easy_cleanup_fn(&state.library, "curl_easy_cleanup")
    state.setOption     = try symbol'Curl.curl_easy_setopt_fn(&state.library, "curl_easy_setopt")
    state.getInfo       = try symbol'Curl.curl_easy_getinfo_fn(&state.library, "curl_easy_getinfo")
    state.perform       = try symbol'Curl.curl_easy_perform_fn(&state.library, "curl_easy_perform")
    state.appendHeader  = try symbol'Curl.curl_slist_append_fn(&state.library, "curl_slist_append")
    state.freeHeaders   = try symbol'Curl.curl_slist_free_all_fn(&state.library, "curl_slist_free_all")
    state.createUrl     = try symbol'Curl.curl_url_fn(&state.library, "curl_url")
    state.freeUrl       = try symbol'Curl.curl_url_cleanup_fn(&state.library, "curl_url_cleanup")
    state.setUrlPart    = try symbol'Curl.curl_url_set_fn(&state.library, "curl_url_set")

    // Lazy initialization happens in an already threaded program. NOSIGNAL also needs an
    // asynchronous resolver for the request deadline to cover DNS lookup.
    let version  = state.versionInfo(Curl.CURLVERSION_FIRST)
    let required = Curl.CURL_VERSION_THREADSAFE | Curl.CURL_VERSION_ASYNCHDNS
    if (version.features & required) != required do
        fail NetworkError{"libcurl needs thread-safe initialization and asynchronous DNS", code: Curl.CURLE_NOT_BUILT_IN}
    try checkCurl(state.globalInit(Curl.CURL_GLOBAL_DEFAULT))
    g_Curl      = #move state
    g_CurlReady = true
    return &g_Curl
}

#drop
{
    // As with other native library owners, callers must finish before Net is unloaded.
    g_CurlMutex.lock()
    defer g_CurlMutex.unlock()
    if g_CurlReady
    {
        g_Curl.globalCleanup()
        g_Curl.library.close()
        g_CurlReady = false
    }
}

private struct CurlResponse
{
    response:     Response
    maxBodyBytes: u64
    headerBytes:  u64
    overflow:     bool
    hasLocation:  bool
    inHeaders:    bool
}

#[Swag.CallingConvention(.C)]
private func receiveBody(bytes: [*]u8, size, count: u64, user: *void?)->u64
{
    let state = cast(*CurlResponse, unwrap user)
    if size != 0 and count > Swag.U64.Max / size
    {
        state.overflow = true
        return 0
    }

    let length = size * count
    if length > state.maxBodyBytes - Math.min(state.maxBodyBytes, state.response.body.count)
    {
        state.overflow = true
        return 0
    }

    state.response.body.add(bytes[until length])
    return length
}

#[Swag.CallingConvention(.C)]
private func receiveHeader(bytes: [*]u8, size, count: u64, user: *void?)->u64
{
    let state = cast(*CurlResponse, unwrap user)
    if size != 0 and count > Swag.U64.Max / size
    {
        state.overflow = true
        return 0
    }

    let length = size * count
    if length > 65536 - state.headerBytes
    {
        state.overflow = true
        return 0
    }

    state.headerBytes += length
    let line = cast(string, bytes[until length])
    if Utf8.startsWith(line, "HTTP/")
    {
        // Informational responses must not leak their Location into the final response.
        state.response.location.clear()
        state.hasLocation = false
        state.inHeaders   = true
    }
    elif line == "\r\n" or line == "\n"
    {
        state.inHeaders = false
    }
    elif state.inHeaders and
         not state.hasLocation and
         length >= 9 and
         String.toLower(line[until 9]) == "location:"
    {
        var start = 9'u64
        var end   = length
        while start < end and (line[start] == ' ' or line[start] == '\t') do
            start += 1
        while end > start and (line[end - 1] == '\r' or line[end - 1] == '\n' or line[end - 1] == ' ' or line[end - 1] == '\t') do
            end -= 1
        if end - start > 4096
        {
            state.overflow = true
            return 0
        }

        state.response.location = line[start until end]
        state.hasLocation       = true
    }

    return length
}

internal func getNative(host: string, port: u16, path: string, secure: bool, options: GetOptions)->Response fail
{
    let api = try ensureCurl()
    let url = api.createUrl()
    if not url do
        fail NetworkError{code: Curl.CURLE_OUT_OF_MEMORY}
    defer api.freeUrl(url)
    var headers: *Curl.curl_slist?
    defer api.freeHeaders(headers)
    var received = CurlResponse{maxBodyBytes: options.maxBodyBytes}
    let request  = api.easyInit()
    if not request do
        fail NetworkError{code: Curl.CURLE_OUT_OF_MEMORY}
    defer api.easyCleanup(request)

    // Set the authority as separate URL components: host text cannot inject a port,
    // user information or another destination through URL delimiters.
    let server  = String.from(host)
    let service = Format.toString("%", port)
    let scheme  = secure ? "https" : "http"
    if api.setUrlPart(url, Curl.CURLUPART_SCHEME, scheme.buffer, 0) != Curl.CURLUE_OK or
       api.setUrlPart(url, Curl.CURLUPART_HOST, server.buffer, 0) != Curl.CURLUE_OK or
       api.setUrlPart(url, Curl.CURLUPART_PORT, service.buffer, 0) != Curl.CURLUE_OK do
        fail Errors.BadParameterError{}
    try checkCurl(api.setOption(request, Curl.CURLOPT_CURLU, url))
    let query  = Utf8.indexOf(path, '?')
    let target = String.from(query == Swag.U64.Max ? path : path[until query])
    if api.setUrlPart(url, Curl.CURLUPART_PATH, target.buffer, 0) != Curl.CURLUE_OK do
        fail Errors.BadParameterError{}
    if query != Swag.U64.Max
    {
        let parameters = String.from(path[query + 1 to])
        if api.setUrlPart(url, Curl.CURLUPART_QUERY, parameters.buffer, 0) != Curl.CURLUE_OK do
            fail Errors.BadParameterError{}
    }

    let agent = String.from(options.userAgent)
    try checkCurl(api.setOption(request, Curl.CURLOPT_PATH_AS_IS, 1's64))
    try checkCurl(api.setOption(request, Curl.CURLOPT_USERAGENT, agent.buffer))
    try checkCurl(api.setOption(request, Curl.CURLOPT_HTTP_VERSION, Curl.CURL_HTTP_VERSION_1_1))
    try checkCurl(api.setOption(request, Curl.CURLOPT_PROTOCOLS, Curl.CURLPROTO_HTTP | Curl.CURLPROTO_HTTPS))
    try checkCurl(api.setOption(request, Curl.CURLOPT_FOLLOWLOCATION, 0's64))
    try checkCurl(api.setOption(request, Curl.CURLOPT_NETRC, 0's64))
    try checkCurl(api.setOption(request, Curl.CURLOPT_HTTP09_ALLOWED, 0's64))
    try checkCurl(api.setOption(request, Curl.CURLOPT_NOSIGNAL, 1's64))
    try checkCurl(api.setOption(request, Curl.CURLOPT_TIMEOUT_MS, cast(s64, options.timeoutMs)))
    try checkCurl(api.setOption(request, Curl.CURLOPT_CONNECTTIMEOUT_MS, cast(s64, options.timeoutMs)))
    try checkCurl(api.setOption(request, Curl.CURLOPT_SSL_VERIFYPEER, 1's64))
    try checkCurl(api.setOption(request, Curl.CURLOPT_SSL_VERIFYHOST, 2's64))
    try checkCurl(api.setOption(request, Curl.CURLOPT_PROXY_SSL_VERIFYPEER, 1's64))
    try checkCurl(api.setOption(request, Curl.CURLOPT_PROXY_SSL_VERIFYHOST, 2's64))
    try checkCurl(api.setOption(request, Curl.CURLOPT_SUPPRESS_CONNECT_HEADERS, 1's64))
    // Origin headers, especially Authorization, do not belong on a proxy CONNECT request.
    try checkCurl(api.setOption(request, Curl.CURLOPT_HEADEROPT, 1's64))

    // Keep libcurl's system roots unless the caller supplies the standard CA overrides.
    let certFile = Linux.getenv("SSL_CERT_FILE".buffer)
    if certFile and certFile[0] != 0
    {
        try checkCurl(api.setOption(request, Curl.CURLOPT_CAINFO, certFile))
        try checkCurl(api.setOption(request, Curl.CURLOPT_PROXY_CAINFO, certFile))
    }
    let certDirectory = Linux.getenv("SSL_CERT_DIR".buffer)
    if certDirectory and certDirectory[0] != 0
    {
        try checkCurl(api.setOption(request, Curl.CURLOPT_CAPATH, certDirectory))
        try checkCurl(api.setOption(request, Curl.CURLOPT_PROXY_CAPATH, certDirectory))
    }

    for header in options.headers
    {
        // A semicolon sends an empty field; a colon-only libcurl entry removes a field.
        let text = header.value.count ? Format.toString("%: %", header.name, header.value) :
                   Format.toString("%;", header.name)
        let appended = api.appendHeader(headers, text.buffer)
        if not appended do
            fail NetworkError{code: Curl.CURLE_OUT_OF_MEMORY}
        headers = appended
    }

    try checkCurl(api.setOption(request, Curl.CURLOPT_HTTPHEADER, headers))

    try checkCurl(api.setOption(request, Curl.CURLOPT_WRITEDATA, &received))
    try checkCurl(api.setOption(request, Curl.CURLOPT_WRITEFUNCTION, &receiveBody))
    try checkCurl(api.setOption(request, Curl.CURLOPT_HEADERDATA, &received))
    try checkCurl(api.setOption(request, Curl.CURLOPT_HEADERFUNCTION, &receiveHeader))
    let code = api.perform(request)
    if received.overflow do
        fail Errors.OverflowError{}
    try checkCurl(code)
    var status: s64
    try checkCurl(api.getInfo(request, Curl.CURLINFO_RESPONSE_CODE, &status))
    received.response.status = cast(u32, status)
    return #move received.response
}
