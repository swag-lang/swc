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

// Same, for the release rather than the hover: this is the phase that asks a source to produce
// what it only holds in memory.
//
// Nothing is handed back, because nothing survives: the platform clears the payload as soon as
// the drop is delivered, so a target reads it from inside its own event or not at all.
internal func testRoundTripDrop(host: *Testing.HeadlessHost, source: *IDataObject)
{
    host.surface.registerDropTarget()
    let target = cast(*IDropTarget) &host.surface.dropTarget

    var effect = DROPEFFECT_COPY
    @assert(target.lpVtbl.Drop(target, source, 0, {60, 60}, &effect) == S_OK)
}

// Copies `text` into a movable block, which is what a `TYMED_HGLOBAL` medium transfers.
internal func testGlobalBlock(text: string)->HGLOBAL
{
    let size  = cast(u64) @countof(text)
    let hglob = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, size)
    let buf   = cast([*] u8) GlobalLock(hglob)!
    Memory.copy(buf, @dataof(text), size)
    discard GlobalUnlock(buf)
    return hglob
}

// A source that publishes everything it has solely as a stream.
//
// The inner object produces the memory block and this one wraps it, refusing `TYMED_HGLOBAL`
// outright. That is the shape of a browser handing over a large image, and the shape the reader
// used to come away from with nothing.
#[Swag.NoCopy]
internal struct StreamOnlySource
{
    lpVtbl: #null *IDataObjectVtbl     // Interface header OLE calls through; must stay first.
    inner:  #null *DragDataObject      // Object the blocks are produced by.
}

private var g_StreamOnlyVtbl: IDataObjectVtbl = undefined

impl StreamOnlySource
{
    internal mtd setup(inner: *DragDataObject)
    {
        .lpVtbl = &g_StreamOnlyVtbl
        .inner  = inner
    }
}

private func streamOnlyOf(itf: *IDataObject)->*StreamOnlySource => cast(*StreamOnlySource) itf

private func streamOnlyQueryInterface(itf: *IDataObject, riid: const *GUID, ppv: *LPVOID)->HRESULT
{
    discard riid
    dref ppv = cast([*] void) itf
    return S_OK
}

private func streamOnlyAddRef(itf: *IDataObject)->ULONG
{
    discard itf
    return 1
}

private func streamOnlyRelease(itf: *IDataObject)->ULONG
{
    discard itf
    return 1
}

private func streamOnlyQueryGetData(itf: *IDataObject, fmt: const *FORMATETC)->HRESULT
{
    if !(fmt.tymed & TYMED_ISTREAM) do
        return DV_E_TYMED

    let inner = cast(*IDataObject) streamOnlyOf(itf).inner!
    var ask   = dref fmt
    ask.tymed = TYMED_HGLOBAL
    return inner.lpVtbl.QueryGetData(inner, &ask)
}

private func streamOnlyGetData(itf: *IDataObject, fmt: const *FORMATETC, med: *STGMEDIUM)->HRESULT
{
    if !(fmt.tymed & TYMED_ISTREAM) do
        return DV_E_TYMED

    let inner = cast(*IDataObject) streamOnlyOf(itf).inner!
    var ask   = dref fmt
    ask.tymed = TYMED_HGLOBAL

    var block: STGMEDIUM
    if inner.lpVtbl.GetData(inner, &ask, &block) != S_OK do
        return DV_E_FORMATETC

    var raw: LPVOID
    if CreateStreamOnHGlobal(block.hGlobal, TRUE, &raw) != S_OK
    {
        ReleaseStgMedium(&block)
        return E_OUTOFMEMORY
    }

    med.tymed          = TYMED_ISTREAM
    med.pstm           = cast(*IStream) raw!
    med.pUnkForRelease = null
    return S_OK
}

private func streamOnlyNotImpl(itf: *IDataObject, fmt: const *FORMATETC, med: *STGMEDIUM)->HRESULT
{
    discard itf
    discard fmt
    discard med
    return E_NOTIMPL
}

private func streamOnlyCanonical(itf: *IDataObject, fmtIn: const *FORMATETC, fmtOut: *FORMATETC)->HRESULT
{
    discard itf
    discard fmtIn
    fmtOut.ptd = null
    return DATA_S_SAMEFORMATETC
}

