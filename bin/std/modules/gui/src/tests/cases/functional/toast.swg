#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A long sentence must not push the toast action outside its bounded pill.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 180)
    var actionCount: u32

    let toast = Toast.create(&host.root)
    toast.sigAction += func|&actionCount|(_) { actionCount += 1 }
    toast.show("A long message that needs more room than this narrow surface can give it", action: "Undo")

    Swag.require(toast.actionRect.width > 0)
    Swag.require(toast.actionRect.x >= 0 and toast.actionRect.right() <= toast.position.width)

    let action = toast.surfaceRect()
    host.moveMouse({action.x + toast.actionRect.horzCenter(), action.vertCenter()})
    Swag.require(toast.hotAction)
    host.click({action.x + toast.actionRect.horzCenter(), action.vertCenter()})
    Swag.require(actionCount == 1 and not toast.isLocallyVisible())
}

// A bar floating at the foot of the parent keeps the pill above it, with the floating air between
// them; without one the pill stands above the hint line as before.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 360)
    defer host.shutdown()

    let toast = Toast.create(&host.root)
    toast.show("Saved", "capture.mp4")
    let resting = toast.position

    let metrics = toast.themeMetrics()
    let barTop  = resting.bottom() - 4
    toast.keepAbove(barTop)
    Swag.require(toast.position.bottom() <= barTop - metrics.floating_Inset + 0.5)
    Swag.require(toast.position.x == resting.x and toast.position.width == resting.width)

    toast.keepAbove(0)
    Swag.require(toast.position == resting)
}
