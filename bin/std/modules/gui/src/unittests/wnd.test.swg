#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core

// Parenting, child enumeration and lookup by id.
#test
{
    var host: GuiHeadlessHost
    host.setup(200, 200)

    let container = Wnd.create'Wnd(&host.root, null, {0, 0, 200, 200})
    let a = Wnd.create'Wnd(container, null, {0, 0, 50, 50}, "Wnd.A")
    let b = Wnd.create'Wnd(container, null, {0, 0, 50, 50}, "Wnd.B")

    @assert(container.childs.count == 2)
    @assert(a.parent == container)
    @assert(container.isParentOf(a))
    @assert(host.root.isParentOf(a))
    @assert(!a.isParentOf(container))

    @assert(container.getChildById("Wnd.A") == a)
    @assert(container.getChildById("Wnd.B") == b)
    @assert(container.getChildById("Wnd.None") == null)

    host.shutdown()
}

// Hidden state and its propagation to children.
#test
{
    var host: GuiHeadlessHost
    host.setup(200, 200)

    let container = Wnd.create'Wnd(&host.root, null, {0, 0, 200, 200})
    let child     = Wnd.create'Wnd(container, null, {0, 0, 50, 50})

    @assert(child.isVisible())
    @assert(child.isVisibleState())

    child.hide()
    @assert(!child.isVisible())
    @assert(child.isHidden())
    @assert(!child.isVisibleState())

    child.show()
    @assert(child.isVisible())

    // A hidden parent hides the child, but the child keeps its own visible state.
    container.hide()
    @assert(!child.isVisible())
    @assert(child.isVisibleState())
    @assert(child.isVisible(true))

    host.shutdown()
}

// Disabled state and its propagation to children.
#test
{
    var host: GuiHeadlessHost
    host.setup(200, 200)

    let container = Wnd.create'Wnd(&host.root, null, {0, 0, 200, 200})
    let child     = Wnd.create'Wnd(container, null, {0, 0, 50, 50})

    @assert(child.isEnabled())

    child.disable()
    @assert(!child.isEnabled())
    @assert(child.isDisabled())

    child.enable()
    @assert(child.isEnabled())

    // A disabled parent disables the child, but the child keeps its own state.
    container.disable()
    @assert(!child.isEnabled())
    @assert(child.isEnabled(true))

    host.shutdown()
}

// Move/resize and coordinate conversion through the parent chain.
#test
{
    var host: GuiHeadlessHost
    host.setup(200, 200)

    let container = Wnd.create'Wnd(&host.root, null, {10, 20, 180, 160})
    let child     = Wnd.create'Wnd(container, null, {30, 40, 50, 50})

    // child is at container(10,20) + local(30,40) in surface space.
    @assert(child.localToSurface(Math.Point{0, 0}) == Math.Point{40, 60})
    @assert(child.surfaceToLocal({40, 60}) == Math.Point{0, 0})
    @assert(child.surfaceToLocal(child.localToSurface(Math.Point{7, 9})) == Math.Point{7, 9})

    child.move(15, 25)
    @assert(child.position.x == 15)
    @assert(child.position.y == 25)
    @assert(child.localToSurface(Math.Point{0, 0}) == Math.Point{25, 45})

    child.resize(80, 60)
    @assert(child.position.width == 80)
    @assert(child.position.height == 60)

    child.setPosition({0, 0, 100, 100})
    @assert(child.position == Math.Rectangle{0, 0, 100, 100})

    host.shutdown()
}

// Dock layout: Left/Right consume edges, Center fills the rest.
#test
{
    var host: GuiHeadlessHost
    host.setup(220, 140)

    let container = Wnd.create'Wnd(&host.root, null, {0, 0, 200, 100})
    let left      = Wnd.create'Wnd(container, null, {0, 0, 40, 0})
    let right     = Wnd.create'Wnd(container, null, {0, 0, 30, 0})
    let center    = Wnd.create'Wnd(container, null, {0, 0, 0, 0})

    left.dockStyle   = .Left
    right.dockStyle  = .Right
    center.dockStyle = .Center
    container.applyLayout()

    @assert(left.position == Math.Rectangle{0, 0, 40, 100})
    @assert(right.position == Math.Rectangle{170, 0, 30, 100})
    @assert(center.position == Math.Rectangle{40, 0, 130, 100})

    host.shutdown()
}

// getWndAt descends the hierarchy and skips hidden/disabled by default.
#test
{
    var host: GuiHeadlessHost
    host.setup(200, 200)

    let container = Wnd.create'Wnd(&host.root, null, {10, 10, 180, 180})
    let child     = Wnd.create'Wnd(container, null, {20, 20, 60, 60})

    // Surface point (40,40) -> container(10,10) -> child local (20,20): inside child.
    @assert(host.root.getWndAt(40, 40, true) == child)
    // A point inside the container but outside the child resolves to the container.
    @assert(host.root.getWndAt(160, 160, true) == container)

    child.hide()
    @assert(host.root.getWndAt(40, 40, true) == container)
    child.show()

    // Disabled is skipped unless getDisabled is set.
    child.disable()
    @assert(host.root.getWndAt(40, 40, false) == container)
    @assert(host.root.getWndAt(40, 40, true) == child)

    host.shutdown()
}

// Z-order: getWndAt returns the topmost (last) sibling; bringToFront/bringToTop reorder.
#test
{
    var host: GuiHeadlessHost
    host.setup(200, 200)

    let container = Wnd.create'Wnd(&host.root, null, {0, 0, 200, 200})
    let a = Wnd.create'Wnd(container, null, {0, 0, 100, 100})
    let b = Wnd.create'Wnd(container, null, {0, 0, 100, 100})

    // b was added last -> painted on top -> hit first.
    @assert(host.root.getWndAt(50, 50, true) == b)

    a.bringToTop()
    @assert(container.childs.back() == a)
    @assert(host.root.getWndAt(50, 50, true) == a)

    b.bringToFront()
    @assert(container.childs.front() == b)
    @assert(host.root.getWndAt(50, 50, true) == a)

    host.shutdown()
}

// destroy() detaches the window from its parent after the destroy pump.
#test
{
    var host: GuiHeadlessHost
    host.setup(200, 200)

    let container = Wnd.create'Wnd(&host.root, null, {0, 0, 200, 200})
    let child     = Wnd.create'Wnd(container, null, {0, 0, 50, 50})
    @assert(container.childs.count == 1)

    child.destroy()
    host.pump()
    @assert(container.childs.count == 0)

    host.shutdown()
}
