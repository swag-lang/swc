#global public

using Core

// The RFC 6455 frame kinds supported by [[Net.WebSocket]].
enum WebSocketOpcode: u8
{
    Continuation = 0      // Continues a fragmented text or binary message.
    Text         = 1      // Carries a UTF-8 text message or fragment.
    Binary       = 2      // Carries a binary message or fragment.
    Close        = 8      // Starts or acknowledges the WebSocket closing handshake.
    Ping         = 9      // Requests a Pong control frame.
    Pong         = 10     // Replies to a Ping control frame.
}

// Limits the frame and reassembled message sizes accepted by a WebSocket peer.
struct WebSocketOptions
{
    public
    {
        maxFrameBytes:   u64 = 16 * 1024 * 1024     // Maximum payload in one frame.
        maxMessageBytes: u64 = 64 * 1024 * 1024     // Maximum payload across fragments in one message.
    }
}

// A received WebSocket frame; fragments and control frames remain visible to the caller.
struct WebSocketFrame
{
    public
    {
        opcode:  WebSocketOpcode     // Frame kind.
        final:   bool                // Whether this is the last frame in the message.
        payload: Array'u8            // Unmasked frame payload.
    }
}

internal enum WebSocketSide: u8
{
    Client = 0
    Server = 1
}

// Owns a blocking WebSocket connection established with an HTTP/1.1 upgrade.
#[Swag.NoCopy]
struct WebSocket
{
    stream:             TcpStream
    side:               WebSocketSide
    options:            WebSocketOptions
    input:              [4096] u8
    inputOffset:        u64
    inputCount:         u64
    sendHasFragments:   bool
    sendFragmentOpcode: WebSocketOpcode
    sendFragmentBytes:  u64
    sendTextBytes:      Array'u8
    recvHasFragments:   bool
    recvFragmentOpcode: WebSocketOpcode
    recvFragmentBytes:  u64
    recvTextBytes:      Array'u8
    open:               bool
}

private const WebSocketGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

internal func webSocketAccept(key: string)->String fail
{
    let decoded = try Base64.decode(key, 16)
    if decoded.count != 16 or Base64.encode(decoded.toSlice()) != key do
        fail Errors.InvalidFormatError{"invalid WebSocket key"}
    var hash: Hash.Sha1
    var source = String.from(key)
    source += WebSocketGuid
    hash.update(cast(const [..] u8, source))
    let words = hash.finalize()
    var bytes: [20] u8
    for i in words.count
    {
        bytes[i * 4 + 0] = cast(u8, words[i] >> 24)
        bytes[i * 4 + 1] = cast(u8, (words[i] >> 16) & 0xFF)
        bytes[i * 4 + 2] = cast(u8, (words[i] >> 8) & 0xFF)
        bytes[i * 4 + 3] = cast(u8, words[i] & 0xFF)
    }

    return Base64.encode(bytes)
}

private func webSocketOpcode(raw: u8)->WebSocketOpcode fail
{
    switch raw
    {
    case 0:  return .Continuation
    case 1:  return .Text
    case 2:  return .Binary
    case 8:  return .Close
    case 9:  return .Ping
    case 10: return .Pong
    default: fail Errors.InvalidFormatError{"invalid WebSocket opcode"}
    }
}

private func webSocketHasToken(value: string, token: string)->bool
{
    var offset = 0'u64
    while offset <= value.count
    {
        let separator = Utf8.indexOf(value, ",", offset)
        let end       = separator == Swag.U64.Max ? value.count : separator
        let candidate = Latin1.trim(value[offset until end])
        if candidate.count == token.count and Utf8.indexOf(candidate, token, 0, .Latin1NoCase) == 0 do
            return true
        if separator == Swag.U64.Max do
            break
        offset = separator + 1
    }

    return false
}

private func webSocketIsSwitchingProtocols(status: string)->bool
{
    return status.count >= 13 and
           status[0 until 12] == "HTTP/1.1 101" and
           status[12] == ' '
}

