/*
Net provides blocking IPv4 TCP connections, bounded HTTP GET requests and URL helpers.

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

Streams own their connections and close them on drop. Operations can fail and may transfer fewer
bytes than requested. Networking is available on Windows in this implementation.

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

HTTPS uses the Windows trust store. Requests have bounded response bodies and return redirects
without following them, so the caller can decide which destinations are acceptable.
*/
#import("core")
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
