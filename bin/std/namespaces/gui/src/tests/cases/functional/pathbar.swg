#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// The shared path bar keeps short paths intact and the leaf of long paths reachable.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 100)
    let bar = PathBar.create(&host.root)
    bar.setPosition({0, 0, 400, 32})
    const Root = #os == Swag.TargetOs.Windows ? "Z:/" : "/"
    let shortPath = Path.combine(Root, "Films")
    let longPath  = Path.combine(Root, "A long collection folder/Another long folder/Films")
    bar.setPath(shortPath.toString())
    Swag.require(bar.breadcrumb.toolTip.isEmpty())
    Swag.require(bar.breadcrumb.items.count == 2)
    Swag.require(bar.breadcrumb.items[0].tag == Root)
    Swag.require(bar.breadcrumb.items[1].name == "Films")
    Swag.require(bar.breadcrumb.scrollPos.x == 0)
    var navigated: String
    bar.sigNavigate += func|&navigated|(_, path) { navigated = path }
    host.click(bar.breadcrumb.localToSurface(bar.breadcrumb.items[0].bodyRect.center()))
    Swag.require(navigated == Root)
    bar.setPath(longPath.toString())
    bar.resize(180, 32)
    host.root.applyLayout()
    Swag.require(bar.breadcrumb.scrollPos.x == 0)
    Swag.require(bar.breadcrumb.firstVisible > 0)
    Swag.require(not bar.pathScroll.showBarH)
    let leaf = bar.breadcrumb.items.back().bodyRect
    host.click(bar.breadcrumb.localToSurface(leaf.center() - bar.breadcrumb.scrollPos))
    Swag.require(bar.edit.isLocallyVisible())
    Swag.require(bar.edit.text() == longPath.toString())
    host.keyPress(.Escape)
    Swag.require(not bar.edit.isLocallyVisible() and bar.pathScroll.isLocallyVisible())

    var submitted: String
    bar.sigSubmitted += func|&submitted|(_, path) { submitted = path }
    bar.beginEdit()
    bar.edit.setText("C:/Pictures")
    host.keyPress(.Return)
    Swag.require(submitted == "C:/Pictures")
    Swag.require(not bar.edit.isLocallyVisible())
}

// A click on a control that keeps keyboard focus where it was still dismisses the editor.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 120)
    let bar = PathBar.create(&host.root)
    bar.setPosition({0, 0, 400, 32})
    bar.setPath("Original")
    let button = PushButton.create(&host.root, "Outside")
    button.setPosition({0, 52, 100, 32})
    button.focusPolicy = .None
    let search = EditBox.create(&host.root, "")
    search.setPosition({120, 52, 100, 32})
    var pressed, submitted, finished: bool
    button.sigPressed   += func|&pressed|(_) { pressed = true }
    bar.sigSubmitted    += func|&submitted|(_, _) { submitted = true }
    bar.sigEditFinished += func|&finished|(_) { finished = true }
    host.root.applyLayout()

    bar.beginEdit()
    bar.edit.setText("Draft")
    host.click(bar.edit.surfaceRect().center())
    Swag.require(bar.edit.hasFocus() and bar.edit.isLocallyVisible())

    host.click(button.surfaceRect().center())
    Swag.require(pressed and not submitted and not finished)
    Swag.require(not bar.edit.isLocallyVisible() and bar.pathScroll.isLocallyVisible())
    bar.beginEdit()
    Swag.require(bar.edit.text() == "Original")
    host.click(Math.Point{350, 100})
    Swag.require(not bar.edit.isLocallyVisible() and not submitted)
    Swag.require(bar.focusedWindow() == null)

    bar.beginEdit()
    host.app.notifyPressedElsewhere()
    Swag.require(not bar.edit.isLocallyVisible() and bar.focusedWindow() == null)

    bar.beginEdit()
    host.click(search.surfaceRect().center())
    Swag.require(not bar.edit.isLocallyVisible() and search.hasFocus())
}

// A wide caption path gives its trailing ground to the window and edits it on a double-click.
#test
{
    var host: Testing.HeadlessHost
    host.setup(500, 140)
    host.surface.flags = .StandardWindow

    let strip    = host.surfaceWnd.stripHeight()
    with let bar = PathBar.create(&host.surfaceWnd)
    {
        .focusPolicy = .Click
        .setPosition({40, 8, 420, strip - 8})
    }

    bar.setText("Library/Films")
    bar.breadcrumb.addItem("Library")
    bar.breadcrumb.addItem("Films", hasArrow: false)
    bar.refreshPath()

    let leaf  = bar.breadcrumb.localToSurface(bar.breadcrumb.items.back().bodyRect.center())
    let arrow = bar.breadcrumb.localToSurface(bar.breadcrumb.items[0].arrowRect.center())
    let empty = bar.localToSurface(Math.Point{bar.position.width - 20, bar.position.height * 0.5})
    Swag.require(not host.surfaceWnd.hitTestCaption(leaf))
    Swag.require(not host.surfaceWnd.hitTestCaption(arrow))
    Swag.require(host.surfaceWnd.hitTestCaption(empty))

    var screen = empty
    host.surface.surfaceToScreen(&screen)
    Swag.require(host.surface.windowAt(screen) == &host.surfaceWnd)
    host.click(screen)
    Swag.require(not bar.edit.isLocallyVisible())

    let movement = Math.Point{24, 16}
    let before   = host.surface.position
    host.drag(screen, screen + movement)
    Swag.require(host.surface.position.x == before.x + movement.x and
                 host.surface.position.y == before.y + movement.y)
    Swag.require(not bar.edit.isLocallyVisible() and host.app.mouseCapture() == null)

    host.doubleClick(screen + movement)
    Swag.require(bar.edit.isLocallyVisible() and bar.edit.hasFocus())
    Swag.require(bar.edit.text() == "Library/Films")
    Swag.require(not host.surfaceWnd.hitTestCaption(empty))
    host.keyPress(.Escape)
    Swag.require(bar.pathScroll.isLocallyVisible())

    bar.breadcrumb.maxVisibleItems = 1
    bar.refreshPath()
    let overflow = bar.breadcrumb.localToSurface(bar.breadcrumb.overflowRect.center())
    Swag.require(not host.surfaceWnd.hitTestCaption(overflow))
    Swag.require(host.surfaceWnd.hitTestCaption(empty))

    // The same path in a content header keeps its single-click editing affordance.
    bar.setPosition({40, strip + 8, 420, strip - 8})
    screen = bar.localToSurface(Math.Point{bar.position.width - 20, bar.position.height * 0.5})
    host.surface.surfaceToScreen(&screen)
    host.click(screen)
    Swag.require(bar.edit.isLocallyVisible())
}
