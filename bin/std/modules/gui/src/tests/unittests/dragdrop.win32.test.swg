#global if #os == Swag.TargetOs.Windows
#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Win32

// ---------------------------------------------------------------------------
// The two halves of the platform layer, driven against each other exactly as OLE
// drives them: the source's `IDataObject` handed to the target's `IDropTarget`,
// through the interface vtables, with real clipboard mediums in between.
//
// This is what proves the binding layout — FORMATETC, STGMEDIUM, POINTL passed by
// value — every format both sides claim to speak, and that a drop entering through
// the platform reaches the window under it. The hit test asks the surface OLE called
// rather than the desktop, so it works with no desktop under it, which is exactly why
// a drag from Explorer used to answer `None` everywhere: the topmost window at the
// pointer is the shell's drag image, not ours.
// ---------------------------------------------------------------------------

// Builds a source object over `data`, the way `startDrag` does.
internal func testDragSource(session: *DragSession, data: *DragData)->*IDataObject
{
    session.setup(data)
    return cast(*IDataObject) &session.dataObj
}

// Hands `source` to the surface's own drop target and returns the payload it read back.
internal func testRoundTrip(host: *Testing.HeadlessHost, source: *IDataObject)->*DragData
{
    host.surface.registerDropTarget()
    let target = cast(*IDropTarget) &host.surface.dropTarget

    var effect = DROPEFFECT_COPY
    @assert(target.lpVtbl.DragEnter(target, source, 0, {60, 60}, &effect) == S_OK)
    return &host.surface.dropTarget.data
}

// A window that takes everything, so a platform drop has somewhere to land.
internal struct PlatformCatcher
{
    using wnd: Wnd
    drops:     u32
    files:     Array'String
}

impl IWnd for PlatformCatcher
{
    mtd impl onDragDropEvent(evt: *DragDropEvent)
    {
        if evt.kind == .Drop
        {
            .drops += 1
            .files.clear()
            for &f in evt.data.files do
                .files.add(f)
        }

        evt.effect = pickDropEffect(evt.allowed, evt.modifiers)
    }
}

// A drop arriving through the platform reaches the window under the pointer.
//
// This is the regression that shipped: the target was resolved with `WindowFromPoint`,
// which during a real drag answers the shell's drag image rather than the window being
// dragged over, so every position refused the drop.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()

    let catcher = Wnd.create'PlatformCatcher(&host.surfaceWnd, {0, 0, 200, 200})
    host.surfaceWnd.view = catcher

    var data: DragData
    data.addFile("c:/tmp/dropped.txt")

    var session: DragSession
    let source = testDragSource(&session, &data)

    host.surface.registerDropTarget()
    let target = cast(*IDropTarget) &host.surface.dropTarget

    var effect = DROPEFFECT_COPY
    @assert(target.lpVtbl.DragEnter(target, source, 0, {60, 60}, &effect) == S_OK)
    @assert(effect == DROPEFFECT_COPY)

    effect = DROPEFFECT_COPY
    @assert(target.lpVtbl.Drop(target, source, 0, {60, 60}, &effect) == S_OK)
    @assert(effect == DROPEFFECT_COPY)

    @assert(catcher.drops == 1)
    @assert(catcher.files.count == 1)
    @assert(catcher.files[0] == "c:/tmp/dropped.txt")
}

// A list of files survives the DROPFILES block, in order.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()

    var data: DragData
    data.addFile("c:/tmp/first.png")
    data.addFile("c:/tmp/second name with spaces.png")

    var session: DragSession
    let payload = testRoundTrip(&host, testDragSource(&session, &data))

    @assert(payload.files.count == 2)
    @assert(payload.files[0] == "c:/tmp/first.png")
    @assert(payload.files[1] == "c:/tmp/second name with spaces.png")
    @assert(payload.singleFile() == null)
    @assert(!payload.hasText())
    @assert(!payload.hasImage())
}

// One file alone is what a field naming a document reads through `singleFile`.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()

    var data: DragData
    data.addFile("c:/tmp/only.txt")

    var session: DragSession
    @assert(testRoundTrip(&host, testDragSource(&session, &data)).singleFile() == "c:/tmp/only.txt")
}

// Text survives the UTF-16 medium, including what does not fit in one byte.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()

    var data: DragData
    data.setText("drag héllo → wörld")

    var session: DragSession
    let payload = testRoundTrip(&host, testDragSource(&session, &data))

    @assert(payload.text == "drag héllo → wörld")
    @assert(!payload.hasFiles())
}

// A picture survives the PNG medium, pixel for pixel.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()

    var source = Testing.indexedImage(7, 5)

    var data: DragData
    expect data.setImage(source)

    var session: DragSession
    let payload = testRoundTrip(&host, testDragSource(&session, &data))

    @assert(payload.hasImage())
    let decoded = payload.image()!
    @assert(decoded.width == 7)
    @assert(decoded.height == 5)
    @assert(decoded.pixelColor(0, 0).argb == source.pixelColor(0, 0).argb)
    @assert(decoded.pixelColor(6, 4).argb == source.pixelColor(6, 4).argb)
}

// Files and a picture together: a folder takes the file, an editor takes the bitmap, and the
// target sees both.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()

    var source = Testing.indexedImage(4, 4)

    var data: DragData
    data.addFile("c:/tmp/shot.png")
    expect data.setImage(source)

    var session: DragSession
    let payload = testRoundTrip(&host, testDragSource(&session, &data))

    @assert(payload.singleFile() == "c:/tmp/shot.png")
    @assert(payload.hasImage())
}