internal func webSocketValidateUpgrade(request: Http.ServerRequest)->String fail
{
    if request.method != "GET" or request.version != "HTTP/1.1" do
        fail Errors.InvalidFormatError{"WebSocket upgrade requires HTTP/1.1 GET"}
    var hasHost       = false
    var hasUpgrade    = false
    var hasConnection = false
    var hasVersion    = false
    var hostCount     = 0
    var upgradeCount  = 0
    var versionCount  = 0
    var keyCount      = 0
    var key: String
    for header in request.headers
    {
        if Utf8.indexOf(header.name, "Host", 0, .Latin1NoCase) == 0 and header.name.count == 4
        {
            hostCount += 1
            hasHost   = header.value.count != 0
        }
        elif Utf8.indexOf(header.name, "Upgrade", 0, .Latin1NoCase) == 0 and header.name.count == 7
        {
            upgradeCount += 1
            hasUpgrade   = webSocketHasToken(header.value, "websocket")
        }
        elif Utf8.indexOf(header.name, "Connection", 0, .Latin1NoCase) == 0 and header.name.count == 10
        {
            hasConnection = hasConnection or webSocketHasToken(header.value, "Upgrade")
        }
        elif Utf8.indexOf(header.name, "Sec-WebSocket-Version", 0, .Latin1NoCase) == 0 and header.name.count == 21
        {
            versionCount += 1
            hasVersion   = header.value == "13"
        }
        elif Utf8.indexOf(header.name, "Sec-WebSocket-Key", 0, .Latin1NoCase) == 0 and header.name.count == 17
        {
            keyCount += 1
            key      = header.value
        }
    }

    if hostCount != 1 or
       upgradeCount != 1 or
       versionCount != 1 or
       keyCount != 1 or
       not hasHost or
       not hasUpgrade or
       not hasConnection or
       not hasVersion do
        fail Errors.InvalidFormatError{"incomplete WebSocket upgrade request"}
    return try webSocketAccept(key.toString())
}

private func webSocketValidClosePayload(payload: const [..] u8)->bool
{
    if payload.count == 0 do
        return true
    if payload.count == 1 do
        return false
    let code = (cast(u32, payload[0]) << 8) | payload[1]
    if not (code == 1000 or
            code == 1001 or
            code == 1002 or
            code == 1003 or
            (code >= 1007 and code <= 1014) or
            (code >= 3000 and code <= 4999)) do
        return false
    return Utf8.isValid(payload[2 to])
}

impl WebSocket
{
    private mtd readByte()->u8 fail
    {
        if .inputOffset == .inputCount
        {
            .inputOffset = 0
            .inputCount  = try .stream.read(.input)
            if .inputCount == 0 do
                fail NetworkError{"WebSocket peer closed the connection", code: 0}
        }

        let value = .input[.inputOffset]
        .inputOffset += 1
        return value
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
                offset       += count
                continue
            }

