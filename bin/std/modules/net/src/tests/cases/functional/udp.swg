#global if #command == Swag.CompilerCommand.Test
#global private

using Core

#test
{
    var receiver = expect DatagramSocket.bind({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect receiver.localAddress()
    Swag.require(endpoint.address.isIPv4() and endpoint.port != 0)

    var sender  = expect DatagramSocket.bind({address: [127, 0, 0, 1], port: 0})
    let payload = cast(const [..] u8, "one datagram")
    Swag.require(expect sender.sendTo(endpoint, payload) == payload.count)

    var buffer: [32] u8
    let message = expect receiver.receiveFrom(buffer)
    Swag.require(not message.truncated and message.count == payload.count)
    Swag.require(message.endpoint.address.isIPv4() and message.endpoint.port != 0)
    Swag.require(buffer[0 until message.count] == payload)

    let empty = cast(const [..] u8, "")[0 until 0]
    Swag.require(expect sender.sendTo(endpoint, empty) == 0)
    let emptyMessage = expect receiver.receiveFrom(buffer)
    Swag.require(emptyMessage.count == 0 and not emptyMessage.truncated)

    sender.close()
    sender.close()
    Swag.require(not sender.isOpen())
}

// Broadcast permission and IPv4 multicast membership are controlled on the owned socket.
#test
{
    var socket = expect DatagramSocket.bind({address: [0, 0, 0, 0], port: 0})
    expect socket.setBroadcast(true)
    expect socket.setBroadcast(false)

    let group = IpAddress.ipv4([239, 1, 2, 3])
    expect socket.joinMulticast(group)
    expect socket.leaveMulticast(group)

    var error: Swag.Error
    discard catch socket.joinMulticast(IpAddress.ipv4([192, 0, 2, 1])) as error
    Swag.require(error.value() is Errors.BadParameterError)
}

#test
{
    #static if #os == Swag.TargetOs.Linux
    {
        let anyAddress = IpAddress.ipv6([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        let group      = IpAddress.ipv6([0xFF, 0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x14])
        var socket     = expect DatagramSocket.bind({address: anyAddress, port: 0})
        expect socket.joinMulticast(group, {interfaceIndex: 1})
        expect socket.leaveMulticast(group, {interfaceIndex: 1})
    }

    #static if #os == Swag.TargetOs.Windows
    {
        let anyAddress = IpAddress.ipv6([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        let group      = IpAddress.ipv6([0xFF, 0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x14])
        var socket     = expect DatagramSocket.bind({address: anyAddress, port: 0})
        expect socket.joinMulticast(group, {interfaceIndex: 1})
        expect socket.leaveMulticast(group, {interfaceIndex: 1})
    }
}

#test
{
    var receiver = expect DatagramSocket.bind({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect receiver.localAddress()
    var sender   = expect DatagramSocket.bind({address: [127, 0, 0, 1], port: 0})
    Swag.require(expect sender.sendTo(endpoint, cast(const [..] u8, "oversized")) == 9)

    var buffer: [4] u8
    let message = expect receiver.receiveFrom(buffer)
    Swag.require(message.count == buffer.count and message.truncated)
    Swag.require(buffer == [cast(u8, 'o'), cast(u8, 'v'), cast(u8, 'e'), cast(u8, 'r')])
}
