#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// An unhandled command state is empty in every field. Presenters use UpdatedFields as the sole
// authority for applying state, so stray bits here can randomly hide or rename menu entries.
#test
{
    var host: Testing.HeadlessHost
    host.setup(80, 40)
    defer host.shutdown()

    let state = host.root.sendComputeCommandStateEvent("Wnd.Unhandled")
    @assert(!state.accepted)
    @assert(state.updatedFields == .None)
    @assert(state.renderingHint == .None)
    @assert(!state.disabled and !state.checked and !state.hidden)
    @assert(state.name.isEmpty() and state.longName.isEmpty() and state.shortcut.isEmpty() and state.toolTip.isEmpty())
}

// Parenting, child enumeration and lookup by id.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()
    let container = Wnd.create'Wnd(&host.root, null, {0, 0, 200, 200})
    let a         = Wnd.create'Wnd(container, null, {0, 0, 50, 50}, "Wnd.A")
    let b         = Wnd.create'Wnd(container, null, {0, 0, 50, 50}, "Wnd.B")

    @assert(container.children.count == 2)
    @assert(a.parent == container)
    @assert(container.isAncestorOf(a))
    @assert(host.root.isAncestorOf(a))
    @assert(!a.isAncestorOf(container))

    @assert(container.childById("Wnd.A") == a)
    @assert(container.childById("Wnd.B") == b)
    @assert(container.childById("Wnd.None") == null)
}

// Detaching and reparenting update both sides and propagate the surface through the subtree.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()
    let left       = Wnd.create'Wnd(&host.root, null, {0, 0, 100, 200})
    let right      = Wnd.create'Wnd(&host.root, null, {100, 0, 100, 200})
    let child      = Wnd.create'Wnd(left, null, {0, 0, 50, 50})
    let grandChild = Wnd.create'Wnd(child, null, {0, 0, 20, 20})

    @assert(left.detachChild(child))
    @assert(child.parent == null and child.surface == null)
    @assert(grandChild.surface == null)
    @assert(left.children.count == 0)

    child.setParent(right)
    @assert(child.parent == right and child.surface == right.surface)
    @assert(grandChild.surface == right.surface)
    @assert(right.children.count == 1 and right.children[0] == child)
}

// Hidden state and its propagation to children.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()
    let container = Wnd.create'Wnd(&host.root, null, {0, 0, 200, 200})
    let child     = Wnd.create'Wnd(container, null, {0, 0, 50, 50})

    @assert(child.isVisible())
    @assert(child.isLocallyVisible())

    child.hide()
    @assert(!child.isVisible())
    @assert(child.isHidden())
    @assert(!child.isLocallyVisible())

    child.show()
    @assert(child.isVisible())

    // A hidden parent hides the child, but the child keeps its own visible state.
    container.hide()
    @assert(!child.isVisible())
    @assert(child.isLocallyVisible())
    @assert(child.isLocallyVisible())
}

// Disabled state and its propagation to children.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()
    let container = Wnd.create'Wnd(&host.root, null, {0, 0, 200, 200})
    let child     = Wnd.create'Wnd(container, null, {0, 0, 50, 50})

    @assert(child.isEnabled())
    @assert(child.isLocallyEnabled())

    child.disable()
    @assert(!child.isEnabled())
    @assert(child.isDisabled())
    @assert(!child.isLocallyEnabled())

    child.enable()
    @assert(child.isEnabled())
    @assert(child.isLocallyEnabled())

    // A disabled parent disables the child, but the child keeps its own state.
    container.disable()
    @assert(!child.isEnabled())
    @assert(child.isLocallyEnabled())
    @assert(child.isLocallyEnabled())
}

// Move/resize and coordinate conversion through the parent chain.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()
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
}

// Dock layout: Left/Right consume edges, Center fills the rest.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 140)
    defer host.shutdown()
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
}

// getWndAt descends the hierarchy and skips hidden/disabled by default.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()
    let container = Wnd.create'Wnd(&host.root, null, {10, 10, 180, 180})
    let child     = Wnd.create'Wnd(container, null, {20, 20, 60, 60})

    // Surface point (40,40) -> container(10,10) -> child local (20,20): inside child.
    @assert(host.root.windowAt(40, 40, true) == child)

    // A point inside the container but outside the child resolves to the container.
    @assert(host.root.windowAt(160, 160, true) == container)

    child.hide()
    @assert(host.root.windowAt(40, 40, true) == container)
    child.show()

    // Disabled is skipped unless getDisabled is set.
    child.disable()
    @assert(host.root.windowAt(40, 40, false) == container)
    @assert(host.root.windowAt(40, 40, true) == child)
}

// Z-order: windowAt returns the topmost (last) sibling; sendToBack/bringToFront reorder.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()
    let container = Wnd.create'Wnd(&host.root, null, {0, 0, 200, 200})
    let a         = Wnd.create'Wnd(container, null, {0, 0, 100, 100})
    let b         = Wnd.create'Wnd(container, null, {0, 0, 100, 100})

    // b was added last -> painted on top -> hit first.
    @assert(host.root.windowAt(50, 50, true) == b)

    a.bringToFront()
    @assert(container.children.back() == a)
    @assert(host.root.windowAt(50, 50, true) == a)

    b.sendToBack()
    @assert(container.children.front() == b)
    @assert(host.root.windowAt(50, 50, true) == a)
}

// destroy() detaches the window from its parent after the destroy pump.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()
    let container = Wnd.create'Wnd(&host.root, null, {0, 0, 200, 200})
    let child     = Wnd.create'Wnd(container, null, {0, 0, 50, 50})
    @assert(container.children.count == 1)

    child.destroy()
    host.pump()
    @assert(container.children.count == 0)
}

// A no-scroll window and everything it contains ignore scroll offsets above that boundary in
// painting, hit testing, and coordinate conversion.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 180)
    defer host.shutdown()

    let scroller = Wnd.create'Wnd(&host.root, null, {10, 20, 200, 140})
    scroller.scrollPos = {0, 70}

    let normal = Wnd.create'Wnd(scroller, null, {5, 100, 40, 30})
    @assert(normal.surfaceRect().y == 50)

    let fixed = Wnd.create'Wnd(scroller, null, {5, 30, 80, 60})
    fixed.wndFlags |= .NoScroll
    @assert(fixed.surfaceRect().y == 50)
    @assert(fixed.surfaceToLocal({15, 50}) == Math.Point{0, 0})

    fixed.scrollPos = {0, 6}
    let nested = Wnd.create'Wnd(fixed, null, {2, 20, 20, 20})
    @assert(nested.surfaceRect().y == 64)
}

// Deferred destruction immediately unregisters timers, so one progressive loader cannot receive
// another callback after its window has stopped being an event target.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 100)
    defer host.shutdown()

    let wnd   = Wnd.create'Wnd(&host.root, null, {0, 0, 40, 30})
    let timer = wnd.addTimer(1'ms)
    @assert(!timer.isPendingRemoval)
    wnd.destroy()
    @assert(timer.isPendingRemoval)
}

// A window that still names its own timer after the retirement was flushed asks about a timer the
// application has already released. The registry is what answers, so the second request finds
// nothing instead of reading — and freeing — a released block.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 100)
    defer host.shutdown()

    let wnd   = Wnd.create'Wnd(&host.root, null, {0, 0, 40, 30})
    let timer = wnd.addTimer(1'ms)
    wnd.destroy()
    host.pumpTimerQueues()
    host.app.removeTimer(timer)
}
