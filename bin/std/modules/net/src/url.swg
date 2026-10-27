#global export
#global namespace Url

using Core

// The owned parts needed for an HTTP request to a DNS name or IPv4 address.
struct HttpTarget
{
    public
    {
        host:    String     // Lowercase ASCII host, without a port.
        path:    String     // Absolute request path and optional query, without a fragment.
        port:    u16        // Explicit port, or the scheme's default.
        secure:  bool       // True for HTTPS.
        hasPort: bool       // True if the URL contained an explicit port.
    }
}

// Parses an absolute HTTP or HTTPS URL into owned request parts.
//
// This deliberately accepts only ASCII host names and IPv4 literals as hosts. User information,
// IPv6 literals, relative references and non-ASCII URL text are rejected. The path and query stay
// percent-encoded, an absent path becomes `/`, and a fragment is omitted. Invalid escapes,
// malformed ports, spaces and control characters fail.
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
    let colon     = Utf8.indexOf(authority, ':')
    let host      = colon == Swag.U64.Max ? authority : authority[0 until colon]
    if host.count == 0 do
        fail Errors.InvalidFormatError{}
    for c in host
    {
        if not ((c >= 'a' and c <= 'z') or
                (c >= 'A' and c <= 'Z') or
                Latin1.isDigit(c) or
                c == '.' or
                c == '-') do
            fail Errors.InvalidFormatError{}
    }

    result.host = String.toLower(host)
    if colon != Swag.U64.Max
    {
        result.hasPort = true
        let digits = authority[colon + 1 to]
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
    while index < finish
    {
        let c = text[index]
        if not ((c >= 'a' and c <= 'z') or
                (c >= 'A' and c <= 'Z') or
                Latin1.isDigit(c) or
                Utf8.indexOf("-._~:/?@!$&'()*+,;=[]%", cast(rune, c)) != Swag.U64.Max) do
            fail Errors.InvalidFormatError{}
        if c == '%'
        {
            if finish - index < 3 or
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
