#global if #command == Swag.CompilerCommand.Test
#global private

using Core

#test
{
    let title   = "Léon: The Professional & friends"
    let encoded = Url.encodeComponent(cast(const [..] u8, title))
    Swag.assert(encoded == "L%C3%A9on%3A%20The%20Professional%20%26%20friends")
    let decoded = expect Url.decodeComponent(encoded)
    Swag.assert(cast(string, decoded.toSlice()) == title)
    Swag.assert(Url.encodeComponent(cast(const [..] u8, "a-z_A~1")) == "a-z_A~1")
    Swag.assert(cast(string, (expect Url.decodeComponent("a+b%2f")).toSlice()) == "a+b/")
}

#test
{
    let https = expect Url.parseHttp("HTTPS://Example.COM:8443/a%20b?q=one%26two#section")
    Swag.assert(https.secure and https.host == "example.com" and https.port == 8443 and https.hasPort)
    Swag.assert(https.path == "/a%20b?q=one%26two")
    let query = expect Url.parseHttp("http://127.0.0.1?x=1#part")
    Swag.assert(not query.secure and query.port == 80 and not query.hasPort and query.path == "/?x=1")
    let empty = expect Url.parseHttp("https://example.com")
    Swag.assert(empty.port == 443 and empty.path == "/")
}

#test
{
    for invalid in ["/relative", "ftp://example.com/", "https://user@example.com/",
                    "https://[::1]/", "http://example.com:0/", "http://example.com:65536/",
                    "http://example.com:/", "http://example.com/a b", "http://example.com/%zz"]
    {
        var error: Swag.Error
        discard catch Url.parseHttp(invalid) as error
        Swag.assert(error.value() != null)
    }
}

#test
{
    for invalid in ["%", "%0", "%GG"]
    {
        var error: Swag.Error
        discard catch Url.decodeComponent(invalid) as error
        Swag.assert(error.value() != null)
    }
}
