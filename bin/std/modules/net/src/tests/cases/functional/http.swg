#global if #command == Swag.CompilerCommand.Test
#global private

using Core

struct HttpServerFixture
{
    late listener: *TcpListener
    request:       String
    response:      string
}

struct HttpTimeoutFixture
{
    late listener:        *TcpListener
    late requestFinished: *Sync.Event
    received:             bool
}

struct HttpBodyFixture
{
    body:    String
    calls:   u32
    proceed: bool
}

struct HttpRequestBodyFixture
{
    body:   String
    offset: u64
    calls:  u32
}

struct HttpPostServerFixture
{
    server:       *Http.Server
    body:         String
    bodyRejected: bool
}

func receiveHttpBody(context: *void?, bytes: const [..] u8)->bool
{
    let fixture = cast(*HttpBodyFixture, unwrap context)
    fixture.body.append(cast(string, bytes))
    fixture.calls += 1
    return fixture.proceed
}

func supplyHttpRequestBody(context: *void?, buffer: [..] u8)->u64
{
    let fixture = cast(*HttpRequestBodyFixture, unwrap context)
    let source = cast(const [..] u8, fixture.body.toString())
    let count = Math.min(Math.min(buffer.count, 512), source.count - fixture.offset)
    Memory.copy(buffer.buffer, source.buffer + fixture.offset, count)
    fixture.offset += count
    fixture.calls += 1
    return count
}

func serveHttpPost(thread: const *Threading.Thread)
{
    let fixture = cast(*HttpPostServerFixture, unwrap thread.userParam)
    var connection = expect fixture.server.accept()
    let request = expect connection.readRequest()
    Swag.require(request.method == "POST")
    fixture.body = String.from(cast(string, request.body.toSlice()))
    expect connection.respond(200, cast(const [..] u8, "received"))
}

func rejectShortHttpPost(thread: const *Threading.Thread)
{
    let fixture = cast(*HttpPostServerFixture, unwrap thread.userParam)
    var connection = expect fixture.server.accept()
    var error: Swag.Error
    discard catch connection.readRequest() as error
    fixture.bodyRejected = error.value() is Errors.InvalidFormatError
}

func serveHttp(thread: const *Threading.Thread)
{
    let fixture = cast(*HttpServerFixture, unwrap thread.userParam)
    var stream  = expect fixture.listener.accept()
    var buffer: [1024] u8
    while Utf8.indexOf(fixture.request.toString(), "\r\n\r\n") == Swag.U64.Max
    {
        let count = expect stream.read(buffer)
        if count == 0 do
            return
        fixture.request += cast(string, buffer[0 until count])
    }

    let response = cast(const [..] u8, fixture.response)
    var written  = 0'u64
    while written < response.count
    {
        let count = expect stream.write(response[written to])
        if count == 0 do
            return
        written += count
    }
}

// Request validation rejects missing body readers and caller-supplied transfer framing.
#test
{
    var missingReader: Swag.Error
    discard catch Http.post("localhost", 80, "/", false, {requestBodyLength: 1}) as missingReader
    Swag.require(missingReader.value() is Errors.BadParameterError)

    var framedHeader: Swag.Error
    var options: Http.PostOptions
    options.headers.add({name: "Content-Length", value: "1"})
    discard catch Http.post("localhost", 80, "/", false, options) as framedHeader
    Swag.require(framedHeader.value() is Errors.BadParameterError)
}