            let count = try .stream.read(buffer[offset to])
            if count == 0 do
                fail NetworkError{"WebSocket frame ended early", code: 0}
            offset += count
        }
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
                    fail Errors.InvalidFormatError{"HTTP upgrade lines must end with CRLF"}
                return line
            }

            if value == '\n' or (value < ' ' and value != '\t') or value == 0x7F do
                fail Errors.InvalidFormatError{"HTTP upgrade line contains a control character"}
            line.append(value)
        }

        fail Errors.OverflowError{"HTTP upgrade headers exceed the configured limit"}
    }

    private mtd writeAll(bytes: const [..] u8) fail
    {
        var offset = 0'u64
        while offset < bytes.count
        {
            let count = try .stream.write(bytes[offset to])
            if count == 0 do
                fail NetworkError{"WebSocket connection stopped accepting bytes", code: 0}
            offset += count
        }
    }

    // Returns whether this socket still owns a connection.
    mtd const isOpen()->bool => .open

    // Closes the connection; repeated calls do nothing.
    mtd close()
    {
        if .open
        {
            .stream.close()
            .open = false
        }
    }

    // Closes the connection when the owner is dropped.
    mtd opDrop() { .close() }

    // Sends one frame, applying the client mask required by RFC 6455.
    mtd sendFrame(opcode: WebSocketOpcode, payload: const [..] u8, final: bool = true) fail
    {
        if not .open or payload.count > .options.maxFrameBytes do
            fail Errors.BadParameterError{}
        let rawOpcode = cast(u8, opcode)
        if rawOpcode != 0 and
           rawOpcode != 1 and
           rawOpcode != 2 and
           rawOpcode != 8 and
           rawOpcode != 9 and
           rawOpcode != 10 do
            fail Errors.BadParameterError{}
        let control = rawOpcode >= 8
        if control and (not final or payload.count > 125) do
            fail Errors.BadParameterError{}
        if opcode == .Close and not webSocketValidClosePayload(payload) do
            fail Errors.BadParameterError{}
        if opcode == .Continuation
        {
            if not .sendHasFragments do
                fail Errors.BadParameterError{}
            .sendFragmentBytes += payload.count
            if .sendFragmentBytes > .options.maxMessageBytes do
                fail Errors.OverflowError{"WebSocket message exceeds its configured limit"}
            if .sendFragmentOpcode == .Text do
                .sendTextBytes.add(payload)
            if final
            {
                if .sendFragmentOpcode == .Text and not Utf8.isValid(.sendTextBytes.toSlice()) do
                    fail Errors.InvalidFormatError{"WebSocket text message is not valid UTF-8"}
                .sendHasFragments  = false
                .sendFragmentBytes = 0
                .sendTextBytes.clear()
            }
        }
        elif opcode == .Text or opcode == .Binary
        {
            if .sendHasFragments do
                fail Errors.BadParameterError{}
            if payload.count > .options.maxMessageBytes do
                fail Errors.OverflowError{"WebSocket message exceeds its configured limit"}
            if opcode == .Text and final and not Utf8.isValid(payload) do
                fail Errors.InvalidFormatError{"WebSocket text message is not valid UTF-8"}
            if not final
            {
                .sendFragmentOpcode = opcode
                .sendHasFragments   = true
                .sendFragmentBytes  = payload.count
                .sendTextBytes.clear()
                if opcode == .Text do
                    .sendTextBytes.add(payload)
            }
        }

        var header: [14] u8
        var count = 0'u64
        header[count] = (final ? 0x80 : 0) | rawOpcode
        count         += 1
        let masked   = .side == .Client
        let maskFlag = masked ? 0x80'u8 : 0'u8
        if payload.count < 126
        {
            header[count] = maskFlag | cast(u8, payload.count)
            count         += 1
        }
        elif payload.count <= 65535
        {
            header[count]     = maskFlag | 126
            header[count + 1] = cast(u8, payload.count >> 8)
            header[count + 2] = cast(u8, payload.count & 0xFF)
            count             += 3
        }
        else
        {
            header[count] = maskFlag | 127
            for i in 8 do
                header[count + 1 + i] = cast(u8, (payload.count >> ((7 - i) * 8)) & 0xFF)
            count += 9
        }

        var mask: [4] u8
        if masked
        {
            try Crypto.randomBytes(mask)
            for i in mask.count do
                header[count + i] = mask[i]
            count += 4
        }

        try .writeAll(header[0 until count])
        if masked
        {
            var chunk: [4096] u8
            var offset = 0'u64
            while offset < payload.count
            {
                let length = Math.min(chunk.count, payload.count - offset)
                for i in length do
                    chunk[i] = payload[offset + i] ^ mask[(offset + i) & 3]
                try .writeAll(chunk[0 until length])
                offset += length
            }
        }
        else
        {
            try .writeAll(payload)
        }
    }

    // Sends a close frame, answers intervening pings, and waits for the peer's close frame.
    mtd closeGracefully(code: u16 = 1000, reason: string = "") fail
    {
        if reason.count > 123 or not Utf8.isValid(cast(const [..] u8, reason)) do
            fail Errors.BadParameterError{}
        var payload: Array'u8
        payload.add(cast(u8, code >> 8))
        payload.add(cast(u8, code & 0xFF))
        for i in reason.count do
            payload.add(reason[i])
        try .sendFrame(.Close, payload.toSlice())
        while true
        {
            let frame = try .receiveFrame()
            if frame.opcode == .Close
            {
                .close()
                return
            }

            if frame.opcode == .Ping
            {
                try .sendFrame(.Pong, frame.payload.toSlice())
                continue
            }

            if frame.opcode != .Pong do
                fail Errors.InvalidFormatError{"received a data frame during WebSocket close handshake"}
        }
    }

    // Reads one frame and validates masking, control-frame, fragmentation, and size rules.
    mtd receiveFrame()->WebSocketFrame fail
    {
        if not .open do
            fail Errors.BadParameterError{}
        let first  = try .readByte()
        let second = try .readByte()
        let final  = first & 0x80 != 0
        if first & 0x70 != 0 do
            fail Errors.InvalidFormatError{"WebSocket extensions are not negotiated"}
        let rawOpcode = first & 0x0F
        if rawOpcode != 0 and
           rawOpcode != 1 and
           rawOpcode != 2 and
           rawOpcode != 8 and
           rawOpcode != 9 and
           rawOpcode != 10 do
            fail Errors.InvalidFormatError{"invalid WebSocket opcode"}
        let opcode = try webSocketOpcode(rawOpcode)
        let masked = second & 0x80 != 0
        if masked != (.side == .Server) do
            fail Errors.InvalidFormatError{"WebSocket frame has invalid masking for its peer"}
        var length = cast(u64, second & 0x7F)
        if length == 126
        {
            length = (cast(u64, try .readByte()) << 8) | try .readByte()
            if length < 126 do
                fail Errors.InvalidFormatError{"WebSocket frame uses a non-canonical length"}
        }
        elif length == 127
        {
            length = 0
            for 8 do
                length = (length << 8) | try .readByte()
            if length < 65536 or length & 0x80000000_00000000 do
                fail Errors.InvalidFormatError{"invalid WebSocket 64-bit frame length"}
        }

        if length > .options.maxFrameBytes do
            fail Errors.OverflowError{"WebSocket frame exceeds its configured limit"}
        let control = rawOpcode >= 8
        if control and (not final or length > 125) do
            fail Errors.InvalidFormatError{"invalid WebSocket control frame"}
        if opcode == .Continuation
        {
            if not .recvHasFragments do
                fail Errors.InvalidFormatError{"unexpected WebSocket continuation frame"}
            .recvFragmentBytes += length
            if .recvFragmentBytes > .options.maxMessageBytes do
                fail Errors.OverflowError{"WebSocket message exceeds its configured limit"}
        }
        elif opcode == .Text or opcode == .Binary
        {
            if .recvHasFragments do
                fail Errors.InvalidFormatError{"new WebSocket message started before fragments ended"}
            if length > .options.maxMessageBytes do
                fail Errors.OverflowError{"WebSocket message exceeds its configured limit"}
            if not final
            {
                .recvFragmentOpcode = opcode
                .recvHasFragments   = true
                .recvFragmentBytes  = length
                .recvTextBytes.clear()
            }
        }

        var mask: [4] u8
        if masked do
            try .readExact(mask)
        var result: WebSocketFrame
        result.opcode = opcode
        result.final  = final
        result.payload.resize(length)
        try .readExact(result.payload.toSlice())
        if masked do
            for i in length do
                result.payload[i] ^= mask[i & 3]
        if opcode == .Text
        {
            if final
            {
                if not Utf8.isValid(result.payload.toSlice()) do
                    fail Errors.InvalidFormatError{"WebSocket text message is not valid UTF-8"}
            }
            else
            {
                .recvTextBytes.add(result.payload.toSlice())
            }
        }
        elif opcode == .Continuation and .recvFragmentOpcode == .Text
        {
            .recvTextBytes.add(result.payload.toSlice())
            if final
            {
                if not Utf8.isValid(.recvTextBytes.toSlice()) do
                    fail Errors.InvalidFormatError{"WebSocket text message is not valid UTF-8"}
                .recvTextBytes.clear()
            }
        }

        if opcode == .Close and not webSocketValidClosePayload(result.payload.toSlice()) do
            fail Errors.InvalidFormatError{"invalid WebSocket close payload"}
        if opcode == .Continuation and final
        {
            .recvHasFragments  = false
            .recvFragmentBytes = 0
        }

        return result
    }

    // Starts a client WebSocket handshake and verifies the server's HTTP upgrade response.
    func connect(host: string, port: u16 = 80, path: string = "/", options: WebSocketOptions = {})->WebSocket fail
    {
        if host.count == 0 or path.count == 0 or path[0] != '/' do
            fail Errors.BadParameterError{}
        for byte in host do
            if byte == '\r' or byte == '\n' or byte == 0 do
                fail Errors.BadParameterError{}
        for byte in path do
            if byte == '\r' or byte == '\n' or byte == ' ' or byte == 0 do
                fail Errors.BadParameterError{}
        let endpoints = try Dns.resolve(host, port)
        if endpoints.isEmpty() do
            fail NetworkError{"host name resolution returned no addresses", code: -5}
        var stream: TcpStream
        var connected = false
        var lastCode  = 0's32
        for endpoint in endpoints
        {
            var candidate: TcpStream
            var error:     Swag.Error
            candidate = catch TcpStream.connect(endpoint) as error
            {
                if error.value() is NetworkError as networkError do
                    lastCode = networkError.code
                continue
            }

            stream    = #move candidate
            connected = true
            break
        }

        if not connected do
            fail NetworkError{"could not connect to any resolved WebSocket address", code: lastCode}
        var result = WebSocket{stream: #move stream, side: .Client, options: options, open: true}
        var nonce: [16] u8
        try Crypto.randomBytes(nonce)
        let key           = Base64.encode(nonce)
        let authorityHost = Utf8.indexOf(host, ":") == Swag.U64.Max ? host : Format.toString("[%]", host)
        let authority     = port == 80 ? authorityHost : Format.toString("%:%", authorityHost, port)
        let request       = Format.toString("GET % HTTP/1.1\r\nHost: %\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %\r\nSec-WebSocket-Version: 13\r\n\r\n", path, authority, key)
        try result.writeAll(cast(const [..] u8, request))
        let status = try result.readLine(8192)
        if not webSocketIsSwitchingProtocols(status) do
            fail Errors.InvalidFormatError{"server rejected the WebSocket upgrade"}
        var upgrade         = false
        var connection      = false
        var accept: String
        var upgradeCount    = 0
        var connectionCount = 0
        var acceptCount     = 0
        var headerBytes     = status.count + 2
        for
        {
            let line = try result.readLine(8192)
            headerBytes += line.count + 2
            if headerBytes > 64 * 1024 do
                fail Errors.OverflowError{"WebSocket upgrade headers exceed the configured limit"}
            if line.count == 0 do
                break
            let colon = Utf8.indexOf(line, ":")
            if colon == 0 or colon == Swag.U64.Max do
                fail Errors.InvalidFormatError{"invalid WebSocket upgrade response header"}
            let name  = line[until colon]
            let value = Latin1.trim(line[colon + 1 to])
            if Utf8.indexOf(name, "Upgrade", 0, .Latin1NoCase) == 0 and name.count == 7
            {
                upgradeCount += 1
                upgrade      = webSocketHasToken(value, "websocket")
            }
            elif Utf8.indexOf(name, "Connection", 0, .Latin1NoCase) == 0 and name.count == 10
            {
                connectionCount += 1
                connection      = webSocketHasToken(value, "Upgrade")
            }
            elif Utf8.indexOf(name, "Sec-WebSocket-Accept", 0, .Latin1NoCase) == 0 and name.count == 20
            {
                acceptCount += 1
                accept      = String.from(value)
            }
        }

        if upgradeCount != 1 or
           connectionCount != 1 or
           acceptCount != 1 or
           not upgrade or
           not connection or
           accept != try webSocketAccept(key) do
            fail Errors.InvalidFormatError{"server returned an invalid WebSocket upgrade response"}
        return result
    }
}
