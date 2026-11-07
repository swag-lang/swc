#global if WINDOWS and #hastag("vault.integration")

using Core

namespace Integration
{
    const PreviewContainerSize = 512'u64 * 1024 * 1024

    #[Swag.Propagate]
    func runPreviewMount() fail
    {
        let args = Env.arguments()
        var box  = Sandbox.create()
        defer box.cleanup()

        var created = Volume.create(box.container, "", PreviewContainerSize)
        created.close()
        box.mountVolume("")
        File.writeAllText(args[2], Format.toString("%\n%\n%\n", box.mountPoint, box.root, box.container))
        Console.println("Preview test drive mounted at ", box.mountPoint)

        // The external stop file releases the test drive when its owner is done inspecting it.
        let stopPath = Path.combine(box.root, "stop")
        while not File.exists(stopPath) do
            Threading.Thread.sleep(250'ms)

        box.closeSandbox()
    }

    func runPreviewMountAndExit()
    {
        discard catch runPreviewMount()
        {
            Console.println("FAIL: ", errorMessage(Swag.err))
            Env.exit(1)
        }
        Env.exit(0)
    }
}
