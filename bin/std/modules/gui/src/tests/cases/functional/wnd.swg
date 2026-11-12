#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

var WndCreateTestId: String

// A nested layout remeasures an inner stack after its child's margin changes.
#test
{
    var host: Testing.HeadlessHost
    host.setup(600, 80)

    let outer = StackLayoutCtrl.create(&host.root, .Left, {0, 0, 600, 40})
    let inner = StackLayoutCtrl.create(outer, .Left)
    let label = Label.create(inner, "A naturally measured nested child")
    host.pump()
    let originalWidth = inner.measure({}).preferred.x

    label.setMargin(12, 0, 12, 0)
    host.pump()
    let measuredWidth = inner.measure({}).preferred.x
    Swag.require(originalWidth != measuredWidth,
                 Format.toString("Nested margin widths: original %, measured %", originalWidth, measuredWidth).toString())
    Swag.require(inner.position.width == measuredWidth,
                 Format.toString("Inner stack width after child margin: measured %, committed %", measuredWidth, inner.position.width).toString())
}

// Changing padding on a natural-size layout reflows that container in its parent.
#test
{
    var host: Testing.HeadlessHost
    host.setup(600, 80)

    let row    = StackLayoutCtrl.create(&host.root, .Left, {0, 0, 600, 40})
    let layout = StackLayoutCtrl.create(row, .Left)
    discard PushButton.create(layout, "A naturally measured child")
    host.pump()
    let originalWidth = layout.measure({}).preferred.x

    layout.setPadding(12, 0, 12, 0)
    host.pump()
    let measuredWidth = layout.measure({}).preferred.x
    Swag.require(originalWidth != measuredWidth,
                 Format.toString("StackLayout padding widths: original %, measured %", originalWidth, measuredWidth).toString())
    Swag.require(layout.position.width == measuredWidth,
                 Format.toString("StackLayout width after padding: measured %, committed %", measuredWidth, layout.position.width).toString())
}

// Changing Wnd padding reflows a naturally sized child in its parent layout.
#test
{
    var host: Testing.HeadlessHost
    host.setup(600, 80)

    let row   = StackLayoutCtrl.create(&host.root, .Left, {0, 0, 600, 40})
    let label = Label.create(row, "A label whose measured width includes Wnd padding")
    host.pump()
    let originalWidth = label.itf.measureContent({}).x

    label.setPadding(12, 0, 12, 0)
    host.pump()
    let measuredWidth = label.itf.measureContent({}).x
    let layoutWidth   = label.measure({}).preferred.x
    Swag.require(originalWidth != measuredWidth,
                 Format.toString("Wnd padding widths: original %, measured %", originalWidth, measuredWidth).toString())
    Swag.require(label.position.width == layoutWidth,
                 Format.toString("Label width after Wnd padding: measured %, committed %", layoutWidth, label.position.width).toString())
}

// Wnd.create owns a dynamic identifier for lookup and command-state queries.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)

    let expected = "Wnd.Dynamic.Command.Identifier"
    WndCreateTestId = Core.String.from(expected)
    let child = Wnd.create'Wnd(null, null, {}, WndCreateTestId.toString())
    child.setParent(&host.root)
    WndCreateTestId[0] = 'X'

    Swag.require(child.id == expected)
    Swag.require(host.root.childById(expected) == child)

    let state = child.sendComputeCommandStateEvent(child.id)
    Swag.require(state.id == expected)
}

struct AncestorTestWnd
{
    using wnd: Wnd
}

impl IWnd for AncestorTestWnd {}

