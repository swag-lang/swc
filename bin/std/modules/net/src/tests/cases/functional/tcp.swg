#global if #command == Swag.CompilerCommand.Test
#global private

#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    var client   = expect TcpStream.connect(expect listener.localEndpoint())
    var server   = expect listener.accept()
    expect server.setReadTimeout(50)

    var buffer: [8] u8
    var error:  Swag.Error
    discard catch server.read(buffer) as error
    Swag.require(error.value() is NetworkError)
}

#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect listener.localEndpoint()
    Swag.require(endpoint.port != 0)

    var client = expect TcpStream.connect(endpoint)
    var server = expect listener.accept()
    expect client.setNoDelay(true)
    expect client.setNoDelay(false)
    expect client.setKeepAlive(true)
    expect client.setKeepAlive(false)
    expect client.setWriteTimeout(50)
    expect client.setWriteTimeout(0)
    listener.close()
    var bytes: [16] u8
    let emptyRead  = expect server.read(bytes[0 until 0])
    let emptyWrite = expect client.write(bytes[0 until 0])
    Swag.require(emptyRead == 0 and emptyWrite == 0)
    let payload = cast(const [..] u8, "hello")
    var written = 0'u64
    while written < payload.count
    {
        let count = expect client.write(payload[written to])
        Swag.require(count != 0)
        written += count
    }

    var read = 0'u64
    while read < payload.count
    {
        let count = expect server.read(bytes[read until read + 1])
        Swag.require(count == 1)
        read += count
    }

    Swag.require(cast(string, bytes[0 until read]) == "hello")

    client.close()
    client.close()
    let end = expect server.read(bytes)
    Swag.require(end == 0 and not client.isOpen())
}

// Half-closing the send side delivers EOF without preventing the peer's response.
#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    var client   = expect TcpStream.connect(expect listener.localEndpoint())
    var server   = expect listener.accept()
    let request  = cast(const [..] u8, "request")
    Swag.require(expect client.write(request) == request.count)
    expect client.shutdownWrite()

    var received: String
    var buffer:   [32] u8
    for
    {
        let count = expect server.read(buffer)
        if count == 0 do
            break
        received.append(cast(string, buffer[0 until count]))
    }

    Swag.require(received.toString() == "request")
    let response = cast(const [..] u8, "response")
    Swag.require(expect server.write(response) == response.count)
    server.close()

    received.clear()
    for
    {
        let count = expect client.read(buffer)
        if count == 0 do
            break
        received.append(cast(string, buffer[0 until count]))
    }

    Swag.require(received.toString() == "response")
}

#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    var client   = expect TcpStream.connect(expect listener.localEndpoint())
    var server   = expect listener.accept()
    let request  = cast(const [..] u8, "whole request")
    Swag.require(expect client.writeAll(request) == request.count)
    var received: [13] u8
    Swag.require(expect server.readExact(received) == received.count)
    Swag.require(received == request)

    let response = cast(const [..] u8, "whole response")
    Swag.require(expect server.writeAll(response) == response.count)
    var returned: [14] u8
    Swag.require(expect client.readExact(returned) == returned.count)
    Swag.require(returned == response)

    Swag.require(expect client.writeAll(request[0 until 0]) == 0)
    Swag.require(expect server.readExact(received[0 until 0]) == 0)

    server.close()
    var error: Swag.Error
    discard catch client.readExact(received) as error
    Swag.require(error.value() is NetworkError)
}

#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect listener.localEndpoint()
    listener.close()
    listener.close()

    var outcome: Swag.Error
    discard catch TcpStream.connect(endpoint) as outcome
    Swag.require(outcome.value() != null)
}
