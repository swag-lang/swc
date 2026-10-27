#global if #command == Swag.CompilerCommand.Test
#global private

using Core

struct HttpServerFixture
{
    late listener: *TcpListener
    request:       String
    response:      string
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

func stallHttp(thread: const *Threading.Thread)
{
    let listener = cast(*TcpListener, unwrap thread.userParam)
    var stream   = expect listener.accept()
    var buffer: [1024] u8
    discard expect stream.read(buffer)
    Threading.Thread.sleep(8's)
}

// A peer that accepts a connection but never sends a response reaches the receive timeout.
#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect listener.localEndpoint()
    var thread: Threading.Thread
    expect thread.init(&stallHttp, &listener)
    expect thread.start()
    var error: Swag.Error
    let started = Time.monotonicMilliseconds()
    discard catch Http.get("127.0.0.1", endpoint.port, "/", false, {timeoutMs: 100}) as error
    let elapsed = Time.monotonicMilliseconds() - started
    thread.wait()
    Swag.assert(error.value() is NetworkError)
    if error.value() is NetworkError as networkError do
        Swag.assert(networkError.code == 12002)     // ERROR_WINHTTP_TIMEOUT
    Swag.assert(elapsed < 7_000)
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
    Swag.assert(response.status == 200 and cast(string, response.body.toSlice()) == "hello")
    Swag.assert(Utf8.indexOf(fixture.request.toString(), "GET /films?title=hello HTTP/1.1") != Swag.U64.Max)
    Swag.assert(Utf8.indexOf(fixture.request.toString(), "X-Test: yes") != Swag.U64.Max)
    Swag.assert(Utf8.indexOf(fixture.request.toString(), "X_Test: also") != Swag.U64.Max)
}

#test
{
    let headers: [1] Http.Header = [{name: "X-Test", value: "good\r\nInjected: yes"}]
    var options: Http.GetOptions
    options.headers.add(headers)
    var error: Swag.Error
    discard catch Http.get("127.0.0.1", 80, "/", false, options) as error
    Swag.assert(error.value() != null)
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
    Swag.assert(error.value() is Errors.OverflowError)
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
    Swag.assert(response.status == 302 and response.body.isEmpty())
    Swag.assert(response.location == "http://127.0.0.1:1/")
}
