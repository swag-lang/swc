#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A window that records the gesture and claims every payload it is offered.
internal struct DropCatcher
{
    using wnd: Wnd

    enters, leaves, overs, drops: u32
    lastFiles: Array'String
    lastText:  String
    claim = true
}

impl IWnd for DropCatcher
{
    mtd impl onDragDropEvent(evt: *DragDropEvent)
    {
        if !.claim
        {
            evt.accepted = false
            return
        }

        switch evt.kind
        {
        case .Enter:
            .enters += 1

        case .Leave:
            .leaves += 1

        case .Over:
            .overs += 1

        case .Drop:
            .drops += 1
            .lastFiles.clear()
            for &f in evt.data.files do
                .lastFiles.add(f)
            .lastText = evt.data.text
        }

        evt.effect = pickDropEffect(evt.allowed, evt.modifiers)
    }
}

internal func makeCatcher(parent: *Wnd, rect: Math.Rectangle)->*DropCatcher
{
    let res = Wnd.create'DropCatcher(parent, rect)
    return res
}

// A drop reaches the window under the pointer, with the payload it carries.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()

    let catcher = makeCatcher(&host.root, {10, 10, 100, 100})
    let effect  = host.dropFiles({50, 50}, ["c:/tmp/one.txt"])

    Swag.assert(effect == DropEffect.Copy)
    Swag.assert(catcher.drops == 1)
    Swag.assert(catcher.lastFiles.count == 1)
    Swag.assert(catcher.lastFiles[0] == "c:/tmp/one.txt")
}

// Entering and leaving are derived from the position, once each.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()

    let catcher = makeCatcher(&host.root, {10, 10, 80, 80})

    discard host.dragFilesOver({50, 50}, ["c:/tmp/one.txt"])
    discard host.dragFilesOver({60, 60}, ["c:/tmp/one.txt"])
    Swag.assert(catcher.enters == 1)
    Swag.assert(catcher.overs == 2)
    Swag.assert(catcher.leaves == 0)

    // Moving outside the window leaves it, and moving back enters it again.
    discard host.dragFilesOver({150, 150}, ["c:/tmp/one.txt"])
    Swag.assert(catcher.leaves == 1)
    discard host.dragFilesOver({50, 50}, ["c:/tmp/one.txt"])
    Swag.assert(catcher.enters == 2)
}

// A cancelled gesture still tells the window it was left, so a highlight is never stuck on.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()

    let catcher = makeCatcher(&host.root, {10, 10, 80, 80})
    discard host.dragFilesOver({50, 50}, ["c:/tmp/one.txt"])
    host.cancelDrag()

    Swag.assert(catcher.enters == 1)
    Swag.assert(catcher.leaves == 1)
    Swag.assert(catcher.drops == 0)
}

// A drop is followed by a leave, whatever the target answered.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()

    let catcher = makeCatcher(&host.root, {10, 10, 80, 80})
    discard host.dropFiles({50, 50}, ["c:/tmp/one.txt"])

    Swag.assert(catcher.drops == 1)
    Swag.assert(catcher.leaves == 1)
}

// A window destroyed while a drag hovers it leaves nothing behind for the next move to follow.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()

    let catcher = makeCatcher(&host.root, {10, 10, 80, 80})
    discard host.dragFilesOver({50, 50}, ["c:/tmp/one.txt"])
    Swag.assert(host.app.dragEnterWnd == cast(*Wnd?) catcher)

    catcher.destroy()
    host.pump()
    Swag.assert(host.app.dragEnterWnd == null)

    // The gesture goes on over what is left, which is nothing that takes a drop.
    Swag.assert(host.dropFiles({50, 50}, ["c:/tmp/one.txt"]) == DropEffect.None)
}

// A window that declines lets the gesture bubble to its parent.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()

    let outer = makeCatcher(&host.root, {10, 10, 150, 150})
    let inner = makeCatcher(outer, {10, 10, 50, 50})
    inner.claim = false

    let effect = host.dropFiles({40, 40}, ["c:/tmp/one.txt"])
    Swag.assert(effect == DropEffect.Copy)
    Swag.assert(inner.drops == 0)
    Swag.assert(outer.drops == 1)
}

// The target answers within what the source allows, and the modifiers pick among them.
#test
{
    Swag.assert(pickDropEffect(DropEffect.Copy | DropEffect.Move, Input.KeyModifiers.None) == DropEffect.Copy)
    Swag.assert(pickDropEffect(DropEffect.Copy | DropEffect.Move, Input.KeyModifiers.Shift) == DropEffect.Move)
    Swag.assert(pickDropEffect(DropEffect.Copy | DropEffect.Move, Input.KeyModifiers.Control) == DropEffect.Copy)
    Swag.assert(pickDropEffect(DropEffect.Copy | DropEffect.Link, Input.KeyModifiers.Control | .Shift) == DropEffect.Link)

    // A modifier naming an effect the source refuses falls back to what it does offer.
    Swag.assert(pickDropEffect(DropEffect.Copy, Input.KeyModifiers.Shift) == DropEffect.Copy)
    Swag.assert(pickDropEffect(DropEffect.None, Input.KeyModifiers.None) == DropEffect.None)

    // Nothing offered by nobody stays nothing.
    Swag.assert(pickDropEffect(DropEffect.Link, Input.KeyModifiers.None) == DropEffect.Link)
}

