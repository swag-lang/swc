#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Crossing a power-of-two client width must not double the backing allocation. Nearby sizes
// reuse it, and growing the other axis must not discard the width already reserved for a drag.
#test
{
    var host: Testing.HeadlessHost
    host.setup(2048, 64)
    defer host.shutdown()

    host.surface.paintWnd(&host.root)
    Swag.assert(host.surface.rt.colorBuffer.width == 2048)

    host.surface.setPosition({0, 0, 2049, 64})
    host.surface.paintWnd(&host.root)
    let capacity = host.surface.rt.colorBuffer.width
    Swag.assert(capacity >= 2049 and capacity < 2049 + 256)
    let handle = host.surface.rt.handle

    host.surface.setPosition({0, 0, 2050, 64})
    host.surface.paintWnd(&host.root)
    Swag.assert(host.surface.rt.handle == handle)

    host.surface.setPosition({0, 0, 512, 257})
    host.surface.paintWnd(&host.root)
    Swag.assert(host.surface.rt.colorBuffer.width == capacity)
    Swag.assert(host.surface.rt.colorBuffer.height >= 257 and host.surface.rt.colorBuffer.height < 257 + 256)
    let tallerHandle = host.surface.rt.handle

    host.surface.setPosition({0, 0, 2049, 257})
    host.surface.paintWnd(&host.root)
    Swag.assert(host.surface.rt.handle == tallerHandle)
}

// Painting the final geometry consumes the pending dirty region before returning.
//
// The platform layer presents from inside the geometry transaction that changed the window, and
// a frame abandoned there stays abandoned: the application loop that normally picks a pending
// region up is suspended for the whole of a border drag.
#test
{
    var host: Testing.HeadlessHost
    host.setup(256, 128)
    defer host.shutdown()

    host.surface.invalidate()
    host.surface.paint()
    Swag.assert(not host.surface.isDirty, "a synchronous paint leaves nothing pending")
}
