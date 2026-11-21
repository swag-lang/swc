#global if #command == Swag.CompilerCommand.Test
#global private

using Core

#test
{
    let addresses = expect Dns.resolve("localhost", 8080, {family: .IPv4})
    Swag.require(not addresses.isEmpty())
    for endpoint in addresses do
        Swag.require(endpoint.address.isIPv4() and endpoint.port == 8080)
}

#test
{
    let addresses = expect Dns.resolve("localhost", "http", {family: .IPv4})
    Swag.require(not addresses.isEmpty())
    for endpoint in addresses do
        Swag.require(endpoint.address.isIPv4() and endpoint.port == 80)
}

#test
{
    let ipv4 = IpAddress.ipv4([192, 0, 2, 10])
    Swag.require(ipv4.isIPv4() and ipv4.bytes[0] == 192 and ipv4.bytes[3] == 10)
    let ipv6 = IpAddress.ipv6([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])
    Swag.require(ipv6.isIPv6() and ipv6.bytes[15] == 1)
}

#test
{
    var empty, embeddedZero, emptyService, unknownService: Swag.Error
    discard catch Dns.resolve("") as empty
    discard catch Dns.resolve("local\0host") as embeddedZero
    discard catch Dns.resolve("localhost", "") as emptyService
    discard catch Dns.resolve("localhost", "swag-no-such-service") as unknownService
    Swag.require(empty.value() is Errors.BadParameterError)
    Swag.require(embeddedZero.value() is Errors.BadParameterError)
    Swag.require(emptyService.value() is Errors.BadParameterError)
    Swag.require(unknownService.value() is NetworkError)
}
