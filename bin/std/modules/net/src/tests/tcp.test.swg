#global if #command == Swag.CompilerCommand.Test
#global private

#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect listener.localEndpoint()
    Swag.assert(endpoint.port != 0)

    var client = expect TcpStream.connect(endpoint)
    var server = expect listener.accept()
    listener.close()
    var bytes: [16] u8
    let emptyRead  = expect server.read(bytes[0 until 0])
    let emptyWrite = expect client.write(bytes[0 until 0])
    Swag.assert(emptyRead == 0 and emptyWrite == 0)
    let payload = cast(const [..] u8, "hello")
    var written = 0'u64
    while written < payload.count
    {
        let count = expect client.write(payload[written to])
        Swag.assert(count != 0)
        written += count
    }

    var read = 0'u64
    while read < payload.count
    {
        let count = expect server.read(bytes[read until read + 1])
        Swag.assert(count == 1)
        read += count
    }

    Swag.assert(cast(string, bytes[0 until read]) == "hello")

    client.close()
    client.close()
    let end = expect server.read(bytes)
    Swag.assert(end == 0 and not client.isOpen())
}

#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect listener.localEndpoint()
    listener.close()
    listener.close()

    var outcome: Swag.Error
    discard catch TcpStream.connect(endpoint) as outcome
    Swag.assert(outcome.value() != null)
}