// Keep-alive serves a bounded second request and closes at the configured request limit.
#test
{
    var invalid: Swag.Error
    discard catch Http.Server.listen({address: [127, 0, 0, 1], port: 0},
        {maxRequestsPerConnection: 2}) as invalid
    Swag.require(invalid.value() is Errors.BadParameterError)

    var options = Http.ServerOptions{maxRequestsPerConnection: 2, idleTimeoutMs: 1000}
    var server = expect Http.Server.listen({address: [127, 0, 0, 1], port: 0}, options)
    var client = expect TcpStream.connect(expect server.localAddress())
    let firstRequest = cast(const [..] u8,
        "GET /one HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n")
    Swag.require(expect client.write(firstRequest) == firstRequest.count)

    var connection = expect server.accept()
    let first = expect connection.readRequest()
    Swag.require(first.target == "/one")
    expect connection.respond(200, cast(const [..] u8, "one"))

    var response: String
    var buffer: [512] u8
    while Utf8.indexOf(response.toString(), "one") == Swag.U64.Max
    {
        let count = expect client.read(buffer)
        Swag.require(count > 0)
        response.append(cast(string, buffer[0 until count]))
    }
    Swag.require(Utf8.indexOf(response.toString(), "Connection: keep-alive") != Swag.U64.Max)

    let secondRequest = cast(const [..] u8,
        "GET /two HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
    Swag.require(expect client.write(secondRequest) == secondRequest.count)
    let second = expect connection.readRequest()
    Swag.require(second.target == "/two")
    expect connection.respond(200, cast(const [..] u8, "two"))

    var finalResponse: String
    for
    {
        let count = expect client.read(buffer)
        if count == 0 do
            break
        finalResponse.append(cast(string, buffer[0 until count]))
    }
    Swag.require(Utf8.indexOf(finalResponse.toString(), "two") != Swag.U64.Max)
    Swag.require(Utf8.indexOf(finalResponse.toString(), "Connection: close") != Swag.U64.Max)
}

// An idle persistent connection times out while waiting for its first request.
#test
{
    let options = Http.ServerOptions{maxRequestsPerConnection: 2, idleTimeoutMs: 50}
    var server = expect Http.Server.listen({address: [127, 0, 0, 1], port: 0}, options)
    var client = expect TcpStream.connect(expect server.localAddress())
    var connection = expect server.accept()
    var error: Swag.Error
    discard catch connection.readRequest() as error
    Swag.require(error.value() is NetworkError)
}

// A peer that accepts a connection but never sends a response reaches the receive timeout.
#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect listener.localEndpoint()
    var requestFinished: Sync.Event
    requestFinished.init(manual: false)
    var fixture = HttpTimeoutFixture{listener: &listener, requestFinished: &requestFinished}

    func stallHttp(thread: const *Threading.Thread)
    {
        let peer   = cast(*HttpTimeoutFixture, unwrap thread.userParam)
        var stream = expect peer.listener.accept()
        var buffer: [1024] u8
        peer.received = (expect stream.read(buffer)) > 0
        peer.requestFinished.wait()
    }

    var thread: Threading.Thread
    expect thread.init(&stallHttp, &fixture)
    expect thread.start()
    var error: Swag.Error
    discard catch Http.get("127.0.0.1", endpoint.port, "/", false, {timeoutMs: 100}) as error
    requestFinished.signal()
    thread.wait()
    Swag.require(fixture.received)
    Swag.require(error.value() is NetworkError)
    if error.value() is NetworkError as networkError
    {
        #static if #os == Swag.TargetOs.Windows do
            Swag.require(networkError.code == 12002)     // ERROR_WINHTTP_TIMEOUT
        else do
            Swag.require(networkError.code == Curl.CURLE_OPERATION_TIMEDOUT)
    }
}

// POST request bytes are read incrementally and carry an exact content length.
#test
{
    var server = expect Http.Server.listen({address: [127, 0, 0, 1], port: 0})
    var fixture = HttpPostServerFixture{server: &server}
    var thread: Threading.Thread
    expect thread.init(&serveHttpPost, &fixture)
    expect thread.start()

    var requestBytes: String
    for 20000 do
        requestBytes.append(cast(u8, 'x'))
    var requestBody = HttpRequestBodyFixture{body: #move requestBytes}
    let endpoint = expect server.localAddress()
    let response = expect Http.post("127.0.0.1", endpoint.port, "/upload", false,
        {requestBodyLength: requestBody.body.count,
         bodyReader: &supplyHttpRequestBody,
         requestContext: &requestBody})
    thread.wait()
    Swag.require(response.status == 200 and cast(string, response.body.toSlice()) == "received")
    Swag.require(fixture.body.toString() == requestBody.body.toString())
    Swag.require(requestBody.offset == requestBody.body.count)
    Swag.require(requestBody.calls > 1)
}

// A request body reader that ends early fails instead of sending a shorter body silently.
#test
{
    var server = expect Http.Server.listen({address: [127, 0, 0, 1], port: 0})
    var fixture = HttpPostServerFixture{server: &server}
    var thread: Threading.Thread
    expect thread.init(&rejectShortHttpPost, &fixture)
    expect thread.start()

    var requestBody: HttpRequestBodyFixture
    let endpoint = expect server.localAddress()
    var error: Swag.Error
    discard catch Http.post("127.0.0.1", endpoint.port, "/upload", false,
        {requestBodyLength: 1, bodyReader: &supplyHttpRequestBody, requestContext: &requestBody}) as error
    thread.wait()
    Swag.require(error.value() is NetworkError)
    Swag.require(fixture.bodyRejected)
}

#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect listener.localEndpoint()
    var server = HttpServerFixture{listener: &listener,
        response: "HTTP/1.1 200 OK\r\nContent-Length: 8\r\nConnection: close\r\n\r\nstreamed"}
    var thread: Threading.Thread
    expect thread.init(&serveHttp, &server)
    expect thread.start()

    var received = HttpBodyFixture{proceed: true}
    let response = expect Http.get("127.0.0.1", endpoint.port, "/", false,
        {bodyHandler: &receiveHttpBody, bodyContext: &received})
    thread.wait()
    Swag.require(response.status == 200 and response.body.isEmpty())
    Swag.require(received.body.toString() == "streamed" and received.calls > 0)
}

