#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Timeout diagnostics distinguish an absent modal from an observed modal with the wrong action.
#test
{
    var host: Testing.HeadlessHost
    host.setup(300, 120)
    defer host.shutdown()

    host.clickModalButtonWhenShown("missing", maxFrames: 1)
    host.driveAutoStages(&host.app)
    host.driveAutoStages(&host.app)
    Swag.assert(!host.autoArmed and !host.autoHandled)
    Swag.assert(host.autoFailure == "modal did not appear while waiting for button 'missing'")

    discard PushButton.create(&host.root, "Close", {10, 10, 90, 28}, id: "close")
    host.clickModalButtonWhenShown("missing", maxFrames: 1)
    Swag.assert(host.autoFailure.isEmpty())
    host.app.modalSurfaces.add(&host.surface)
    host.driveAutoStages(&host.app)
    host.app.modalSurfaces.removeBack()

    // Remember an observed modal even if it disappears before the timeout is reached.
    host.driveAutoStages(&host.app)
    Swag.assert(!host.autoArmed and !host.autoHandled)
    Swag.assert(host.autoFailure == "modal appeared without button 'missing'; observed button identifiers: 'close'")
}