// Typed lookup borrows the nearest matching ancestor and follows reparenting.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)

    let outer = Wnd.create'AncestorTestWnd(&host.root)
    let inner = Wnd.create'AncestorTestWnd(outer)
    let child = Wnd.create'Wnd(inner)
    Swag.require(child.ancestorByType'AncestorTestWnd() == inner)
    Swag.require(inner.ancestorByType'AncestorTestWnd() == outer)
    Swag.require(outer.ancestorByType'AncestorTestWnd() == null)
    Swag.require(child.ancestorByType'PushButton() == null)

    child.setParent(outer)
    Swag.require(child.ancestorByType'AncestorTestWnd() == outer)
}

// An unhandled command state is empty in every field. Presenters use UpdatedFields as the sole
// authority for applying state, so stray bits here can randomly hide or rename menu entries.
#test
{
    var host: Testing.HeadlessHost
    host.setup(80, 40)

    let state = host.root.sendComputeCommandStateEvent("Wnd.Unhandled")
    Swag.require(not state.accepted)
    Swag.require(state.updatedFields == .None)
    Swag.require(state.renderingHint == .None)
    Swag.require(not state.disabled and not state.checked and not state.hidden)
    Swag.require(state.name.isEmpty() and
                 state.longName.isEmpty() and
                 state.shortcut.isEmpty() and
                 state.toolTip.isEmpty())
}

// Parenting, child enumeration and lookup by id.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    let container = Wnd.create'Wnd(&host.root, null, {0, 0, 200, 200})
    let a         = Wnd.create'Wnd(container, null, {0, 0, 50, 50}, "Wnd.A")
    let b         = Wnd.create'Wnd(container, null, {0, 0, 50, 50}, "Wnd.B")

    Swag.require(container.children.count == 2)
    Swag.require(a.parent == container)
    Swag.require(container.isAncestorOf(a))
    Swag.require(host.root.isAncestorOf(a))
    Swag.require(not a.isAncestorOf(container))

    Swag.require(container.childById("Wnd.A") == a)
    Swag.require(container.childById("Wnd.B") == b)
    Swag.require(container.childById("Wnd.None") == null)
}

// Detaching and reparenting update both sides and propagate the surface through the subtree.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    let left       = Wnd.create'Wnd(&host.root, null, {0, 0, 100, 200})
    let right      = Wnd.create'Wnd(&host.root, null, {100, 0, 100, 200})
    let child      = Wnd.create'Wnd(left, null, {0, 0, 50, 50})
    let grandChild = Wnd.create'Wnd(child, null, {0, 0, 20, 20})

    Swag.require(left.detachChild(child))
    Swag.require(child.parent == null and child.surface == null)
    Swag.require(grandChild.surface == null)
    Swag.require(left.children.isEmpty())

    child.setParent(right)
    Swag.require(child.parent == right and child.surface == right.surface)
    Swag.require(grandChild.surface == right.surface)
    Swag.require(right.children.count == 1 and right.children[0] == child)
}

// Hidden state and its propagation to children.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    let container = Wnd.create'Wnd(&host.root, null, {0, 0, 200, 200})
    let child     = Wnd.create'Wnd(container, null, {0, 0, 50, 50})

    Swag.require(child.isVisible())
    Swag.require(child.isLocallyVisible())

    child.hide()
    Swag.require(not child.isVisible())
    Swag.require(child.isHidden())
    Swag.require(not child.isLocallyVisible())

    child.show()
    Swag.require(child.isVisible())

    // A hidden parent hides the child, but the child keeps its own visible state.
    container.hide()
    Swag.require(not child.isVisible())
    Swag.require(child.isLocallyVisible())
    Swag.require(child.isLocallyVisible())
}

// Disabled state and its propagation to children.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    let container = Wnd.create'Wnd(&host.root, null, {0, 0, 200, 200})
    let child     = Wnd.create'Wnd(container, null, {0, 0, 50, 50})

    Swag.require(child.isEnabled())
    Swag.require(child.isLocallyEnabled())

    child.disable()
    Swag.require(not child.isEnabled())
    Swag.require(child.isDisabled())
    Swag.require(not child.isLocallyEnabled())

    child.enable()
    Swag.require(child.isEnabled())
    Swag.require(child.isLocallyEnabled())

    // A disabled parent disables the child, but the child keeps its own state.
    container.disable()
    Swag.require(not child.isEnabled())
    Swag.require(child.isLocallyEnabled())
    Swag.require(child.isLocallyEnabled())
}

// Move/resize and coordinate conversion through the parent chain.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    let container = Wnd.create'Wnd(&host.root, null, {10, 20, 180, 160})
    let child     = Wnd.create'Wnd(container, null, {30, 40, 50, 50})

    // child is at container(10,20) + local(30,40) in surface space.
    Swag.require(child.localToSurface(Math.Point{0, 0}) == Math.Point{40, 60})
    Swag.require(child.surfaceToLocal({40, 60}) == Math.Point{0, 0})
    Swag.require(child.surfaceToLocal(child.localToSurface(Math.Point{7, 9})) == Math.Point{7, 9})

    child.move(15, 25)
    Swag.require(child.position.x == 15)
    Swag.require(child.position.y == 25)
    Swag.require(child.localToSurface(Math.Point{0, 0}) == Math.Point{25, 45})

    child.resize(80, 60)
    Swag.require(child.position.width == 80)
    Swag.require(child.position.height == 60)

    child.setPosition({0, 0, 100, 100})
    Swag.require(child.position == {0, 0, 100, 100})
}

// Dock layout: Left/Right consume edges, Center fills the rest.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 140)
    let container = Wnd.create'Wnd(&host.root, null, {0, 0, 200, 100})
    let left      = Wnd.create'Wnd(container, null, {0, 0, 40, 0})
    let right     = Wnd.create'Wnd(container, null, {0, 0, 30, 0})
    let center    = Wnd.create'Wnd(container, null, {0, 0, 0, 0})

    left.dockStyle   = .Left
    right.dockStyle  = .Right
    center.dockStyle = .Center
    container.applyLayout()

    Swag.require(left.position == {0, 0, 40, 100})
    Swag.require(right.position == {170, 0, 30, 100})
    Swag.require(center.position == {40, 0, 130, 100})
}

