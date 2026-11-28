#global if #command == Swag.CompilerCommand.Test
#global if WINDOWS
#global private

#[Swag.TestTag("integration.desktop")]
#test
{
    for monitor in Env.getMonitors()
    {
        let physicalWidth = monitor.physicalBounds.width
        let logicalWidth  = monitor.bounds.width
        Swag.require(logicalWidth > 0)
        Swag.require(monitor.scaleFactor == cast(f32, physicalWidth) / cast(f32, logicalWidth))
    }
}
