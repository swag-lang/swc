/*
Net provides blocking TCP and UDP, DNS resolution, bounded HTTP requests and servers, and URL helpers.

## Connect over TCP

```swag
#import("net")
using Net

#main
{
    var connection = try TcpStream.connect({address: [127, 0, 0, 1], port: 8080})
    let request = cast(const [..] u8, "hello")
    var offset = 0'u64
    while offset < request.count
    {
        let sent = try connection.write(request[offset to])
        if sent == 0 do
            break
        offset += sent
    }
}
```

Streams own their connections and close them on drop. TCP and UDP support IPv4 and IPv6 on Linux
and Windows. TCP streams support half-closing their send side, and operations can fail or transfer
fewer bytes than requested. DNS resolution
preserves the platform resolver's address order and resolves named services. DNS lookup is
synchronous and cannot be cancelled. HTTP and HTTPS clients and the HTTP/1.1 server are
available on Windows and Linux.
An HTTP server handles one request per connection and closes each response; closing the server
stops its listener while accepted connections remain independent.

## Request an HTTPS resource

```swag
#import("net")
using Core, Net

#main
{
    let target = try Url.parseHttp("https://example.com/?q=swag")
    let response = try Http.get(target.host, target.port, target.path, target.secure)
    if response.status == 200 do
        Console.println(cast(string, response.body.toSlice()))
}
```

HTTPS verifies certificates and host names against the platform trust roots. Linux loads
`libcurl.so.4` on the first HTTP request and needs thread-safe initialization and asynchronous DNS
support; TCP-only programs do not load it. Standard proxy settings remain effective, including
`NO_PROXY`. `SSL_CERT_FILE` and `SSL_CERT_DIR` override Linux CA roots for the server and HTTPS proxy.
Requests have bounded response bodies and return redirects without following them, so the caller
can decide which destinations are acceptable. [[Net.Http.get]] documents timeout and header limits.

## Exchange WebSocket frames

```swag
#import("net")
using Core, Net

#main
{
    var peer = try WebSocket.connect("example.com", 80, "/events")
    try peer.sendFrame(.Text, cast(const [..] u8, "hello"))
    let frame = try peer.receiveFrame()
    if frame.opcode == .Text do
        Console.println(cast(string, frame.payload.toSlice()))
}
```

The client and server validate RFC 6455 upgrades and frame masking. Frames remain visible to the
caller, including fragments and control frames; `closeGracefully` performs the close handshake.
`WebSocket.connect` currently uses an unencrypted `ws://` transport. HTTPS requests verify TLS
certificates, but the module does not yet expose a reusable TLS stream.
*/
#import("core")
#static if #os == Swag.TargetOs.Linux
{
    #import("linux")
}

#static if #os == Swag.TargetOs.Windows do
    #import("win32")

#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleVersion     = #swcversion
    cfg.moduleRevision    = #swcrevision
    cfg.moduleBuildNum    = #swcbuildnum
    cfg.moduleNamespace   = "Net"
    cfg.backendKind       = .SharedLibrary
    cfg.repoPath          = "https://github.com/swag-lang/swc/blob/master/bin/std/modules/net"
    cfg.genDoc.kind       = .Api
    cfg.genDoc.outputName = "std.net"
    cfg.genDoc.icon       = "favicon.svg"
    cfg.genDoc.css        = "css/style.css"
}
