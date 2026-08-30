#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

const GuiHeadlessSmoke_CloseWindow = "GuiHeadlessSmoke.CloseWindow"
const GuiHeadlessSmoke_ModalExit   = "GuiHeadlessSmoke.ModalExit"

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.closeOnCommand(GuiHeadlessSmoke_CloseWindow)

    let button = PushButton.create(&host.root, "Close", {20, 20, 90, 30}, GuiHeadlessSmoke_CloseWindow)

    Swag.assert(!host.closed)
    Swag.assert(host.wndAt({40, 30}) == button)

    host.click({40, 30})

    Swag.assert(host.closed)
    Swag.assert(host.commandCount == 1)
    Swag.assert(host.lastCommand == GuiHeadlessSmoke_CloseWindow)
    Swag.assert(host.root.isPendingDestroy)
    Swag.assert(host.root.wndFlags.has(.Hidden))
    Swag.assert(host.app.mouseCaptureWnd == null)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.theme.metrics.surfaceWnd_CornerRadius = 18
    host.surface.flags = SurfaceFlags.StandardWindow

    Swag.assert(host.surface.cornerRadius() == 18)

    host.surface.flags.add(.NoShadow)
    Swag.assert(host.surface.cornerRadius() == 0)

    host.surface.flags.remove(.NoShadow)
    host.surface.isMaximized = true
    Swag.assert(host.surface.cornerRadius() == 0)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    var timerCount: u32
    host.root.hookOnEvent = func|count = &timerCount|(wnd, evt)
    {
        switch evt
        {
        case TimerEvent: count[] += 1
        }

        return false
    }

    let timer = host.root.addTimer(10'ms)
    host.fireTimer(timer)

    Swag.assert(timerCount == 1)
    Swag.assert(host.app.timers.count == 1)

    host.app.removeTimer(timer)
    host.pumpTimerQueues()
    Swag.assert(host.app.timers.count == 0)
}

// Scheduling destruction immediately retires timers even though storage is released only after
// the frame. A streaming viewer can therefore be replaced without receiving one last timer on an
// already-discarded document tree.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()

    var timerCount: u32
    let view = Wnd.create'Wnd(&host.root)
    view.hookOnEvent = func|count = &timerCount|(wnd, evt)
    {
        discard wnd
        switch evt
        {
        case TimerEvent: count[] += 1
        }

        return false
    }

    let timer = view.addTimer(1'ms)
    view.destroy()

    Swag.assert(view.isPendingDestroy)
    Swag.assert(timer.isPendingRemoval)
    host.fireTimer(timer)
    Swag.assert(timerCount == 0)
    host.pumpTimerQueues()
    Swag.assert(host.app.timers.count == 0)
}

