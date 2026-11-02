#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

using Core

func httpFixturePort(name: string)->u16
{
    let value = Env.variable(name)
    Swag.assert(not value.isEmpty())
    return expect StrConv.toU16(value)
}

func expectHttpOverflow(port: u16, path: string, limit: u64)
{
    var error: Swag.Error
    discard catch Http.get("localhost", port, path, false, {maxBodyBytes: limit}) as error
    Swag.assert(error.value() is Errors.OverflowError)
}

// Run through http.linux.fixture.py, which owns isolated listeners and temporary test roots.
#[Swag.TestTag("integration.network.http")]
#test
{
    let port = httpFixturePort("SWAG_TEST_HTTP_PORT")
    let response = expect Http.get("localhost", port, "/chunked", false, {maxBodyBytes: 6})
    Swag.assert(response.status == 200 and cast(string, response.body.toSlice()) == "abcdef")
    Swag.assert(response.location.isEmpty())
    expectHttpOverflow(port, "/chunked", 5)
    expectHttpOverflow(port, "/body", 0)
    let empty = expect Http.get("localhost", port, "/empty", false, {maxBodyBytes: 0})
    Swag.assert(empty.status == 200 and empty.body.isEmpty())
}

#[Swag.TestTag("integration.network.http")]
#test
{
    let port = httpFixturePort("SWAG_TEST_HTTP_PORT")
    expectHttpOverflow(port, "/header-overflow", 0)
    expectHttpOverflow(port, "/location-overflow", 0)
    expectHttpOverflow(port, "/folded-location-overflow", 0)
    let folded = expect Http.get("localhost", port, "/folded-location", false)
    Swag.assert(folded.location == "/first /second")
    let limit = expect Http.get("localhost", port, "/location-limit", false, {maxBodyBytes: 0})
    Swag.assert(limit.status == 302 and limit.location.count == 4096)
    let response = expect Http.get("localhost", port, "/informational", false)
    Swag.assert(response.status == 200 and response.location.isEmpty())
    Swag.assert(cast(string, response.body.toSlice()) == "final")
}

#[Swag.TestTag("integration.network.http")]
#test
{
    let port = httpFixturePort("SWAG_TEST_HTTP_PORT")
    var options: Http.GetOptions
    options.userAgent = "Swag HTTP integration"
    options.headers.add({name: "X-Empty", value: ""})
    options.headers.add({name: "X-Test", value: "custom"})
    let response = expect Http.get("localhost", port, "/headers", false, options)
    Swag.assert(cast(string, response.body.toSlice()) == "|custom|Swag HTTP integration")
    let path = "/a/../encoded%2F?q=%2B"
    let exact = expect Http.get("localhost", port, path, false)
    Swag.assert(cast(string, exact.body.toSlice()) == path)
    let redirect = expect Http.get("localhost", port, "/redirect", false)
    Swag.assert(redirect.status == 302 and redirect.location == "/redirect-target")
    let missing = expect Http.get("localhost", port, "/missing", false)
    Swag.assert(missing.status == 404 and cast(string, missing.body.toSlice()) == "missing")
}

#[Swag.TestTag("integration.network.http")]
#test
{
    let port = httpFixturePort("SWAG_TEST_HTTP_PORT")
    var error: Swag.Error
    discard catch Http.get("localhost", port, "/partial", false) as error
    Swag.assert(error.value() is NetworkError)
    let started = Time.monotonicMilliseconds()
    discard catch Http.get("localhost", port, "/slow", false, {timeoutMs: 100}) as error
    let elapsed = Time.monotonicMilliseconds() - started
    Swag.assert(error.value() is NetworkError and elapsed < 2000)
    if error.value() is NetworkError as networkError do
        Swag.assert(networkError.code == Curl.CURLE_OPERATION_TIMEDOUT)
}

