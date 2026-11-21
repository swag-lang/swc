#global if #command == Swag.CompilerCommand.Test
#global private

using Core

#test
{
    let title   = "Léon: The Professional & friends"
    let encoded = Url.encodeComponent(cast(const [..] u8, title))
    Swag.require(encoded == "L%C3%A9on%3A%20The%20Professional%20%26%20friends")
    let decoded = expect Url.decodeComponent(encoded)
    Swag.require(cast(string, decoded.toSlice()) == title)
    Swag.require(Url.encodeComponent(cast(const [..] u8, "a-z_A~1")) == "a-z_A~1")
    Swag.require(cast(string, (expect Url.decodeComponent("a+b%2f")).toSlice()) == "a+b/")
}

#test
{
    let https = expect Url.parseHttp("HTTPS://Example.COM:8443/a%20b?q=one%26two#section")
    Swag.require(https.secure and https.host == "example.com" and https.port == 8443 and https.hasPort)
    Swag.require(https.path == "/a%20b?q=one%26two")
    let query = expect Url.parseHttp("http://127.0.0.1?x=1#part")
    Swag.require(not query.secure and query.port == 80 and not query.hasPort and query.path == "/?x=1")
    let empty = expect Url.parseHttp("https://example.com")
    Swag.require(empty.port == 443 and empty.path == "/")
    let ipv6 = expect Url.parseHttp("https://[2001:DB8::1]:8443/path")
    Swag.require(ipv6.secure and ipv6.host == "2001:db8::1" and ipv6.port == 8443 and ipv6.hasPort)
    let ipv6Default = expect Url.parseHttp("http://[::1]/")
    Swag.require(not ipv6Default.secure and ipv6Default.host == "::1" and ipv6Default.port == 80)
    let ipv6Full = expect Url.parseHttp("http://[2001:0db8:0000:0000:0000:0000:0000:0001]/")
    Swag.require(ipv6Full.host == "2001:0db8:0000:0000:0000:0000:0000:0001")
    let ipv4Mapped = expect Url.parseHttp("http://[::FFFF:192.0.2.1]/")
    Swag.require(ipv4Mapped.host == "::ffff:192.0.2.1")
}

#test
{
    for invalid in ["http://example.com/a[b]", "http://example.com/?key[]=value"]
    {
        var error: Swag.Error
        discard catch Url.parseHttp(invalid) as error
        Swag.require(error.value() is Errors.InvalidFormatError)
    }

    let encoded = expect Url.parseHttp("http://example.com/a%5Bb%5D?key%5B%5D=value")
    Swag.require(encoded.path == "/a%5Bb%5D?key%5B%5D=value")
}

#test
{
    for invalid in ["http://example.com/#bad fragment", "http://example.com/#%zz"]
    {
        var error: Swag.Error
        discard catch Url.parseHttp(invalid) as error
        Swag.require(error.value() is Errors.InvalidFormatError)
    }
}

#test
{
    for invalid in ["/relative", "ftp://example.com/", "https://user@example.com/",
                    "https://[:::1]/", "http://[1:2:3:4:5:6:7:8:9]/", "http://[2001::db8::1]/",
                    "http://[gg::1]/", "http://[::1", "http://[::1]junk/", "http://[::1]:/",
                    "http://[::ffff:192.0.2.999]/", "http://[::ffff:192.0.2]/",
                    "http://[::1]:0/", "http://example.com:0/", "http://example.com:65536/",
                    "http://example.com:/", "http://example.com/a b", "http://example.com/%zz"]
    {
        var error: Swag.Error
        discard catch Url.parseHttp(invalid) as error
        Swag.require(error.value() != null)
    }
}

#test
{
    for invalid in ["http://.example.com/", "http://example..com/", "http://-bad.example/",
                    "http://bad-.example/", "http://bad_name.example/"]
    {
        var error: Swag.Error
        discard catch Url.parseHttp(invalid) as error
        Swag.require(error.value() is Errors.InvalidFormatError)
    }

    Swag.require(expect Url.parseHttp("http://localhost/").host == "localhost")
    Swag.require(expect Url.parseHttp("http://example.com./").host == "example.com.")
}

#test
{
    var validHost, overlongHost: String
    for label in 4
    {
        if label > 0
        {
            validHost.append(".")
            overlongHost.append(".")
        }

        let validLabelLength    = label == 3 ? 61 : 63
        let overlongLabelLength = label == 3 ? 62 : 63
        var index = 0
        while index < validLabelLength
        {
            validHost.append('a'u8)
            index += 1
        }

        index = 0
        while index < overlongLabelLength
        {
            overlongHost.append('a'u8)
            index += 1
        }
    }

    Swag.require(validHost.count == 253 and overlongHost.count == 254)
    Swag.require(expect Url.parseHttp(Format.toString("http://%/", validHost)).host == validHost)

    var absoluteHost = validHost
    absoluteHost.append(".")
    Swag.require(expect Url.parseHttp(Format.toString("http://%/", absoluteHost)).host == absoluteHost)

    var error: Swag.Error
    discard catch Url.parseHttp(Format.toString("http://%/", overlongHost)) as error
    Swag.require(error.value() is Errors.InvalidFormatError)
}

#test
{
    for invalid in ["%", "%0", "%GG"]
    {
        var error: Swag.Error
        discard catch Url.decodeComponent(invalid) as error
        Swag.require(error.value() != null)
    }
}
