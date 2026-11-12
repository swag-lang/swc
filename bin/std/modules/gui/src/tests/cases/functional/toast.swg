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