private func streamOnlySetData(itf: *IDataObject, fmt: const *FORMATETC, med: *STGMEDIUM, release: BOOL)->HRESULT
{
    discard itf
    discard fmt
    discard med
    discard release
    return E_NOTIMPL
}

private func streamOnlyEnum(itf: *IDataObject, direction: DWORD, ppenum: *LPVOID)->HRESULT
{
    discard itf
    discard direction
    dref ppenum = null
    return E_NOTIMPL
}

private func streamOnlyAdvise(itf: *IDataObject, fmt: const *FORMATETC, flags: DWORD, sink: #null *void, conn: *DWORD)->HRESULT
{
    discard itf
    discard fmt
    discard flags
    discard sink
    discard conn
    return OLE_E_ADVISENOTSUPPORTED
}

private func streamOnlyUnadvise(itf: *IDataObject, conn: DWORD)->HRESULT
{
    discard itf
    discard conn
    return OLE_E_ADVISENOTSUPPORTED
}

private func streamOnlyEnumAdvise(itf: *IDataObject, ppenum: *LPVOID)->HRESULT
{
    discard itf
    dref ppenum = null
    return OLE_E_ADVISENOTSUPPORTED
}

#init
{
    g_StreamOnlyVtbl.QueryInterface        = &streamOnlyQueryInterface
    g_StreamOnlyVtbl.AddRef                = &streamOnlyAddRef
    g_StreamOnlyVtbl.Release               = &streamOnlyRelease
    g_StreamOnlyVtbl.GetData               = &streamOnlyGetData
    g_StreamOnlyVtbl.GetDataHere           = &streamOnlyNotImpl
    g_StreamOnlyVtbl.QueryGetData          = &streamOnlyQueryGetData
    g_StreamOnlyVtbl.GetCanonicalFormatEtc = &streamOnlyCanonical
    g_StreamOnlyVtbl.SetData               = &streamOnlySetData
    g_StreamOnlyVtbl.EnumFormatEtc         = &streamOnlyEnum
    g_StreamOnlyVtbl.DAdvise               = &streamOnlyAdvise
    g_StreamOnlyVtbl.DUnadvise             = &streamOnlyUnadvise
    g_StreamOnlyVtbl.EnumDAdvise           = &streamOnlyEnumAdvise
}

// A window that keeps what a drop handed it.
//
// The payload belongs to the platform layer and is cleared the moment the drop is delivered, so
// the only place a file with no path can be read is the event itself — which is also the only
// place a real target would read it.
internal struct ContentCatcher
{
    using wnd: Wnd
    names:     Array'String
    blobs:     Array'(Array'u8)
}

impl IWnd for ContentCatcher
{
    mtd impl onDragDropEvent(evt: *DragDropEvent)
    {
        if evt.kind == .Drop
        {
            .names.clear()
            .blobs.clear()
            for [i] in evt.data.contents.count
            {
                .names.add(evt.data.contents[i].name)

                var blob: Array'u8
                blob.add(evt.data.contentData(i))
                .blobs.add(blob)
            }
        }

        evt.effect = pickDropEffect(evt.allowed, evt.modifiers)
    }
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
    data.setImage(source)

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
    data.setImage(source)

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

// A file with no path travels by name while the gesture hovers, and by content once it lands.
//
// This is what an attachment dragged out of a mail client is, driven here from both ends: the
// source publishes a group descriptor and one content medium per file, and the target reads the
// names on the way over and the bytes on the release.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()

    let catcher = Wnd.create'ContentCatcher(&host.surfaceWnd, {0, 0, 200, 200})
    host.surfaceWnd.view = catcher

    var produced = 0'u32

    var data: DragData
    data.addContent("report.txt", Testing.textBytes("already here").toSlice())
    data.addContent("late.bin", func|&produced|()
    {
        produced += 1
        return Testing.textBytes("made on demand")
    })

    var session: DragSession
    let source = testDragSource(&session, &data)

    // Hovering announces the names and asks for nothing else, so the producer has not run.
    let hovering = testRoundTrip(&host, source)
    @assert(hovering.contents.count == 2)
    @assert(hovering.contents[0].name == "report.txt")
    @assert(hovering.contents[1].name == "late.bin")
    @assert(@countof(hovering.contentData(0)) == 0)
    @assert(produced == 0)

