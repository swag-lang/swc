#global if #command == Swag.CompilerCommand.Test
#global private

struct ResizeLayoutWnd
{
    using wnd: Wnd
    layouts:   u32
}

impl IWnd for ResizeLayoutWnd
{
    mtd impl onLayout()
    {
        .layouts += 1
    }
}

// Reapplying a stable size must not restart layout all the way to the surface root.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    let child = Wnd.create'ResizeLayoutWnd(&host.root, null, {0, 0, 80, 40})
    host.pump()
    let baseline = child.layouts

    for 20
    {
        child.resize(80.2, 40.2)
        host.pump()
        Swag.assert(child.layouts == baseline)
    }

    child.resize(100, 50)
    host.pump()
    Swag.assert(child.layouts > baseline)
    Swag.assert(child.preferredSize == Math.Point{100, 50})
    let resized = child.layouts

    // A container can arrange a different size without changing what the child prefers.
    child.resize(120, 60, computeLayout: false)
    Swag.assert(child.preferredSize == Math.Point{100, 50})
    child.resize(120, 60)
    host.pump()
    Swag.assert(child.layouts > resized)
    Swag.assert(child.preferredSize == Math.Point{120, 60})
}