// A payload a source builds reads back through the same accessors a target uses.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()

    var data: DragData
    Swag.assert(!data.hasFiles() and !data.hasText() and !data.hasImage())

    data.addFile("c:/tmp/one.png")
    data.setText("beside it")
    var source = Testing.indexedImage(5, 3)
    data.setImage(source)

    Swag.assert(data.singleFile() == "c:/tmp/one.png")
    Swag.assert(data.text == "beside it")
    Swag.assert(data.hasImage())

    // A picture handed in is the one handed back, with no encode-decode round trip in between.
    let held = data.image()!
    Swag.assert(held.width == 5 and held.height == 3)

    data.clear()
    Swag.assert(!data.hasFiles() and !data.hasText() and !data.hasImage())
    Swag.assert(data.image() == null)
}

// A file the payload carries itself is produced when it is read, and only then.
#test
{
    var runs = 0'u32

    var data: DragData
    data.addContent("late.txt", func|&runs|()
    {
        runs += 1
        return Testing.textBytes("produced")
    })

    // Announcing the gesture costs nothing: the name is there and the bytes are not.
    Swag.assert(data.hasContents())
    Swag.assert(data.contents.count == 1)
    Swag.assert(data.contents[0].name == "late.txt")
    Swag.assert(!data.contents[0].isReady())
    Swag.assert(runs == 0)

    // The first read pays for it, and every later one is free.
    Swag.assert(Testing.bytesAre(data.contentData(0), "produced"))
    Swag.assert(runs == 1)
    Swag.assert(Testing.bytesAre(data.contentData(0), "produced"))
    Swag.assert(runs == 1)
    Swag.assert(data.contents[0].isReady())

    data.clear()
    Swag.assert(!data.hasContents())
}

// A file whose content is already in hand needs no producer, and reads as ready straight away.
#test
{
    var data: DragData
    data.addContent("now.bin", [1'u8, 2, 3])

    Swag.assert(data.contents.count == 1)
    Swag.assert(data.contents[0].isReady())

    let bytes = data.contentData(0)
    Swag.assert(bytes.count == 3)
    Swag.assert(bytes[0] == 1 and bytes[1] == 2 and bytes[2] == 3)
}

// A picture handed to a payload is not encoded until something asks for the encoded form.
#test
{
    var data: DragData
    data.setImage(Testing.indexedImage(6, 4))

    // The payload knows it carries a picture without touching the encoder.
    Swag.assert(data.hasImage())
    Swag.assert(data.imageBytes.count == 0)

    let held = data.image()!
    Swag.assert(held.width == 6 and held.height == 4)
    Swag.assert(data.imageBytes.count == 0)

    // Asking for the bytes is what pays, and it pays once.
    Swag.assert(data.encodedImage().count != 0)
    Swag.assert(data.imageEncoded)

    let size = data.imageBytes.count
    Swag.assert(data.encodedImage().count == size)
}

// A drag started with no desktop under it, or with nothing to carry, goes nowhere.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()

    let catcher = makeCatcher(&host.root, {10, 10, 80, 80})

    var empty: DragData
    Swag.assert(catcher.startDrag(&empty) == DropEffect.None)

    var data: DragData
    data.setText("nowhere to go")
    Swag.assert(catcher.startDrag(&data) == DropEffect.None)

    // A payload carrying nothing but a file of its own is still something to drag, so this one
    // is refused for the missing desktop rather than for an empty payload.
    var carried: DragData
    carried.addContent("only.txt", Testing.textBytes("content").toSlice())
    Swag.assert(catcher.startDrag(&carried) == DropEffect.None)
}

// A drop on nothing is refused without reaching any window.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()

    let catcher = makeCatcher(&host.root, {10, 10, 20, 20})
    let effect  = host.dropFiles({500, 500}, ["c:/tmp/one.txt"])

    Swag.assert(effect == DropEffect.None)
    Swag.assert(catcher.drops == 0)
}

// An edit box takes dropped text at the caret, and emits its change notification.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 60)
    defer host.shutdown()

    let edit    = EditBox.create(&host.root, "AC", {0, 0, 240, 26})
    var changed = 0'u32
    edit.sigTextChanged += func|&changed|(box)
    {
        discard box
        changed += 1
    }

    // The text lands where the pointer is, not where the caret happened to be: the box moved its
    // caret under the payload while it hovered, which is what the reader was looking at.
    let rect = edit.surfaceRect()
    edit.setSelection(0, 0)

    let effect = host.dropText({rect.right() - 2, rect.center().y}, "B")
    Swag.assert(effect == DropEffect.Copy)
    Swag.assert(edit.text() == "ACB")
    Swag.assert(changed == 1)

    discard host.dropText({rect.x + 2, rect.center().y}, "Z")
    Swag.assert(edit.text() == "ZACB")
}

// A read-only edit box refuses every payload.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 60)
    defer host.shutdown()

    let edit = EditBox.create(&host.root, "keep", {0, 0, 240, 26})
    edit.updateFlags(.ReadOnly)

    Swag.assert(host.dropText(edit.surfaceRect().center(), "no") == DropEffect.None)
    Swag.assert(edit.text() == "keep")
}

// A file replaces the whole content, but only when the box asked for file drops.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 60)
    defer host.shutdown()

    let edit = EditBox.create(&host.root, "", {0, 0, 240, 26})
    let pt   = edit.surfaceRect().center()

    Swag.assert(host.dropFiles(pt, ["c:/tmp/one.vault"]) == DropEffect.None)
    Swag.assert(edit.text() == "")

    edit.updateFlags(.AcceptFileDrop)
    Swag.assert(host.dropFiles(pt, ["c:/tmp/one.vault"]) == DropEffect.Copy)
    Swag.assert(edit.text() == "c:/tmp/one.vault")

    // Several files name no single value, so the box has nothing to answer.
    Swag.assert(host.dropFiles(pt, ["c:/tmp/a.vault", "c:/tmp/b.vault"]) == DropEffect.None)
    Swag.assert(edit.text() == "c:/tmp/one.vault")
}