    // The release is what pays for the content, and each file keeps its own. The payload is read
    // from inside the event, because the platform clears it as soon as the drop is delivered.
    testRoundTripDrop(&host, source)
    @assert(produced == 1)
    @assert(catcher.names.count == 2)
    @assert(catcher.names[0] == "report.txt")
    @assert(catcher.names[1] == "late.bin")
    @assert(Testing.bytesAre(catcher.blobs[0].toSlice(), "already here"))
    @assert(Testing.bytesAre(catcher.blobs[1].toSlice(), "made on demand"))
}

// The source enumerates a file with no path as a descriptor plus one entry per file, and names
// the stream medium the shell reads content through.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()

    var data: DragData
    data.addContent("a.txt", cast(const [..] u8) "a")
    data.addContent("b.txt", cast(const [..] u8) "b")

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

    @assert(entries[0].cfFormat == cast(CLIPFORMAT) catch RegisterClipboardFormatA(@dataof(CFSTR_FILEDESCRIPTORW)))
    @assert(entries[0].lindex == -1)

    let contents = cast(CLIPFORMAT) catch RegisterClipboardFormatA(@dataof(CFSTR_FILECONTENTS))
    @assert(entries[1].cfFormat == contents and entries[1].lindex == 0)
    @assert(entries[2].cfFormat == contents and entries[2].lindex == 1)
    @assert(entries[1].tymed & TYMED_ISTREAM)

    // One item of a multi-item format is named exactly, so asking past the last one is refused
    // rather than answered with the first.
    var fmt = entries[2]
    fmt.lindex = 2
    @assert(source.lpVtbl.QueryGetData(source, &fmt) == DV_E_FORMATETC)
}

// A format published solely as a stream reads as what it carries, not as nothing on offer.
//
// This is how some browsers hand over a large image, and how the shell hands over the content of
// a file with no path. The source here answers `TYMED_HGLOBAL` with nothing at all, so a reader
// that only knows memory blocks would come away empty.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()

    var data: DragData
    data.setText("carried by a stream")

    var session: DragSession
    session.setup(&data)

    var streamOnly: StreamOnlySource
    streamOnly.setup(&session.dataObj)

    let payload = testRoundTrip(&host, cast(*IDataObject) &streamOnly)
    @assert(payload.text == "carried by a stream")
}

// A format set on the source object is handed back to whoever asks for it.
//
// The drag-image helper is the reason this path exists: it publishes the picture it will draw by
// calling `SetData`, and refuses to initialize a gesture when that fails.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()

    var data: DragData
    data.setText("payload")

    var session: DragSession
    let source = testDragSource(&session, &data)

    let format = cast(CLIPFORMAT) catch RegisterClipboardFormatA(@dataof("SwagDragPrivate"))

    var fmt: FORMATETC
    fmt.cfFormat = format
    fmt.dwAspect = DVASPECT_CONTENT
    fmt.lindex   = -1
    fmt.tymed    = TYMED_HGLOBAL
    @assert(source.lpVtbl.QueryGetData(source, &fmt) == DV_E_FORMATETC)

    var med: STGMEDIUM
    med.tymed   = TYMED_HGLOBAL
    med.hGlobal = testGlobalBlock("private bits")
    @assert(source.lpVtbl.SetData(source, &fmt, &med, TRUE) == S_OK)

    // It now reads back through the same two questions every other format answers.
    @assert(source.lpVtbl.QueryGetData(source, &fmt) == S_OK)

    var out: STGMEDIUM
    @assert(source.lpVtbl.GetData(source, &fmt, &out) == S_OK)
    @assert(out.tymed == TYMED_HGLOBAL)
    defer ReleaseStgMedium(&out)

    let buf = cast([*] u8) GlobalLock(out.hGlobal)!
    @assert(@mkstring(buf, 12) == "private bits")
    discard GlobalUnlock(buf)

    // And it is part of what the object enumerates, beside what it produces itself.
    var raw: LPVOID
    @assert(source.lpVtbl.EnumFormatEtc(source, 1, &raw) == S_OK)
    let formats = cast(*IEnumFORMATETC) raw!
    defer discard formats.lpVtbl.Release(formats)

    var entries: [8] FORMATETC
    var fetched: ULONG
    discard formats.lpVtbl.Next(formats, 8, &entries[0], &fetched)
    @assert(fetched == 3)
    @assert(entries[2].cfFormat == format)

    // Lending a medium instead of handing it over is refused rather than half-supported.
    @assert(source.lpVtbl.SetData(source, &fmt, &med, FALSE) == E_NOTIMPL)
}
