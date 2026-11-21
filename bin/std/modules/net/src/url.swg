#global export
#global namespace Url

using Core

// The owned parts needed for an HTTP request to a DNS name or IP address.
struct HttpTarget
{
    public
    {
        host:    String     // Lowercase DNS name or IP literal, without a port or IPv6 brackets or scope ID.
        path:    String     // Absolute request path and optional query, without a fragment.
        port:    u16        // Explicit port, or the scheme's default.
        secure:  bool       // True for HTTPS.
        hasPort: bool       // True if the URL contained an explicit port.
    }
}

// Parses an absolute HTTP or HTTPS URL into owned request parts.
//
// This accepts ASCII host names, IPv4 literals, and bracketed IPv6 literals, including IPv4-mapped
// addresses. IPv6 scope IDs, user information, relative references and non-ASCII URL text are
// rejected. The path and query stay
// percent-encoded, an absent path becomes `/`, and a fragment is omitted. Invalid escapes,
// malformed ports, overlong DNS names, spaces and control characters fail. DNS names have labels
// of at most 63 characters and a total of at most 253 characters, excluding an optional final dot.
func parseHttp(text: string)->HttpTarget fail
{
    var result: #returntype
    var start:  u64
    if text.count >= 8 and String.toLower(text[0 until 8]) == "https://"
    {
        start         = 8
        result.secure = true
        result.port   = 443
    }
    elif text.count >= 7 and String.toLower(text[0 until 7]) == "http://"
    {
        start       = 7
        result.port = 80
    }
    else
    {
        fail Errors.InvalidFormatError{}
    }

    var end = start
    while end < text.count and text[end] != '/' and text[end] != '?' and text[end] != '#' do
        end += 1
    if end == start do
        fail Errors.InvalidFormatError{}
    let authority = text[start until end]
    var host: string
    var portStart = Swag.U64.Max
    if authority[0] == '['
    {
        let closeBracket = Utf8.indexOf(authority, ']')
        if closeBracket == Swag.U64.Max do
            fail Errors.InvalidFormatError{}
        host = authority[1 until closeBracket]
        if not isValidIpv6Literal(host) do
            fail Errors.InvalidFormatError{}
        if closeBracket + 1 < authority.count
        {
            if authority[closeBracket + 1] != ':' do
                fail Errors.InvalidFormatError{}
            portStart = closeBracket + 2
        }
    }
    else
    {
        let colon = Utf8.indexOf(authority, ':')
        host = colon == Swag.U64.Max ? authority : authority[0 until colon]
        if colon != Swag.U64.Max
        {
            if Utf8.indexOf(authority[colon + 1 to], ':') != Swag.U64.Max do
                fail Errors.InvalidFormatError{}
            portStart = colon + 1
        }

        if host.count == 0 do
            fail Errors.InvalidFormatError{}
        var labelStart = 0'u64
        var hostIndex  = 0'u64
        while hostIndex < host.count
        {
            let c = host[hostIndex]
            if c == '.'
            {
                if hostIndex == labelStart do
                    fail Errors.InvalidFormatError{}
                if host[hostIndex - 1] == '-' or hostIndex - labelStart > 63 do
                    fail Errors.InvalidFormatError{}
                labelStart = hostIndex + 1
            }
            else
            {
                if not ((c >= 'a' and c <= 'z') or
                        (c >= 'A' and c <= 'Z') or
                        Latin1.isDigit(c) or
                        (c == '-' and hostIndex != labelStart)) do
                    fail Errors.InvalidFormatError{}
            }

            hostIndex += 1
        }

        if labelStart < host.count and
           (host.count - labelStart > 63 or host[host.count - 1] == '-') do
            fail Errors.InvalidFormatError{}

        let hostLength = host.count - (host[host.count - 1] == '.' ? 1 : 0)
        if hostLength > 253 do
            fail Errors.InvalidFormatError{}
    }

    result.host = String.toLower(host)
    if portStart != Swag.U64.Max
    {
        result.hasPort = true
        let digits = authority[portStart to]
        if digits.count == 0 do
            fail Errors.InvalidFormatError{}
        for c in digits where not Latin1.isDigit(c) do
            fail Errors.InvalidFormatError{}
        result.port = try StrConv.toU16(digits)
        if result.port == 0 do
            fail Errors.InvalidFormatError{}
    }

    var finish = end
    while finish < text.count and text[finish] != '#' do
        finish += 1
    var index = end
    while index < text.count
    {
        let c = text[index]
        if not ((c >= 'a' and c <= 'z') or
                (c >= 'A' and c <= 'Z') or
                Latin1.isDigit(c) or
                Utf8.indexOf("-._~:/?@!$&'()*+,;=%", cast(rune, c)) != Swag.U64.Max or
                (c == '#' and index == finish)) do
            fail Errors.InvalidFormatError{}
        if c == '%'
        {
            if text.count - index < 3 or
               not Latin1.isHexDigit(text[index + 1]) or
               not Latin1.isHexDigit(text[index + 2]) do
                fail Errors.InvalidFormatError{}
            index += 2
        }

        index += 1
    }

    if end == finish or text[end] == '?' do
        result.path = "/"
    result.path += text[end until finish]
    return result
}