#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect listener.localEndpoint()
    var server = HttpServerFixture{listener: &listener,
        response: "HTTP/1.1 200 OK\r\nContent-Length: 4\r\nConnection: close\r\n\r\ndata"}
    var thread: Threading.Thread
    expect thread.init(&serveHttp, &server)
    expect thread.start()

    var received = HttpBodyFixture{proceed: false}
    var error: Swag.Error
    discard catch Http.get("127.0.0.1", endpoint.port, "/", false,
        {bodyHandler: &receiveHttpBody, bodyContext: &received}) as error
    thread.wait()
    Swag.require(error.value() is NetworkError)
    Swag.require(received.body.toString() == "data")
}

#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect listener.localEndpoint()
    var fixture  = HttpServerFixture{listener: &listener, response: "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello"}
    var thread: Threading.Thread
    expect thread.init(&serveHttp, &fixture)
    expect thread.start()

    let headers: [2] Http.Header = [{name: "X-Test", value: "yes"}, {name: "X_Test", value: "also"}]
    var options: Http.GetOptions
    options.headers.add(headers)
    let response = expect Http.get("127.0.0.1", endpoint.port, "/films?title=hello", false, options)
    thread.wait()
    Swag.require(response.status == 200 and cast(string, response.body.toSlice()) == "hello")
    Swag.require(Utf8.indexOf(fixture.request.toString(), "GET /films?title=hello HTTP/1.1") != Swag.U64.Max)
    Swag.require(Utf8.indexOf(fixture.request.toString(), "X-Test: yes") != Swag.U64.Max)
    Swag.require(Utf8.indexOf(fixture.request.toString(), "X_Test: also") != Swag.U64.Max)
}

#test
{
    let headers: [1] Http.Header = [{name: "X-Test", value: "good\r\nInjected: yes"}]
    var options: Http.GetOptions
    options.headers.add(headers)
    var error: Swag.Error
    discard catch Http.get("127.0.0.1", 80, "/", false, options) as error
    Swag.require(error.value() != null)
}

#test
{
    var error: Swag.Error
    discard catch Http.get("127.0.0.1", 80, "/resource#fragment", false) as error
    Swag.require(error.value() is Errors.BadParameterError)
}

#test
{
    for path in ["/truncated%", "/truncated%2", "/bad%GG", "/café"]
    {
        var error: Swag.Error
        discard catch Http.get("127.0.0.1", 1, path, false) as error
        Swag.require(error.value() is Errors.BadParameterError)
    }
}

#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect listener.localEndpoint()
    var fixture  = HttpServerFixture{listener: &listener, response: "HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\n123456"}
    var thread: Threading.Thread
    expect thread.init(&serveHttp, &fixture)
    expect thread.start()

    var error: Swag.Error
    discard catch Http.get("127.0.0.1", endpoint.port, "/", false, {maxBodyBytes: 5}) as error
    thread.wait()
    Swag.require(error.value() is Errors.OverflowError)
}

#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect listener.localEndpoint()
    var fixture  = HttpServerFixture{listener: &listener, response: "HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:1/\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"}
    var thread: Threading.Thread
    expect thread.init(&serveHttp, &fixture)
    expect thread.start()

    let response = expect Http.get("127.0.0.1", endpoint.port, "/", false)
    thread.wait()
    Swag.require(response.status == 302 and response.body.isEmpty())
    Swag.require(response.location == "http://127.0.0.1:1/")
}

