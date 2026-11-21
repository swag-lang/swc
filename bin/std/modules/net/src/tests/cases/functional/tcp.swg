#global if #command == Swag.CompilerCommand.Test
#global private

using Core

#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect listener.localEndpoint()
    Swag.require(endpoint.port != 0)

    var client = expect TcpStream.connect(endpoint)
    var server = expect listener.accept()
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

    var closedReadError: Swag.Error
    discard catch client.read(bytes) as closedReadError
    Swag.require(closedReadError.value() is Errors.BadParameterError)

    var closedWriteError: Swag.Error
    discard catch client.write(payload) as closedWriteError
    Swag.require(closedWriteError.value() is Errors.BadParameterError)

    var unopened: TcpStream
    var unopenedReadError: Swag.Error
    discard catch unopened.read(bytes) as unopenedReadError
    Swag.require(unopenedReadError.value() is Errors.BadParameterError)
}

#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect listener.localEndpoint()
    listener.close()
    listener.close()

    var closedEndpointError: Swag.Error
    discard catch listener.localEndpoint() as closedEndpointError
    Swag.require(closedEndpointError.value() is Errors.BadParameterError)

    var closedAcceptError: Swag.Error
    discard catch listener.accept() as closedAcceptError
    Swag.require(closedAcceptError.value() is Errors.BadParameterError)

    var unopened: TcpListener
    var unopenedEndpointError: Swag.Error
    discard catch unopened.localEndpoint() as unopenedEndpointError
    Swag.require(unopenedEndpointError.value() is Errors.BadParameterError)

    var outcome: Swag.Error
    discard catch TcpStream.connect(endpoint) as outcome
    Swag.require(outcome.value() != null)
}