private func isValidIpv6Literal(host: string)->bool
{
    if host.count == 0 do
        return false
    let compression = Utf8.indexOf(host, "::")
    if compression == Swag.U64.Max do
        return countIpv6Groups(host, true) == 8
    if Utf8.indexOf(host[compression + 2 to], "::") != Swag.U64.Max do
        return false
    let left  = countIpv6Groups(host[0 until compression], false)
    let right = countIpv6Groups(host[compression + 2 to], true)
    return left != Swag.U64.Max and right != Swag.U64.Max and left + right < 8
}

private func countIpv6Groups(part: string, allowIpv4Tail: bool)->u64
{
    if part.count == 0 do
        return 0
    if Utf8.indexOf(part, '.') != Swag.U64.Max
    {
        if not allowIpv4Tail do
            return Swag.U64.Max
        var tailStart = 0'u64
        var index     = 0'u64
        while index < part.count
        {
            if part[index] == ':' do
                tailStart = index + 1
            index += 1
        }

        let tail = part[tailStart to]
        if Utf8.indexOf(tail, '.') == Swag.U64.Max or not isValidIpv4Tail(tail) do
            return Swag.U64.Max
        let prefix       = tailStart == 0 ? "" : part[0 until tailStart - 1]
        let prefixGroups = countIpv6Groups(prefix, false)
        if prefixGroups == Swag.U64.Max do
            return Swag.U64.Max
        return prefixGroups + 2
    }

    var groups     = 1'u64
    var groupStart = 0'u64
    for index in part.count
    {
        if part[index] == ':'
        {
            let length = index - groupStart
            if length == 0 or length > 4 do
                return Swag.U64.Max
            groups     += 1
            groupStart = index + 1
        }
        elif not Latin1.isHexDigit(part[index])
        {
            return Swag.U64.Max
        }
    }

    let lastLength = part.count - groupStart
    if lastLength == 0 or lastLength > 4 do
        return Swag.U64.Max
    return groups
}

private func isValidIpv4Tail(address: string)->bool
{
    var octets = 0'u64
    var digits = 0'u64
    var value  = 0'u64
    var index  = 0'u64
    while index <= address.count
    {
        let c = index == address.count ? '.' : address[index]
        if c == '.'
        {
            if digits == 0 or digits > 3 or value > 255 do
                return false
            octets += 1
            digits = 0
            value  = 0
        }
        else
        {
            if not Latin1.isDigit(cast(u8, c)) do
                return false
            digits += 1
            value  = value * 10 + cast(u64, c - '0')
        }

        index += 1
    }

    return octets == 4
}

// Percent-encodes bytes for one URL component using the RFC 3986 unreserved alphabet.
//
// UTF-8 text is encoded byte by byte. Spaces become `%20`, not `+`; separators such as `&`,
// `=`, `/` and `%` are encoded so the result can be inserted as one query value or path segment.
func encodeComponent(bytes: const [..] u8)->String
{
    const Hex = "0123456789ABCDEF"
    var result: #returntype
    for byte in bytes
    {
        if (byte >= 'a' and byte <= 'z') or
           (byte >= 'A' and byte <= 'Z') or
           (byte >= '0' and byte <= '9') or
           byte == '-' or
           byte == '.' or
           byte == '_' or
           byte == '~'
        {
            result.append(byte)
        }
        else
        {
            result.append('%'u8)
            result.append(Hex[byte >> 4])
            result.append(Hex[byte & 15])
        }
    }

    return result
}

// Decodes percent escapes in one URL component into its original bytes.
//
// `+` remains `+`. A truncated escape or a non-hexadecimal digit fails; unescaped bytes are
// copied without interpreting or validating UTF-8.
func decodeComponent(text: string)->Array'u8 fail
{
    func hexValue(c: u8)->u8 fail
    {
        if c >= '0' and c <= '9' do
            return c - '0'u8
        if c >= 'A' and c <= 'F' do
            return c - 'A'u8 + 10
        if c >= 'a' and c <= 'f' do
            return c - 'a'u8 + 10
        fail Errors.InvalidFormatError{}
    }

    var result: #returntype
    var index = 0'u64
    while index < text.count
    {
        let byte = text[index]
        if byte != '%'
        {
            result.add(byte)
            index += 1
            continue
        }

        if text.count - index < 3 do
            fail Errors.InvalidFormatError{}
        let high = try hexValue(text[index + 1])
        let low  = try hexValue(text[index + 2])
        result.add((high << 4) | low)
        index += 3
    }

    return result
}