// The HTTP server parses a bounded request body and sends a complete response.
#test
{
    var server = expect Http.Server.listen({address: [127, 0, 0, 1], port: 0})
    var client = expect TcpStream.connect(expect server.localAddress())
    let request = cast(const [..] u8,
        "POST /submit HTTP/1.1\r\nHost: localhost\r\nContent-Length: 4\r\nX-Mode: test\r\n\r\ndata")
    Swag.require(expect client.write(request) == request.count)
    var connection = expect server.accept()
    let parsed = expect connection.readRequest()
    Swag.require(parsed.method == "POST" and parsed.target == "/submit")
    Swag.require(parsed.body.count == 4 and cast(string, parsed.body.toSlice()) == "data")
    Swag.require(parsed.headers.count == 3 and parsed.headers[2].name == "X-Mode")
    expect connection.respond(201, cast(const [..] u8, "created"))
    var response: String
    var buffer: [256] u8
    for
    {
        let count = expect client.read(buffer)
        if count == 0 do
            break
        response.append(cast(string, buffer[0 until count]))
    }
    Swag.require(Utf8.indexOf(response.toString(), "HTTP/1.1 201 Created") != Swag.U64.Max)
    Swag.require(Utf8.indexOf(response.toString(), "created") != Swag.U64.Max)
    Swag.require(expect client.read(buffer) == 0)
}

// The server accepts chunked uploads and can stream a chunked response.
#test
{
    var server = expect Http.Server.listen({address: [127, 0, 0, 1], port: 0})
    var client = expect TcpStream.connect(expect server.localAddress())
    let request = cast(const [..] u8,
        "POST /chunks HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\nA\r\n0123456789\r\n1\r\n!\r\n0\r\n\r\n")
    Swag.require(expect client.write(request) == request.count)
    var connection = expect server.accept()
    let parsed = expect connection.readRequest()
    Swag.require(cast(string, parsed.body.toSlice()) == "0123456789!")
    expect connection.beginChunkedResponse(200)
    expect connection.writeBody(cast(const [..] u8, "first"))
    expect connection.writeBody(cast(const [..] u8, "second"))
    expect connection.finishResponse()
    var response: String
    var buffer: [512] u8
    for
    {
        let count = expect client.read(buffer)
        if count == 0 do
            break
        response.append(cast(string, buffer[0 until count]))
    }
    Swag.require(Utf8.indexOf(response.toString(), "Transfer-Encoding: chunked") != Swag.U64.Max)
    Swag.require(Utf8.indexOf(response.toString(), "5\r\nfirst\r\n") != Swag.U64.Max)
    Swag.require(Utf8.indexOf(response.toString(), "6\r\nsecond\r\n") != Swag.U64.Max)
    Swag.require(Utf8.indexOf(response.toString(), "0\r\n\r\n") != Swag.U64.Max)
}

// Ambiguous HTTP body framing is rejected before any body bytes are consumed.
#test
{
    var server = expect Http.Server.listen({address: [127, 0, 0, 1], port: 0})
    var client = expect TcpStream.connect(expect server.localAddress())
    let request = cast(const [..] u8,
        "POST / HTTP/1.1\r\nContent-Length: 0\r\nTransfer-Encoding: chunked\r\n\r\n")
    Swag.require(expect client.write(request) == request.count)
    var connection = expect server.accept()
    var error: Swag.Error
    discard catch connection.readRequest() as error
    Swag.require(error.value() is Errors.InvalidFormatError)
}

// Malformed transfer framing and forbidden trailers fail before a request is returned.
#test
{
    let requests = [
        "POST / HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\nx",
        "POST / HTTP/1.1\r\nTransfer-Encoding: gzip\r\n\r\n",
        "POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\nz\r\n",
        "POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n0\r\nContent-Length: 0\r\n\r\n"]
    for requestText in requests
    {
        var server = expect Http.Server.listen({address: [127, 0, 0, 1], port: 0})
        var client = expect TcpStream.connect(expect server.localAddress())
        let request = cast(const [..] u8, requestText)
        Swag.require(expect client.write(request) == request.count)
        var connection = expect server.accept()
        var error: Swag.Error
        discard catch connection.readRequest() as error
        Swag.require(error.value() is Errors.InvalidFormatError)
    }
}

// Closing an HTTP server releases its listening endpoint without changing accepted streams.
#test
{
    var server = expect Http.Server.listen({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect server.localAddress()
    server.close()
    server.close()
    var error: Swag.Error
    discard catch TcpStream.connect(endpoint) as error
    Swag.require(error.value() is NetworkError)
}
