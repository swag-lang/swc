#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Group tags the selected forms with a shared id, ungroup clears it, and both are
// fully undoable. Selecting one member expands the selection to the whole group.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    let a = testAddShape(f.capture, 0, 0, 10, 10)
    let b = testAddShape(f.capture, 20, 0, 10, 10)
    let c = testAddShape(f.capture, 40, 0, 10, 10)

    f.capture.selection.add(0)
    Swag.assert(!f.capture.canGroup())
    f.capture.selection.add(1)
    Swag.assert(f.capture.canGroup())
    Swag.assert(!f.capture.canUngroup())

    f.capture.pushUndo(f.capture.newUndo(.Group))
    Swag.assert(a.groups.count == 1)
    Swag.assert(b.groups.count == 1)
    Swag.assert(a.groups[0] == b.groups[0])
    Swag.assert(c.groups.count == 0)
    Swag.assert(f.capture.canUngroup())
    let gid = a.groups[0]

    // Selecting a single member expands to every member of its group.
    f.capture.selection.clear()
    f.capture.selection.add(0)
    f.capture.expandSelectionToGroups()
    Swag.assert(f.capture.selection.count == 2)
    Swag.assert(f.capture.selection.contains(0))
    Swag.assert(f.capture.selection.contains(1))

    // A loose form stays alone.
    f.capture.selection.clear()
    f.capture.selection.add(2)
    f.capture.expandSelectionToGroups()
    Swag.assert(f.capture.selection.count == 1)

    f.capture.undo()
    Swag.assert(a.groups.count == 0)
    Swag.assert(b.groups.count == 0)

    // Redo reuses the same minted id instead of allocating a new one.
    f.capture.redo()
    Swag.assert(a.groups[0] == gid)
    Swag.assert(b.groups[0] == gid)

    f.capture.selection.clear()
    f.capture.selection.add(0)
    f.capture.selection.add(1)
    f.capture.pushUndo(f.capture.newUndo(.Ungroup))
    Swag.assert(a.groups.count == 0)
    Swag.assert(b.groups.count == 0)
    f.capture.undo()
    Swag.assert(a.groups[0] == gid)
    Swag.assert(b.groups[0] == gid)
}

// Nested groups: wrapping an existing group prepends a new outer id; ungrouping pops
// one level at a time, revealing the inner group.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    let a = testAddShape(f.capture, 0, 0, 10, 10)
    let b = testAddShape(f.capture, 20, 0, 10, 10)
    let c = testAddShape(f.capture, 40, 0, 10, 10)

    f.capture.selection.add(0)
    f.capture.selection.add(1)
    f.capture.pushUndo(f.capture.newUndo(.Group))
    let inner = a.groups[0]

    f.capture.selection.clear()
    f.capture.selection.add(0)
    f.capture.expandSelectionToGroups()
    f.capture.selection.add(2)
    f.capture.selection.sort()
    f.capture.pushUndo(f.capture.newUndo(.Group))
    let outer = a.groups[0]

    Swag.assert(outer != inner)
    Swag.assert(a.groups.count == 2)
    Swag.assert(a.groups[0] == outer)
    Swag.assert(a.groups[1] == inner)
    Swag.assert(b.groups.count == 2)
    Swag.assert(c.groups.count == 1)
    Swag.assert(c.groups[0] == outer)

    // Any member selects the whole outer group.
    f.capture.selection.clear()
    f.capture.selection.add(2)
    f.capture.expandSelectionToGroups()
    Swag.assert(f.capture.selection.count == 3)

    // Ungroup collapses the outer level, keeping the inner A+B group intact.
    f.capture.pushUndo(f.capture.newUndo(.Ungroup))
    Swag.assert(a.groups.count == 1)
    Swag.assert(a.groups[0] == inner)
    Swag.assert(b.groups[0] == inner)
    Swag.assert(c.groups.count == 0)

    f.capture.selection.clear()
    f.capture.selection.add(0)
    f.capture.expandSelectionToGroups()
    Swag.assert(f.capture.selection.count == 2)
    Swag.assert(f.capture.selection.contains(1))

    f.capture.undo()
    Swag.assert(a.groups.count == 2)
    Swag.assert(c.groups.count == 1)
}

// Grouping survives a save/load round-trip, together with the id allocator.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    f.capture.width, f.capture.widthOrg   = 64
    f.capture.height, f.capture.heightOrg = 48
    f.capture.backImg = Image.create(64, 48, .BGRA8)

    let a = testAddShape(f.capture, 1, 2, 10, 11)
    discard testAddShape(f.capture, 20, 2, 10, 11)
    discard testAddShape(f.capture, 40, 2, 10, 11)

    f.capture.selection.add(0)
    f.capture.selection.add(1)
    f.capture.pushUndo(f.capture.newUndo(.Group))
    let gid    = a.groups[0]
    let nextId = f.capture.nextGroupId

    let path = testTempCapturePath()
    defer discard catch File.delete(path)
    f.capture.file    = path
    f.capture.changed = true
    expect f.capture.save()
    let loaded = expect Capture.load(path)!
    defer Memory.delete(loaded)
    Swag.assert(loaded.forms.count == 3)
    Swag.assert(loaded.nextGroupId == nextId)

    let la = cast(*BaseForm) loaded.forms[0].buffer
    let lb = cast(*BaseForm) loaded.forms[1].buffer
    let lc = cast(*BaseForm) loaded.forms[2].buffer
    Swag.assert(la.groups.count == 1)
    Swag.assert(la.groups[0] == gid)
    Swag.assert(lb.groups.count == 1)
    Swag.assert(lb.groups[0] == gid)
    Swag.assert(lc.groups.count == 0)
}

// Pasting a grouped selection keeps the copies grouped together but under a fresh id,
// so they never silently re-join the originals.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)

    let a = testAddShape(f.capture, 10, 20, 30, 40)
    discard testAddShape(f.capture, 60, 20, 30, 40)
    f.capture.selection.add(0)
    f.capture.selection.add(1)
    f.capture.pushUndo(f.capture.newUndo(.Group))
    let origGid = a.groups[0]

    f.main.sendCommandEvent(ActionCopyPaste.Copy)

    f.capture.paintRect = {0, 0, f.capture.width, f.capture.height}
    f.capture.selection.clear()
    f.main.sendCommandEvent(ActionCopyPaste.Paste)

    Swag.assert(f.capture.forms.count == 4)
    let pa = cast(*BaseForm) f.capture.forms[2].buffer
    let pb = cast(*BaseForm) f.capture.forms[3].buffer
    Swag.assert(pa.groups.count == 1)
    Swag.assert(pb.groups.count == 1)
    Swag.assert(pa.groups[0] == pb.groups[0])
    Swag.assert(pa.groups[0] != origGid)
    Swag.assert(a.groups[0] == origGid)
}
