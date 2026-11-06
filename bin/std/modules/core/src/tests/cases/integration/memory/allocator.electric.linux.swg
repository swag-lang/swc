#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux and #hastag("Swag.AllocatorDiagnostics")
#global private

using Swag

private var g_ElectricFaultAllocator: Allocator

func electricFaultPeer(stale: bool)
{
    g_ElectricFaultAllocator.setup()
    g_ElectricFaultAllocator.configure(true, false, false, false, false)
    var request = AllocatorRequest{size: 4096}
    g_ElectricFaultAllocator.allocate(&request)
    Swag.require(request.address != null)

    let address = cast(u64, request.address)
    let header = g_ElectricFaultAllocator.headerOf(address)
    Swag.require(header.isElectric and header.userAddr == address)

    if stale
    {
        g_ElectricFaultAllocator.freeBlock(&request)
        // The reservation remains, but its payload pages are inaccessible after free.
        Swag.memset(cast(*void, address), 0x5A, 1)
    }
    else
    {
        // The first byte after the committed region belongs to the guard page.
        let guard = cast(u64, header.allocAddr) + header.commitSize
        Swag.memset(cast(*void, guard), 0x5A, 1)
    }

    Env.exit(37)
}

#premain
{
    if Env.hasArgument("--swag-electric-guard-peer") do
        electricFaultPeer(false)
    if Env.hasArgument("--swag-electric-stale-peer") do
        electricFaultPeer(true)
}

#[Swag.TestTag("integration.allocator")]
#test
{
    Swag.require(not Swag.jit(), "run electric faults with --no-test-jit")
    for argument in ["--swag-electric-guard-peer", "--swag-electric-stale-peer"]
    {
        let process = expect Env.runProcess(Env.StartInfo{fileName: Env.executablePath(), arguments: [argument],
                                                     standardOutput: .Pipe, standardError: .Pipe})
        Swag.require(process.exitCode() == 139, // Linux SIGSEGV uses signal number 11.
                     String.from(process.standardError()).toString())
    }
}