// The source enumerates what it offers, most specific first, and stops cleanly.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()

    var data: DragData
    data.addFile("c:/tmp/one.png")
    data.setText("beside it")

    var session: DragSession
    let source = testDragSource(&session, &data)

    var raw: LPVOID
    @assert(source.lpVtbl.EnumFormatEtc(source, 1, &raw) == S_OK)
    let formats = cast(*IEnumFORMATETC) raw!
    defer discard formats.lpVtbl.Release(formats)

    var entries: [8] FORMATETC
    var fetched: ULONG
    @assert(formats.lpVtbl.Next(formats, 8, &entries[0], &fetched) == S_FALSE)
    @assert(fetched == 3)
    @assert(entries[0].cfFormat == cast(CLIPFORMAT) CF_HDROP)
    @assert(entries[1].cfFormat == cast(CLIPFORMAT) CF_UNICODETEXT)
    @assert(entries[2].cfFormat == cast(CLIPFORMAT) CF_TEXT)
    @assert(entries[0].tymed == TYMED_HGLOBAL)
    @assert(entries[0].dwAspect == DVASPECT_CONTENT)

    // Rewinding starts the walk again, and a clone keeps its own place in it.
    @assert(formats.lpVtbl.Reset(formats) == S_OK)
    @assert(formats.lpVtbl.Skip(formats, 1) == S_OK)

    var rawClone: LPVOID
    @assert(formats.lpVtbl.Clone(formats, &rawClone) == S_OK)
    let clone = cast(*IEnumFORMATETC) rawClone!
    defer discard clone.lpVtbl.Release(clone)

    @assert(clone.lpVtbl.Next(clone, 1, &entries[0], &fetched) == S_OK)
    @assert(fetched == 1)
    @assert(entries[0].cfFormat == cast(CLIPFORMAT) CF_UNICODETEXT)

    // Asking past the end is a clean stop, not a failure.
    @assert(formats.lpVtbl.Skip(formats, 99) == S_FALSE)
    @assert(formats.lpVtbl.Next(formats, 1, &entries[0], &fetched) == S_FALSE)
    @assert(fetched == 0)
}

// A format nobody offered is refused rather than answered with an empty medium.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()

    var data: DragData
    data.setText("text only")

    var session: DragSession
    let source = testDragSource(&session, &data)

    var fmt: FORMATETC
    fmt.cfFormat = cast(CLIPFORMAT) CF_HDROP
    fmt.dwAspect = DVASPECT_CONTENT
    fmt.lindex   = -1
    fmt.tymed    = TYMED_HGLOBAL
    @assert(source.lpVtbl.QueryGetData(source, &fmt) == DV_E_FORMATETC)

    var med: STGMEDIUM
    @assert(source.lpVtbl.GetData(source, &fmt, &med) == DV_E_FORMATETC)

    // A format it does offer, but through a medium it cannot produce, is refused too.
    fmt.cfFormat = cast(CLIPFORMAT) CF_UNICODETEXT
    fmt.tymed    = TYMED_ISTREAM
    @assert(source.lpVtbl.QueryGetData(source, &fmt) == DV_E_FORMATETC)
}

// The interfaces answer the identity questions COM asks of every object.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()

    host.surface.registerDropTarget()
    let target = cast(*IDropTarget) &host.surface.dropTarget

    var out: LPVOID
    var iid = IID_IDropTarget
    @assert(target.lpVtbl.QueryInterface(target, &iid, &out) == S_OK)
    @assert(cast(#null *void) out == cast(#null *void) target)

    // An interface the object does not implement is refused, and clears the output.
    var otherIid = IID_IDataObject
    @assert(target.lpVtbl.QueryInterface(target, &otherIid, &out) == E_NOINTERFACE)
    @assert(out == null)

    // The count the surface owns survives a balanced pair.
    let before = target.lpVtbl.AddRef(target)
    @assert(target.lpVtbl.Release(target) == before - 1)

    var data: DragData
    data.setText("x")
    var session: DragSession
    let source = testDragSource(&session, &data)

    var srcIid = IID_IDataObject
    @assert(source.lpVtbl.QueryInterface(source, &srcIid, &out) == S_OK)
    @assert(source.lpVtbl.QueryInterface(source, &iid, &out) == E_NOINTERFACE)

    let dropSrc   = cast(*IDropSource) &session.dropSrc
    var srcSrcIid = IID_IDropSource
    @assert(dropSrc.lpVtbl.QueryInterface(dropSrc, &srcSrcIid, &out) == S_OK)

    // Escape gives up, letting the button go drops, holding it keeps the gesture running.
    @assert(dropSrc.lpVtbl.QueryContinueDrag(dropSrc, TRUE, MK_LBUTTON) == DRAGDROP_S_CANCEL)
    @assert(dropSrc.lpVtbl.QueryContinueDrag(dropSrc, FALSE, 0) == DRAGDROP_S_DROP)
    @assert(dropSrc.lpVtbl.QueryContinueDrag(dropSrc, FALSE, MK_LBUTTON) == S_OK)
    @assert(dropSrc.lpVtbl.GiveFeedback(dropSrc, DROPEFFECT_COPY) == DRAGDROP_S_USEDEFAULTCURSORS)
}

// A drag that leaves without dropping is reported the same way a cancelled one is.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()

    var data: DragData
    data.addFile("c:/tmp/only.txt")

    var session: DragSession
    let source = testDragSource(&session, &data)

    host.surface.registerDropTarget()
    let target = cast(*IDropTarget) &host.surface.dropTarget

    var effect = DROPEFFECT_COPY
    discard target.lpVtbl.DragEnter(target, source, 0, {60, 60}, &effect)
    @assert(host.surface.dropTarget.data.singleFile() == "c:/tmp/only.txt")

    @assert(target.lpVtbl.DragLeave(target) == S_OK)
    @assert(host.surface.dropTarget.data.files.count == 0)
}
