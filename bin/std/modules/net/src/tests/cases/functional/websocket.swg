#global if #command == Swag.CompilerCommand.Test
#global private

using Core

struct WebSocketServerFixture
{
    late listener: *Http.Server
}

func serveWebSocket(thread: const *Threading.Thread)
{
    let fixture = cast(*WebSocketServerFixture, unwrap thread.userParam)
    var connection = expect fixture.listener.accept()
    let request = expect connection.readRequest()
    var socket = expect connection.upgradeWebSocket(request)

    let first = expect socket.receiveFrame()
    Swag.require(first.opcode == .Text and not first.final and cast(string, first.payload.toSlice()) == "hel")
    let second = expect socket.receiveFrame()
    Swag.require(second.opcode == .Continuation and second.final and cast(string, second.payload.toSlice()) == "lo")
    let utf8First = expect socket.receiveFrame()
    Swag.require(utf8First.opcode == .Text and not utf8First.final and utf8First.payload[0] == 0xC3)
    let utf8Last = expect socket.receiveFrame()
    Swag.require(utf8Last.opcode == .Continuation and utf8Last.final and utf8Last.payload[0] == 0xA9)
    let extended = expect socket.receiveFrame()
    Swag.require(extended.opcode == .Binary and extended.payload.count == 126 and
                 extended.payload[0] == 0x5A and extended.payload[125] == 0x5A)
    let extended64 = expect socket.receiveFrame()
    Swag.require(extended64.opcode == .Binary and extended64.payload.count == 65536 and
                 extended64.payload[0] == 0xA5 and extended64.payload[65535] == 0xA5)

    expect socket.sendFrame(.Binary, cast(const [..] u8, "OK"))
    expect socket.sendFrame(.Ping, cast(const [..] u8, "?"))
    let pong = expect socket.receiveFrame()
    Swag.require(pong.opcode == .Pong and cast(string, pong.payload.toSlice()) == "?")

    let close = expect socket.receiveFrame()
    Swag.require(close.opcode == .Close and close.payload.count == 2)
    expect socket.sendFrame(.Ping, cast(const [..] u8, "closing"))
    let closePong = expect socket.receiveFrame()
    Swag.require(closePong.opcode == .Pong and cast(string, closePong.payload.toSlice()) == "closing")
    expect socket.sendFrame(.Close, close.payload.toSlice())
    socket.close()
}

// The handshake accept value matches the RFC 6455 sample.
#test
{
    Swag.require(expect webSocketAccept("dGhlIHNhbXBsZSBub25jZQ==") == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    var error: Swag.Error
    discard catch webSocketAccept("dGhlIHNhbXBsZSBub25jZQ") as error
    Swag.require(error.value() is Errors.InvalidFormatError)
    var request: Http.ServerRequest
    discard catch webSocketValidateUpgrade(request) as error
    Swag.require(error.value() is Errors.InvalidFormatError)
}

// The client and server complete an upgrade and exchange masked, fragmented, and control frames.
#test
{
    var server = expect Http.Server.listen({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect server.localAddress()
    var fixture = WebSocketServerFixture{listener: &server}
    var thread: Threading.Thread
    expect thread.init(&serveWebSocket, &fixture)
    expect thread.start()

    var client = expect WebSocket.connect("localhost", endpoint.port, "/socket")
    var invalidText: Swag.Error
    let invalidUtf8: [1] u8 = [0xFF]
    discard catch client.sendFrame(.Text, invalidUtf8) as invalidText
    Swag.require(invalidText.value() is Errors.InvalidFormatError)
    var invalidClose: Swag.Error
    let reservedCloseCode: [2] u8 = [3, 237]
    discard catch client.sendFrame(.Close, reservedCloseCode) as invalidClose
    Swag.require(invalidClose.value() is Errors.BadParameterError)
    expect client.sendFrame(.Text, cast(const [..] u8, "hel"), false)
    expect client.sendFrame(.Continuation, cast(const [..] u8, "lo"))
    let utf8First: [1] u8 = [0xC3]
    let utf8Last: [1] u8 = [0xA9]
    expect client.sendFrame(.Text, utf8First, false)
    expect client.sendFrame(.Continuation, utf8Last)
    var extended: Array'u8
    extended.resize(126)
    for i in extended.count do
        extended[i] = 0x5A
    expect client.sendFrame(.Binary, extended.toSlice())
    var extended64: Array'u8
    extended64.resize(65536)
    for i in extended64.count do
        extended64[i] = 0xA5
    expect client.sendFrame(.Binary, extended64.toSlice())
    let response = expect client.receiveFrame()
    Swag.require(response.opcode == .Binary and cast(string, response.payload.toSlice()) == "OK")
    let ping = expect client.receiveFrame()
    Swag.require(ping.opcode == .Ping and cast(string, ping.payload.toSlice()) == "?")
    expect client.sendFrame(.Pong, ping.payload.toSlice())

    expect client.closeGracefully()
    Swag.require(not client.isOpen())
    thread.wait()
}