// A timer callback may create another timer and discard its target in the same dispatch. The
// staged timer must never enter the next frame with a target that is already pending destruction.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()

    var stagedWasRetired: bool
    let view = Wnd.create'Wnd(&host.root)
    view.hookOnEvent = func|retired = &stagedWasRetired|(wnd, evt)
    {
        switch evt
        {
        case TimerEvent:
            let staged = wnd.addTimer(1'ms)
            wnd.destroy()
            retired[] = staged.isPendingRemoval
        }

        return false
    }

    let trigger = view.addTimer(1'ms)
    host.fireTimer(trigger)

    Swag.assert(stagedWasRetired)
    Swag.assert(host.app.timers.isEmpty())
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()
    let surface            = expect host.app.createSurface(20, 30, 180, 100, SurfaceFlags.ToolWindow | SurfaceFlags.TopMost | SurfaceFlags.NoShadow)!
    let background         = expect host.app.createSurface(0, 0, 100, 80, SurfaceFlags.None)!
    let disabledBackground = expect host.app.createSurface(100, 0, 100, 80, SurfaceFlags.None)!
    background.show()
    disabledBackground.show()
    disabledBackground.disable()

    Swag.assert(surface.app == &host.app)
    Swag.assert(surface.position.x == 20)
    Swag.assert(surface.position.y == 30)
    Swag.assert(surface.isTopMost())
    Swag.assert(surface.flags.has(.TopMost))
    Swag.assert(surface.isHidden)

    surface.setTopMost(false)
    Swag.assert(!surface.isTopMost())
    Swag.assert(!surface.flags.has(.TopMost))
    surface.setTopMost()
    Swag.assert(surface.isTopMost())
    Swag.assert(surface.flags.has(.TopMost))

    let replacement  = Wnd.create'Wnd()
    let previousView = surface.view()
    surface.setView(replacement)
    Swag.assert(surface.view() == replacement)
    Swag.assert(replacement.parent == surface.wnd)
    Swag.assert(replacement.surface == surface)
    Swag.assert(previousView.isPendingDestroy)

    let button = PushButton.create(surface.view(), "OK", {20, 20, 80, 30}, GuiHeadlessSmoke_ModalExit)
    button.sigPressed += func(btn) { btn.app().exitModal(btn.id orelse "") }

    surface.show()
    Swag.assert(!surface.isHidden)
    Swag.assert(surface.isInitialized)
    Swag.assert(host.app.surfaceAt(40, 50) == surface)

    var frameCount: u32
    var didClick:   bool
    let result = host.app.doModalLoop(surface, func|host = &host, button, frames = &frameCount, didClick = &didClick|(app)
    {
        frames[] += 1
        if !didClick[]
        {
            host.clickWnd(button)
            didClick[] = true
        }
    })

    Swag.assert(result == GuiHeadlessSmoke_ModalExit)
    Swag.assert(frameCount == 1)
    Swag.assert(didClick)
    Swag.assert(!background.isDisabled)
    Swag.assert(disabledBackground.isDisabled)
    host.pump()
    Swag.assert(host.openedSurfaceCount() == 2)

    background.destroy()
    disabledBackground.destroy()
    host.pump()
    Swag.assert(host.openedSurfaceCount() == 0)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 90)
    defer host.shutdown()
    var frameCallbacks: u32
    host.app.sigFrame    += func|count = &frameCallbacks|(app) { count[] += 1 }
    host.app.maxRunFrame = 2

    host.app.runFrame()
    Swag.assert(!host.app.mustQuit)
    host.app.runFrame()

    Swag.assert(host.app.mustQuit)
    Swag.assert(host.app.timing.frameCount == 2)
    Swag.assert(frameCallbacks == 2)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.wnd_SizingBorderSize    = 8
    host.theme.metrics.wnd_TopSizingBorderSize = 7
    host.surface.flags                         = SurfaceFlags.StandardWindow
    host.surface.position                      = {10, 20, 240, 120}
    host.surface.wnd.padding.y                 = host.theme.metrics.wnd_BigCaptionCY

    let captionChild = Wnd.create'Wnd(&host.surfaceWnd, {20, 4, 60, 24})
    Swag.assert(!host.surfaceWnd.hitTestCaption({30, 15}))
    Swag.assert(host.surfaceWnd.hitTestCaption({100, 15}))
    captionChild.destroy()
    host.pump()

    let captionMenu = MenuCtrl.createBar(&host.surfaceWnd, {0, 0, 200, host.surface.wnd.padding.y})
    captionMenu.addItem("File", "GuiHeadlessSmoke.File")
    captionMenu.computeLayoutBar()

    let menuIt0   = captionMenu.items[0]!
    let menuItemX = menuIt0.pos + menuIt0.size * 0.5
    Swag.assert(!host.surfaceWnd.hitTestCaption({menuItemX, 15}))
    Swag.assert(host.surfaceWnd.hitTestCaption({180, 15}))

    captionMenu.destroy()
    host.pump()

    Swag.assert(host.surfaceWnd.hitTestBorders({30, 15}) == SizingBorder.None)
    Swag.assert(host.surfaceWnd.hitTestBorders({30, 1}) & SizingBorder.Top)

    host.surfaceWnd.itf     = &host.surfaceWnd
    host.surfaceWnd.type    = SurfaceWnd
    host.surfaceWnd.surface = &host.surface
    host.app.mouseEnterWnd  = &host.surfaceWnd

    var evt = MouseEvent{kind: .Pressed}
    evt.button     = .Left
    evt.surfacePos = {30, 15}
    host.surfaceWnd.sendEvent(&evt)

    evt.kind       = .Move
    evt.surfacePos = {50, 20}
    evt.delta      = {20, 5}
    host.surfaceWnd.sendEvent(&evt)

    Swag.assert(host.surface.position.x == 30)
    Swag.assert(host.surface.position.y == 25)
    Swag.assert(host.surface.position.width == 240)
    Swag.assert(host.surface.position.height == 120)

    evt.kind       = .Released
    evt.surfacePos = {50, 20}
    host.surfaceWnd.sendEvent(&evt)

    host.surface.position         = {10, 20, 240, 120}
    host.surfaceWnd.movingSurface = false
    host.surfaceWnd.sizingBorder  = .None
    host.app.mouseEnterWnd        = &host.surfaceWnd

    evt.kind       = .Pressed
    evt.surfacePos = {30, 1}
    evt.delta      = {}
    host.surfaceWnd.sendEvent(&evt)

    evt.kind       = .Move
    evt.surfacePos = {30, 11}
    evt.delta      = {0, 10}
    host.surfaceWnd.sendEvent(&evt)

    Swag.assert(host.surface.position.x == 10)
    Swag.assert(host.surface.position.y == 30)
    Swag.assert(host.surface.position.width == 240)
    Swag.assert(host.surface.position.height == 110)

    evt.kind = .Released
    host.surfaceWnd.sendEvent(&evt)
}