#[Swag.TestTag("integration.network.http")]
#test
{
    let port = httpFixturePort("SWAG_TEST_HTTPS_PORT")
    let response = expect Http.get("localhost", port, "/body")
    Swag.assert(response.status == 200 and cast(string, response.body.toSlice()) == "hello")
    var error: Swag.Error
    // The trusted certificate names localhost, not the numeric address.
    discard catch Http.get("127.0.0.1", port, "/body") as error
    Swag.assert(error.value() is NetworkError)
    if error.value() is NetworkError as networkError do
        Swag.assert(networkError.code == Curl.CURLE_PEER_FAILED_VERIFICATION)
    discard catch Http.get("localhost", httpFixturePort("SWAG_TEST_UNTRUSTED_HTTPS_PORT"), "/body") as error
    Swag.assert(error.value() is NetworkError)
    if error.value() is NetworkError as networkError do
        Swag.assert(networkError.code == Curl.CURLE_PEER_FAILED_VERIFICATION)
}

#[Swag.TestTag("integration.network.http")]
#test
{
    let port = httpFixturePort("SWAG_TEST_HTTP_PORT")
    for host in ["localhost@127.0.0.1", "localhost/ignored", "localhost?query", "localhost#fragment"]
    {
        var error: Swag.Error
        discard catch Http.get(host, port, "/body", false) as error
        Swag.assert(error.value() is Errors.BadParameterError)
    }
}

// --proxy on the fixture wrapper routes these reserved names only through its local proxy.
#[Swag.TestTag("integration.network.proxy")]
#test
{
    let port = httpFixturePort("SWAG_TEST_HTTP_PORT")
    let response = expect Http.get("proxy-target.invalid", port, "/a/../encoded%2F?q=%2B", false)
    var expected = Format.toString("proxy|http://proxy-target.invalid:%", port)
    expected += "/a/../encoded%2F?q=%2B"
    Swag.assert(cast(string, response.body.toSlice()) == expected.toString())
    let tunnel = expect Http.get("proxy-target.invalid", httpFixturePort("SWAG_TEST_HTTPS_PORT"), "/body")
    Swag.assert(tunnel.status == 200 and cast(string, tunnel.body.toSlice()) == "hello")
    let bypass = expect Http.get("localhost", port, "/body", false)
    Swag.assert(cast(string, bypass.body.toSlice()) == "hello")
}

// A proxy certificate is verified independently of the origin's certificate.
#[Swag.TestTag("integration.network.proxy-untrusted")]
#test
{
    for secure in [false, true]
    {
        let port = httpFixturePort(secure ? "SWAG_TEST_HTTPS_PORT" : "SWAG_TEST_HTTP_PORT")
        var error: Swag.Error
        discard catch Http.get("proxy-target.invalid", port, "/body", secure) as error
        Swag.assert(error.value() is NetworkError)
        if error.value() is NetworkError as networkError do
            Swag.assert(networkError.code == Curl.CURLE_PEER_FAILED_VERIFICATION)
    }
}

#[Swag.TestTag("integration.network.http")]
#test
{
    func socketCount()->u64
    {
        let directory = unwrap Linux.opendir("/proc/self/fd".buffer)
        defer discard Linux.closedir(directory)
        let descriptor = Linux.dirfd(directory)
        Swag.assert(descriptor >= 0)
        var result: u64
        for
        {
            Linux.errno(0)
            let entry = Linux.readdir(directory)
            if not entry
            {
                Swag.assert(Linux.errno() == 0)
                break
            }
            var buffer: [256]u8
            let count = Linux.readlinkat(descriptor, &entry.d_name[0], &buffer[0], buffer.count)
            if count >= 8 and Utf8.startsWith(cast(string, buffer[until cast(u64, count)]), "socket:[") do
                result += 1
        }
        return result
    }

    let port = httpFixturePort("SWAG_TEST_HTTP_PORT")
    let untrusted = httpFixturePort("SWAG_TEST_UNTRUSTED_HTTPS_PORT")
    expectHttpOverflow(port, "/chunked", 5)
    var error: Swag.Error
    discard catch Http.get("localhost", untrusted, "/body") as error
    Swag.assert(error.value() is NetworkError)
    let before = socketCount()
    for 16
    {
        expectHttpOverflow(port, "/chunked", 5)
        discard catch Http.get("localhost", untrusted, "/body") as error
        Swag.assert(error.value() is NetworkError)
    }
    let after = socketCount()
    Swag.assert(after == before)
}
