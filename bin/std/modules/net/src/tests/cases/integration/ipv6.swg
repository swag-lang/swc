#global if #command == Swag.CompilerCommand.Test
#global private

#[Swag.TestTag("integration.network")]
#test
{
    let loopback = IpAddress.ipv6([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])
    var listener = expect TcpListener.listen({address: loopback, port: 0})
    let endpoint = expect listener.localAddress()
    Swag.require(endpoint.address.isIPv6() and endpoint.address.bytes[15] == 1)

    var client = expect TcpStream.connect(endpoint)
    var server = expect listener.accept()
    Swag.require(expect client.write(cast(const [..] u8, "v6")) == 2)
    var bytes: [2] u8
    Swag.require(expect server.read(bytes) == 2 and cast(string, bytes[0 to]) == "v6")

    var receiver = expect DatagramSocket.bind({address: loopback, port: 0})
    let target = expect receiver.localAddress()
    var sender = expect DatagramSocket.bind({address: loopback, port: 0})
    Swag.require(expect sender.sendTo(target, cast(const [..] u8, "udp6")) == 4)
    var payload: [8] u8
    let datagram = expect receiver.receiveFrom(payload)
    Swag.require(datagram.endpoint.address.isIPv6() and not datagram.truncated)
    Swag.require(cast(string, payload[0 until datagram.count]) == "udp6")
}
