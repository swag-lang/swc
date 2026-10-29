#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Rebuilding the inspector and preset row must retire the previous controls each frame.
#test
{
    func countWindows(wnd: *Wnd)->u64
    {
        var count = 1'u64
        for child in wnd.children do
            count += countWindows(child)
        return count
    }

    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    discard testSetupPropWnd(&f)

    f.main.editMode = .Shape
    f.main.updateState()
    f.gui.runFrames(1)
    let baseline = countWindows(f.main)

    for 100
    {
        f.main.editMode = .Text
        f.main.updateState()
        f.gui.runFrames(1)
        f.main.editMode = .Shape
        f.main.updateState()
        f.gui.runFrames(1)
        Swag.assert(countWindows(f.main) == baseline)
    }
}