// getWndAt descends the hierarchy and skips hidden/disabled by default.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    let container = Wnd.create'Wnd(&host.root, null, {10, 10, 180, 180})
    let child     = Wnd.create'Wnd(container, null, {20, 20, 60, 60})

    // Surface point (40,40) -> container(10,10) -> child local (20,20): inside child.
    Swag.require(host.root.windowAt(40, 40, true) == child)

    // A point inside the container but outside the child resolves to the container.
    Swag.require(host.root.windowAt(160, 160, true) == container)

    child.hide()
    Swag.require(host.root.windowAt(40, 40, true) == container)
    child.show()

    // Disabled is skipped unless getDisabled is set.
    child.disable()
    Swag.require(host.root.windowAt(40, 40, false) == container)
    Swag.require(host.root.windowAt(40, 40, true) == child)
}

// Z-order: windowAt returns the topmost (last) sibling; sendToBack/bringToFront reorder.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    let container = Wnd.create'Wnd(&host.root, null, {0, 0, 200, 200})
    let a         = Wnd.create'Wnd(container, null, {0, 0, 100, 100})
    let b         = Wnd.create'Wnd(container, null, {0, 0, 100, 100})

    // b was added last -> painted on top -> hit first.
    Swag.require(host.root.windowAt(50, 50, true) == b)

    a.bringToFront()
    Swag.require(container.children.back() == a)
    Swag.require(host.root.windowAt(50, 50, true) == a)

    b.sendToBack()
    Swag.require(container.children.front() == b)
    Swag.require(host.root.windowAt(50, 50, true) == a)
}

// destroy() detaches the window from its parent after the destroy pump.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    let container = Wnd.create'Wnd(&host.root, null, {0, 0, 200, 200})
    let child     = Wnd.create'Wnd(container, null, {0, 0, 50, 50})
    Swag.require(container.children.count == 1)

    child.destroy()
    host.pump()
    Swag.require(container.children.isEmpty())
}

// A no-scroll window and its descendants ignore its immediate parent's scroll offset.
// Outer scrolling still moves that subtree, just as painting and hit testing do.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 180)

    let scroller = Wnd.create'Wnd(&host.root, null, {10, 20, 200, 140})
    scroller.scrollPos = {0, 70}

    let normal = Wnd.create'Wnd(scroller, null, {5, 100, 40, 30})
    Swag.require(normal.surfaceRect().y == 50)

    let fixed = Wnd.create'Wnd(scroller, null, {5, 30, 80, 60})
    fixed.wndFlags |= .NoScroll
    Swag.require(fixed.surfaceRect().y == 50)
    Swag.require(fixed.surfaceToLocal({15, 50}) == Math.Point{0, 0})

    fixed.scrollPos = {0, 6}
    let nested = Wnd.create'Wnd(fixed, null, {2, 20, 20, 20})
    Swag.require(nested.surfaceRect().y == 64)

    host.root.scrollPos = {0, 9}
    Swag.require(normal.surfaceRect().y == 41)
    Swag.require(fixed.surfaceRect().y == 41)
    Swag.require(nested.surfaceRect().y == 55)
    Swag.require(nested.surfaceToLocal({17, 55}) == Math.Point{0, 0})
    Swag.require(host.root.windowAt(18, 56, true) == nested)
}

// Deferred destruction immediately unregisters timers, so one progressive loader cannot receive
// another callback after its window has stopped being an event target.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 100)

    let wnd   = Wnd.create'Wnd(&host.root, null, {0, 0, 40, 30})
    let timer = wnd.addTimer(1'ms)
    Swag.require(not timer.isPendingRemoval)
    wnd.destroy()
    Swag.require(timer.isPendingRemoval)
}

// A window that still names its own timer after the retirement was flushed asks about a timer the
// application has already released. The registry is what answers, so the second request finds
// nothing instead of reading — and freeing — a released block.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 100)

    let wnd   = Wnd.create'Wnd(&host.root, null, {0, 0, 40, 30})
    let timer = wnd.addTimer(1'ms)
    wnd.destroy()
    host.pumpTimerQueues()
    host.app.removeTimer(timer)
}

// Stopping a timer through its field releases it and clears the field. An empty field, and a field
// whose timer the pending destruction of the window has already retired, only get cleared.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 100)

    let wnd = Wnd.create'Wnd(&host.root, null, {0, 0, 40, 30})
    var timer: *Timer? = wnd.addTimer(1'ms)
    wnd.stopTimer(&timer)
    Swag.require(timer == null)
    wnd.stopTimer(&timer)

    timer = wnd.addTimer(1'ms)
    wnd.destroy()
    wnd.stopTimer(&timer)
    Swag.require(timer == null)
}
