#global public
#global if #os == Swag.TargetOs.Windows

using Core, Win32, Pixel, Gdi32

// OLE drop target of one surface.
//
// The `IDropTarget` header must stay first: OLE calls the vtable with the address of this whole
// structure as `this`, so the two are the same pointer.
//
// The object lives inside its surface rather than on its own. A window-scoped drop target has
// exactly the lifetime of the window, `RevokeDragDrop` releases OLE's reference before that
// window goes away, and an embedded object cannot outlive or be outlived by the surface whose
// events it routes. The reference count is kept because the interface contract has one, but
// reaching zero frees nothing: the surface owns the storage.
#[Swag.NoCopy]
internal struct SurfaceDropTarget
{
    lpVtbl:   #null *IDropTargetVtbl     // Interface header OLE calls through; must stay first.
    refCount: ULONG      = 1             // OLE reference count; the surface holds one of them.
    surface:  #null *Surface             // Surface the gesture is routed into.
    data:     DragData                   // Payload read once per gesture and reused until it ends.
    allowed:  DropEffect = None          // Effects the source published for the running gesture.
}

private var g_DropTargetVtbl: IDropTargetVtbl = undefined

// Whether OLE was started on this thread. Registering a drop target and starting an outgoing
// drag both need it, and the run loop of an application is a single thread.
private var g_OleStarted: bool

// The "PNG" clipboard format, which is what a browser drags an image out as.
private var g_PngDragFormat: UINT

// The two registered formats a file with no path travels through: the group descriptor names
// them, and one `FileContents` medium per index carries the bytes.
private var g_FileDescriptorFormat: UINT
private var g_FileContentsFormat: UINT

private func startOle()
{
    if g_OleStarted do
        return
    g_OleStarted = true
    discard OleInitialize(null)
}

// The shell object that draws the picture being dragged, seen from both sides of a gesture.
//
// It is created on the first drag and both of its interfaces are held for the life of the process:
// creating it is a COM activation, so a process that never drags never pays for one, and a target
// asks for its half on every pointer move of every gesture. A machine where it cannot be created
// simply drags with no picture, which is what happened before it existed.
private var g_DropTargetHelper: #null *IDropTargetHelper
private var g_DragSourceHelper: #null *IDragSourceHelper
private var g_DragHelperTried: bool

private func loadDragHelper()
{
    if g_DragHelperTried do
        return

    g_DragHelperTried = true
    startOle()

    var raw: LPVOID
    var clsid = CLSID_DragDropHelper
    var iid   = IID_IDropTargetHelper
    if CoCreateInstance(&clsid, null, CLSCTX_INPROC_SERVER, &iid, &raw) != S_OK do
        return

    g_DropTargetHelper = cast(*IDropTargetHelper) raw!

    let target = g_DropTargetHelper!
    var srcRaw: LPVOID
    var srcIid = IID_IDragSourceHelper
    if target.lpVtbl.QueryInterface(target, &srcIid, &srcRaw) == S_OK do
        g_DragSourceHelper = cast(*IDragSourceHelper) srcRaw!
}

// The half of the drag helper that draws the picture over a window being dragged over.
//
// Answers `null` when no native window backs the surface, which is what a headless test is: the
// helper paints on the desktop, and there is no desktop under it.
private func dropTargetHelper(surface: *Surface)->#null *IDropTargetHelper
{
    if !surface.hWnd do
        return null

    loadDragHelper()
    return g_DropTargetHelper
}

// The half of the drag helper that gives the gesture its picture in the first place.
private func dragSourceHelper()->#null *IDragSourceHelper
{
    loadDragHelper()
    return g_DragSourceHelper
}

// Converts the key state OLE reports into the modifiers a GUI event carries.
private func toKeyModifiers(grfKeyState: DWORD)->Input.KeyModifiers
{
    var result: retval
    if grfKeyState & MK_SHIFT do
        result |= .Shift
    if grfKeyState & MK_CONTROL do
        result |= .Control
    if grfKeyState & MK_ALT do
        result |= .Alt
    return result
}

// Converts the effect set of a Swag target into the one OLE speaks, and back.
private func toDropEffect(value: DWORD)->DropEffect
{
    var result: retval
    if value & DROPEFFECT_COPY do
        result |= .Copy
    if value & DROPEFFECT_MOVE do
        result |= .Move
    if value & DROPEFFECT_LINK do
        result |= .Link
    return result
}

private func fromDropEffect(value: DropEffect)->DWORD
{
    var result = DROPEFFECT_NONE
    if value.has(.Copy) do
        result |= DROPEFFECT_COPY
    if value.has(.Move) do
        result |= DROPEFFECT_MOVE
    if value.has(.Link) do
        result |= DROPEFFECT_LINK
    return result
}

// Asks the source for one clipboard format through `tymed`, and reports whether it produced it.
//
// The caller owns the medium from here and has to release it. `index` selects one item inside a
// format that carries several, and is `-1` for every format that carries one thing.
private func requestMedium(dataObj: *IDataObject, format: u32, tymed: u32, index: s32, med: *STGMEDIUM)->bool
{
    var fmt: FORMATETC
    fmt.cfFormat = cast(CLIPFORMAT) format
    fmt.dwAspect = DVASPECT_CONTENT
    fmt.lindex   = index
    fmt.tymed    = tymed

    return dataObj.lpVtbl.GetData(dataObj, &fmt, med) == S_OK
}

// Reads a stream from its start to its end into `dest`.
//
// The position a source hands the stream at is not part of the contract, so it is rewound first;
// a stream that refuses to seek is read from wherever it stands, which is the best that can be
// done with it.
private func readStream(stream: *IStream, dest: *Array'u8)
{
    discard stream.lpVtbl.Seek(stream, 0, STREAM_SEEK_SET, null)

    var chunk: [16384] u8
    for
    {
        var read: ULONG
        let hr = stream.lpVtbl.Read(stream, cast([*] void) &chunk[0], @countof(chunk), &read)
        if hr != S_OK and hr != S_FALSE do
            return
        if !read do
            return

        dest.add(@mkslice(cast(const [*] u8) &chunk[0], cast(u64) read))
    }
}

// Returns the payload of `format` as raw bytes, or an empty array when the source offers none.
//
// Both mediums are asked for at once, because a format published solely as a stream — which is
// how some browsers hand over a large image, and how every source of a file with no path hands
// over its content — would otherwise read as nothing on offer.
private func readFormat(dataObj: *IDataObject, format: u32, index: s32 = -1)->Array'u8
{
    var result: retval

    var med: STGMEDIUM
    if !requestMedium(dataObj, format, TYMED_HGLOBAL | TYMED_ISTREAM, index, &med) do
        return result
    defer ReleaseStgMedium(&med)

    if med.tymed == TYMED_ISTREAM
    {
        if med.pstm do
            readStream(med.pstm!, &result)
        return result
    }

    let size = GlobalSize(med.hGlobal)
    if !size do
        return result

    let buf = cast(#null [*] u8) GlobalLock(med.hGlobal)
    if !buf do
        return result
    defer discard GlobalUnlock(buf)

    result.add(@mkslice(buf!, size))
    return result
}

// Reads the files a source carries by content rather than by path.
//
// `withContents` says whether to ask for the bytes as well as the names. A gesture merely hovering
// a window asks for the names alone: making a mail client produce an attachment on every mouse
// move is exactly what deferred rendering exists to avoid, on both sides of the gesture.
private func readFileContents(obj: *IDataObject, data: *DragData, withContents: bool)
{
    if !g_FileDescriptorFormat or !g_FileContentsFormat do
        return

    let block = readFormat(obj, g_FileDescriptorFormat)
    if block.count < #sizeof(UINT) do
        return

    let count = cast(u64) (cast(const *UINT) block.buffer!)[]
    if !count or #sizeof(UINT) + count * #sizeof(FILEDESCRIPTORW) > block.count do
        return

    let descriptors = cast(const [*] FILEDESCRIPTORW) (block.buffer! + #sizeof(UINT))
    for i in count
    {
        let name = cast(const [*] u16) &descriptors[i].cFileName[0]

        var bytes: Array'u8
        if withContents do
            bytes = readFormat(obj, g_FileContentsFormat, cast(s32) i)

        data.addContent(Utf8.fromUtf16(@mkslice(name, Utf16.lengthZeroTerminated(name))), bytes.toSlice())
    }
}

// Reads every format the GUI understands out of a native drag, once per gesture.
//
// `withContents` is what separates a gesture hovering a window from one released on it: only the
// second asks a source to produce the content of a file it holds in memory.
private func readDragData(dataObj: #null *IDataObject, data: *DragData, withContents: bool)
{
    data.clear()
    if !dataObj do
        return

    let obj = dataObj!

    // Files. The medium is a DROPFILES block, which is exactly what the shell drag helpers read.
    #scope(Files)
    {
        var med: STGMEDIUM
        if !requestMedium(obj, CF_HDROP, TYMED_HGLOBAL, -1, &med) do
            break to Files
        defer ReleaseStgMedium(&med)

        let hDrop = cast(HDROP) med.hGlobal
        let count = DragQueryFileW(hDrop, Swag.U32.Max, null, 0)

        var buf: Array'u16
        for i in count
        {
            let len = DragQueryFileW(hDrop, i, null, 0)
            if !len do
                continue
            buf.resize(len + 1)
            discard DragQueryFileW(hDrop, i, buf.buffer, len + 1)
            data.addFile(Utf8.fromUtf16(@mkslice(buf.buffer!, cast(u64) len)))
        }
    }

    // Files the source holds in memory, which is what an attachment dragged out of a mail client
    // is: it has a name and it has bytes, and nothing on disk holds it.
    readFileContents(obj, data, withContents)

    // Text, preferring the Unicode form the way the clipboard does.
    #scope(Text)
    {
        let utf16 = readFormat(obj, CF_UNICODETEXT)
        if utf16.count >= 2
        {
            let pz = cast(const [*] u16) utf16.buffer!
            data.setText(Utf8.fromUtf16(@mkslice(pz, Utf16.lengthZeroTerminated(pz))))
            break to Text
        }

        let ansi = readFormat(obj, CF_TEXT)
        if ansi.count do
            data.setText(@mkstring(ansi.buffer!, @countof(cast(cstring) ansi.buffer!)))
    }

    // Image. A browser drags PNG bytes and the desktop drags a DIB; both decode from the name.
    #scope(Image)
    {
        if g_PngDragFormat
        {
            let png = readFormat(obj, g_PngDragFormat)
            if png.count
            {
                data.setImage("drag.png", png.toSlice())
                break to Image
            }
        }

        let dib = readFormat(obj, CF_DIB)
        if dib.count do
            data.setImage("drag.bmp", dib.toSlice())
    }
}

private func dropTargetOf(itf: *IDropTarget)->*SurfaceDropTarget => cast(*SurfaceDropTarget) itf

private func comQueryInterface(itf: *IDropTarget, riid: const *GUID, ppv: *LPVOID)->HRESULT
{
    ppv[] = null
    if !isEqualGuid(riid[], IID_IUnknown) and !isEqualGuid(riid[], IID_IDropTarget) do
        return E_NOINTERFACE

    let target = dropTargetOf(itf)
    target.refCount += 1
    ppv[]           = cast([*] void) itf
    return S_OK
}

private func comAddRef(itf: *IDropTarget)->ULONG
{
    let target = dropTargetOf(itf)
    target.refCount += 1
    return target.refCount
}

// Reaching zero frees nothing: the object is a member of the surface that registered it.
private func comRelease(itf: *IDropTarget)->ULONG
{
    let target = dropTargetOf(itf)
    if target.refCount do
        target.refCount -= 1
    return target.refCount
}

private func comDragEnter(itf: *IDropTarget, dataObj: #null *IDataObject, grfKeyState: DWORD, pt: POINTL, pdwEffect: *DWORD)->HRESULT
{
    let target = dropTargetOf(itf)
    readDragData(dataObj, &target.data, false)
    target.allowed = toDropEffect(pdwEffect[])

    let surface = target.surface!
    let effect  = surface.app.dragUpdate(surface, {pt.x, pt.y}, &target.data, target.allowed, toKeyModifiers(grfKeyState))
    pdwEffect[] = fromDropEffect(effect)

    let helper = dropTargetHelper(surface)
    if helper
    {
        var cursor = POINT{pt.x, pt.y}
        discard helper.lpVtbl.DragEnter(helper, surface.hWnd, dataObj, &cursor, pdwEffect[])
    }

    return S_OK
}

private func comDragOver(itf: *IDropTarget, grfKeyState: DWORD, pt: POINTL, pdwEffect: *DWORD)->HRESULT
{
    let target = dropTargetOf(itf)
    target.allowed = toDropEffect(pdwEffect[])

    let surface = target.surface!
    let effect  = surface.app.dragUpdate(surface, {pt.x, pt.y}, &target.data, target.allowed, toKeyModifiers(grfKeyState))
    pdwEffect[] = fromDropEffect(effect)

    let helper = dropTargetHelper(surface)
    if helper
    {
        var cursor = POINT{pt.x, pt.y}
        discard helper.lpVtbl.DragOver(helper, &cursor, pdwEffect[])
    }

    return S_OK
}

private func comDragLeave(itf: *IDropTarget)->HRESULT
{
    let target  = dropTargetOf(itf)
    let surface = target.surface!
    surface.app.dragLeave(&target.data)
    target.data.clear()

    let helper = dropTargetHelper(surface)
    if helper do
        discard helper.lpVtbl.DragLeave(helper)

    return S_OK
}

private func comDrop(itf: *IDropTarget, dataObj: #null *IDataObject, grfKeyState: DWORD, pt: POINTL, pdwEffect: *DWORD)->HRESULT
{
    let target = dropTargetOf(itf)

    // The object handed to Drop is the authoritative one: a source may publish more on release
    // than it announced while hovering, and a source that produces on demand only produces here.
    readDragData(dataObj, &target.data, true)
    target.allowed = toDropEffect(pdwEffect[])

    let surface = target.surface!
    let effect  = surface.app.dragDrop(surface, {pt.x, pt.y}, &target.data, target.allowed, toKeyModifiers(grfKeyState))
    pdwEffect[] = fromDropEffect(effect)
    target.data.clear()

    let helper = dropTargetHelper(surface)
    if helper
    {
        var cursor = POINT{pt.x, pt.y}
        discard helper.lpVtbl.Drop(helper, dataObj, &cursor, pdwEffect[])
    }

    return S_OK
}

// ---------------------------------------------------------------------------
// Outgoing: the three interfaces a source has to be, and the gesture that runs them.
// ---------------------------------------------------------------------------

// Formats the payload can produce, most specific first, because a target picks the first
// one it understands out of the enumeration.
private func offeredFormat(format: u32, tymed: u32, index: s32 = -1)->FORMATETC
{
    var result: retval
    result.cfFormat = cast(CLIPFORMAT) format
    result.dwAspect = DVASPECT_CONTENT
    result.lindex   = index
    result.tymed    = tymed
    return result
}

private func offeredFormats(data: *DragData)->Array'FORMATETC
{
    var result: retval
    if data.hasFiles() do
        result.add(offeredFormat(CF_HDROP, TYMED_HGLOBAL))

    // A file the payload carries itself: one descriptor block naming them all, then one content
    // medium per index. The shell reads the content as a stream, so that is what is offered first.
    if data.hasContents() and g_FileDescriptorFormat and g_FileContentsFormat
    {
        result.add(offeredFormat(g_FileDescriptorFormat, TYMED_HGLOBAL))
        for i in data.contents.count do
            result.add(offeredFormat(g_FileContentsFormat, TYMED_ISTREAM | TYMED_HGLOBAL, cast(s32) i))
    }

    if data.hasImage()
    {
        if g_PngDragFormat do
            result.add(offeredFormat(g_PngDragFormat, TYMED_HGLOBAL))
        result.add(offeredFormat(CF_DIB, TYMED_HGLOBAL))
    }

    if data.hasText()
    {
        result.add(offeredFormat(CF_UNICODETEXT, TYMED_HGLOBAL))
        result.add(offeredFormat(CF_TEXT, TYMED_HGLOBAL))
    }

    return result
}

// Copies `bytes` into a movable block, which is what a `TYMED_HGLOBAL` medium transfers.
//
// Ownership goes to whoever receives the medium: the target releases it through
// `ReleaseStgMedium`, so nothing here frees it.
private func toGlobalBlock(bytes: const [..] u8)->HGLOBAL
{
    let hglob = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, @countof(bytes))
    if !hglob do
        return null

    let buf = cast(#null [*] u8) GlobalLock(hglob)
    if !buf
    {
        discard GlobalFree(hglob)
        return null
    }

    Memory.copy(buf!, @dataof(bytes), @countof(bytes))
    discard GlobalUnlock(buf)
    return hglob
}

// Builds the DROPFILES block the shell reads a dropped file list out of: a fixed header, then
// every path as zero-terminated UTF-16, then one more zero to end the list.
private func buildHDrop(data: *DragData)->HGLOBAL
{
    var chars = 1'u64
    for &f in data.files do
        chars += cast(u64) Utf16.fromUtf8(f.toString()).count + 1

    let size  = cast(u64) #sizeof(DROPFILES) + chars * 2
    let hglob = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, size)
    if !hglob do
        return null

    let base = cast(#null [*] u8) GlobalLock(hglob)
    if !base
    {
        discard GlobalFree(hglob)
        return null
    }

    let header = cast(*DROPFILES) base!
    header.pFiles = #sizeof(DROPFILES)
    header.fWide  = TRUE

    var cursor = cast([*] u16) (base! + #sizeof(DROPFILES))
    for &f in data.files
    {
        let wide = Utf16.fromUtf8(f.toString())
        Memory.copy(cursor, wide.buffer, wide.count * 2)
        cursor   += wide.count
        cursor[] = 0
        cursor   += 1
    }

    cursor[] = 0
    discard GlobalUnlock(base)
    return hglob
}

// Builds the device-independent bitmap every picture consumer understands: the bitmap header
// followed by the rows, with no file header, which is what `CF_DIB` is defined as.
private func buildDib(data: *DragData)->HGLOBAL
{
    let image = data.image()
    if !image do
        return null

    let img   = image!
    let size  = cast(u64) #sizeof(Bmp.Header) + img.byteCount
    let hglob = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, size)
    if !hglob do
        return null

    let base = cast(#null [*] u8) GlobalLock(hglob)
    if !base
    {
        discard GlobalFree(hglob)
        return null
    }

    let header = cast(*Bmp.Header) base!
    header.biSize        = #sizeof(Bmp.Header)
    header.biWidth       = img.width
    header.biHeight      = img.height
    header.biPlanes      = 1
    header.biCompression = Bmp.BI_RGB
    header.biBitCount    = img.bitsPerPixel

    Memory.copy(base! + #sizeof(Bmp.Header), img.pixels.buffer, img.byteCount)
    discard GlobalUnlock(base)
    return hglob
}

// Builds the block naming every file the payload carries itself: a count, then one fixed-size
// descriptor per file.
//
// A size is declared only for a file whose content is already in hand. Asking a producer for its
// bytes here would defeat the whole point of deferring them, and a descriptor with no declared
// size is what every source of a generated file publishes.
private func buildFileGroupDescriptor(data: *DragData)->HGLOBAL
{
    let count = data.contents.count
    let size  = cast(u64) #sizeof(UINT) + count * #sizeof(FILEDESCRIPTORW)
    let hglob = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, size)
    if !hglob do
        return null

    let base = cast(#null [*] u8) GlobalLock(hglob)
    if !base
    {
        discard GlobalFree(hglob)
        return null
    }

    (cast(*UINT) base!)[] = cast(UINT) count

    let descriptors = cast([*] FILEDESCRIPTORW) (base! + #sizeof(UINT))
    for i in count
    {
        let item = &data.contents[i]
        let wide = Utf16.fromUtf8(item.name.toString())
        let kept = Math.min(wide.count, cast(u64) MAX_PATH - 1)

        let entry = &descriptors[i]
        entry.dwFlags = FD_UNICODE | FD_PROGRESSUI
        Memory.copy(&entry.cFileName[0], wide.buffer, kept * 2)

        if item.isReady()
        {
            entry.dwFlags       |= FD_FILESIZE
            entry.nFileSizeLow  = cast() (item.bytes.count & 0xFFFFFFFF)
            entry.nFileSizeHigh = cast() (item.bytes.count >> 32)
        }
    }

    discard GlobalUnlock(base)
    return hglob
}

private func buildUnicodeText(data: *DragData)->HGLOBAL
{
    let wide  = Utf16.fromUtf8(data.text.toString())
    let hglob = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, (wide.count + 1) * 2)
    if !hglob do
        return null

    let buf = cast(#null [*] u16) GlobalLock(hglob)
    if !buf
    {
        discard GlobalFree(hglob)
        return null
    }

    Memory.copy(buf!, wide.buffer, wide.count * 2)
    buf![wide.count] = 0
    discard GlobalUnlock(buf)
    return hglob
}

// One format a caller handed the data object rather than read out of it.
//
// The drag-image helper is the reason this exists: it publishes the picture it is going to draw
// by calling `SetData` on the source object, and refuses to initialize when that fails.
internal struct DragStoredFormat
{
    format: FORMATETC     // What was set, including the medium it was set through.
    medium: STGMEDIUM     // The value, owned by this object until it is released.
}

// The data object of one outgoing drag. Its payload is borrowed from the caller of
// [[Gui.Wnd.startDrag]], which blocks for the whole gesture.
#[Swag.NoCopy]
internal struct DragDataObject
{
    lpVtbl:   #null *IDataObjectVtbl     // Interface header OLE calls through; must stay first.
    refCount: ULONG = 1                  // Reference count; the session owns the storage.
    data:     #null *DragData            // Payload the formats below are produced from.
    formats:  Array'FORMATETC            // What this object can produce, and through which medium.
    stored:   Array'DragStoredFormat     // What was handed to it through `SetData`.
}

internal impl DragDataObject
{
    // Releases every medium handed over through `SetData`.
    //
    // Nothing else owns them: `SetData` is called with `fRelease` set, which transfers the medium
    // to this object, and the gesture is over by the time this runs.
    mtd opDrop()
    {
        for &s in .stored do
            ReleaseStgMedium(&s.medium)
    }
}

// The format enumeration a target walks to find out what is on offer.
//
// This one IS heap-allocated, and its count is real: `EnumFormatEtc` hands a reference to the
// caller and `Clone` hands out more, so the object outlives the call that made it.
#[Swag.NoCopy]
internal struct DragFormatEnum
{
    lpVtbl:   #null *IEnumFORMATETCVtbl     // Interface header OLE calls through; must stay first.
    refCount: ULONG = 1                     // Reference count; reaching zero releases the object.
    formats:  Array'FORMATETC               // Snapshot of what the data object offers.
    index:    u64                           // Next entry the enumeration returns.
}

// The source side of the gesture: what tells OLE to keep going, drop, or give up, and what keeps
// the application drawing while the desktop owns the loop.
#[Swag.NoCopy]
internal struct DragDropSource
{
    lpVtbl:   #null *IDropSourceVtbl     // Interface header OLE calls through; must stay first.
    refCount: ULONG = 1                  // Reference count; the session owns the storage.
    app:      #null *Application         // Application to keep painting for the length of the gesture.
}

// One outgoing drag, alive for exactly the call that runs it.
//
// The data object and the drop source are members rather than allocations: `DoDragDrop` blocks
// until the gesture ends, so the frame that started it outlives every callback OLE makes, and a
// reference count reaching zero has nothing to release.
#[Swag.NoCopy]
internal struct DragSession
{
    dataObj: DragDataObject     // What the target reads the payload out of.
    dropSrc: DragDropSource     // What answers the keyboard and the mouse buttons.
}

private var g_DataObjectVtbl: IDataObjectVtbl = undefined
private var g_FormatEnumVtbl: IEnumFORMATETCVtbl = undefined
private var g_DropSourceVtbl: IDropSourceVtbl = undefined

// Selects the outgoing direction of a format enumeration.
private const DATADIR_GET = 1'u32

private func dataObjectOf(itf: *IDataObject)->*DragDataObject => cast(*DragDataObject) itf
private func formatEnumOf(itf: *IEnumFORMATETC)->*DragFormatEnum => cast(*DragFormatEnum) itf
private func dropSourceOf(itf: *IDropSource)->*DragDropSource => cast(*DragDropSource) itf

private func srcQueryInterface(itf: *IDataObject, riid: const *GUID, ppv: *LPVOID)->HRESULT
{
    ppv[] = null
    if !isEqualGuid(riid[], IID_IUnknown) and !isEqualGuid(riid[], IID_IDataObject) do
        return E_NOINTERFACE

    dataObjectOf(itf).refCount += 1
    ppv[] = cast([*] void) itf
    return S_OK
}

private func srcAddRef(itf: *IDataObject)->ULONG
{
    let obj = dataObjectOf(itf)
    obj.refCount += 1
    return obj.refCount
}

// Reaching zero frees nothing: the object is a member of the session that runs the gesture.
private func srcRelease(itf: *IDataObject)->ULONG
{
    let obj = dataObjectOf(itf)
    if obj.refCount do
        obj.refCount -= 1
    return obj.refCount
}

// Which of the object's own entries answers `fmt`, or `-1` when none does.
//
// An entry that carries one thing is matched whatever index the caller asked for, because `-1`
// means "the whole of it" and a target is free to spell that as an index. An entry that is one
// item inside a multi-item format has to be named exactly, or a request for the second file
// would answer the first.
private func srcOfferedIndex(obj: *DragDataObject, fmt: const *FORMATETC)->s64
{
    if fmt.dwAspect != DVASPECT_CONTENT do
        return -1

    for &f, i in obj.formats
    {
        if f.cfFormat != fmt.cfFormat or !(fmt.tymed & f.tymed) do
            continue
        if f.lindex != -1 and f.lindex != fmt.lindex do
            continue
        return cast(s64) i
    }

    return -1
}

// Which of the formats handed over through `SetData` answers `fmt`, or `-1` when none does.
private func srcStoredIndex(obj: *DragDataObject, fmt: const *FORMATETC)->s64
{
    for &s, i in obj.stored
    {
        if s.format.cfFormat != fmt.cfFormat or s.format.lindex != fmt.lindex do
            continue
        if s.format.dwAspect != fmt.dwAspect or !(fmt.tymed & s.medium.tymed) do
            continue
        return cast(s64) i
    }

    return -1
}

private func srcQueryGetData(itf: *IDataObject, fmt: const *FORMATETC)->HRESULT
{
    let obj = dataObjectOf(itf)
    if srcOfferedIndex(obj, fmt) < 0 and srcStoredIndex(obj, fmt) < 0 do
        return DV_E_FORMATETC
    return S_OK
}

// Hands out a copy of a format that was set on this object rather than produced by it.
//
// Only a memory block is duplicated. Everything the drag-image helper stores is one, and a
// medium of any other shape would need its own ownership rule to be handed out safely.
private func srcGetStored(obj: *DragDataObject, entry: s64, med: *STGMEDIUM)->HRESULT
{
    let source = &obj.stored[cast(u64) entry].medium
    if source.tymed != TYMED_HGLOBAL do
        return DV_E_TYMED

    let size = GlobalSize(source.hGlobal)
    let buf  = cast(#null [*] u8) GlobalLock(source.hGlobal)
    if !buf do
        return E_OUTOFMEMORY
    defer discard GlobalUnlock(buf)

    let hglob = toGlobalBlock(@mkslice(cast(const [*] u8) buf!, size))
    if !hglob do
        return E_OUTOFMEMORY

    med.tymed          = TYMED_HGLOBAL
    med.hGlobal        = hglob
    med.pUnkForRelease = null
    return S_OK
}

private func srcGetData(itf: *IDataObject, fmt: const *FORMATETC, med: *STGMEDIUM)->HRESULT
{
    let obj    = dataObjectOf(itf)
    let stored = srcStoredIndex(obj, fmt)
    if stored >= 0 do
        return srcGetStored(obj, stored, med)

    let entry = srcOfferedIndex(obj, fmt)
    if entry < 0 do
        return DV_E_FORMATETC

    let data   = obj.data!
    var hglob  = cast(HGLOBAL) null
    let format = cast(u32) fmt.cfFormat

    if format == CF_HDROP do
        hglob = buildHDrop(data)
    elif format == CF_DIB do
        hglob = buildDib(data)
    elif format == CF_UNICODETEXT do
        hglob = buildUnicodeText(data)
    elif format == CF_TEXT do
        hglob = toGlobalBlock(@mkslice(cast(const [*] u8) @dataof(data.text.toString()), cast(u64) @countof(data.text) + 1))
    elif g_PngDragFormat and format == g_PngDragFormat do
        hglob = toGlobalBlock(data.encodedImage())
    elif g_FileDescriptorFormat and format == g_FileDescriptorFormat do
        hglob = buildFileGroupDescriptor(data)
    elif g_FileContentsFormat and format == g_FileContentsFormat do
        hglob = toGlobalBlock(data.contentData(cast(u64) fmt.lindex))

    if !hglob do
        return E_OUTOFMEMORY

    // A stream is what the shell reads a file with no path through, and the block becomes the
    // stream's: releasing the medium frees both.
    if (fmt.tymed & TYMED_ISTREAM) and (obj.formats[cast(u64) entry].tymed & TYMED_ISTREAM)
    {
        var raw: LPVOID
        if CreateStreamOnHGlobal(hglob, TRUE, &raw) != S_OK
        {
            discard GlobalFree(hglob)
            return E_OUTOFMEMORY
        }

        med.tymed          = TYMED_ISTREAM
        med.pstm           = cast(*IStream) raw!
        med.pUnkForRelease = null
        return S_OK
    }

    med.tymed          = TYMED_HGLOBAL
    med.hGlobal        = hglob
    med.pUnkForRelease = null
    return S_OK
}

private func srcGetDataHere(itf: *IDataObject, fmt: const *FORMATETC, med: *STGMEDIUM)->HRESULT
{
    discard itf
    discard fmt
    discard med
    return E_NOTIMPL
}

private func srcGetCanonicalFormatEtc(itf: *IDataObject, fmtIn: const *FORMATETC, fmtOut: *FORMATETC)->HRESULT
{
    discard itf
    discard fmtIn
    fmtOut.ptd = null
    return DATA_S_SAMEFORMATETC
}

// Takes a format a caller wants this object to carry alongside what it produces itself.
//
// The drag-image helper is the only caller in practice, and it hands the medium over rather than
// lending it, which is the `fRelease` case. Lending would mean copying a medium of any shape, so
// that case is refused instead of half-supported.
private func srcSetData(itf: *IDataObject, fmt: const *FORMATETC, med: *STGMEDIUM, release: BOOL)->HRESULT
{
    if !release do
        return E_NOTIMPL

    let obj = dataObjectOf(itf)

    // Setting a format twice replaces it, so the helper can change its mind about the picture.
    let already = srcStoredIndex(obj, fmt)
    if already >= 0
    {
        let slot = &obj.stored[cast(u64) already]
        ReleaseStgMedium(&slot.medium)
        slot.medium = med[]
        return S_OK
    }

    obj.stored.add({format: fmt[], medium: med[]})
    return S_OK
}

private func srcEnumFormatEtc(itf: *IDataObject, direction: DWORD, ppenum: *LPVOID)->HRESULT
{
    ppenum[] = null
    if direction != DATADIR_GET do
        return E_NOTIMPL

    // What was set on the object is part of what it offers: a target walking the enumeration has
    // to find the drag picture there too, not only through a request that names it.
    let obj = dataObjectOf(itf)
    let res = Memory.new'DragFormatEnum()
    res.lpVtbl  = &g_FormatEnumVtbl
    res.formats = obj.formats
    for &s in obj.stored do
        res.formats.add(s.format)

    ppenum[] = cast([*] void) res
    return S_OK
}

private func srcDAdvise(itf: *IDataObject, fmt: const *FORMATETC, flags: DWORD, sink: #null *void, conn: *DWORD)->HRESULT
{
    discard itf
    discard fmt
    discard flags
    discard sink
    discard conn
    return OLE_E_ADVISENOTSUPPORTED
}

private func srcDUnadvise(itf: *IDataObject, conn: DWORD)->HRESULT
{
    discard itf
    discard conn
    return OLE_E_ADVISENOTSUPPORTED
}

private func srcEnumDAdvise(itf: *IDataObject, ppenum: *LPVOID)->HRESULT
{
    discard itf
    ppenum[] = null
    return OLE_E_ADVISENOTSUPPORTED
}

private func enumQueryInterface(itf: *IEnumFORMATETC, riid: const *GUID, ppv: *LPVOID)->HRESULT
{
    ppv[] = null
    if !isEqualGuid(riid[], IID_IUnknown) and !isEqualGuid(riid[], IID_IEnumFORMATETC) do
        return E_NOINTERFACE

    formatEnumOf(itf).refCount += 1
    ppv[] = cast([*] void) itf
    return S_OK
}

private func enumAddRef(itf: *IEnumFORMATETC)->ULONG
{
    let obj = formatEnumOf(itf)
    obj.refCount += 1
    return obj.refCount
}

private func enumRelease(itf: *IEnumFORMATETC)->ULONG
{
    let obj = formatEnumOf(itf)
    if obj.refCount do
        obj.refCount -= 1
    let left = obj.refCount
    if !left do
        Memory.delete(obj)
    return left
}

private func enumNext(itf: *IEnumFORMATETC, count: ULONG, entries: *FORMATETC, fetched: #null *ULONG)->HRESULT
{
    let obj  = formatEnumOf(itf)
    let dest = cast([*] FORMATETC) entries
    var done = 0'u64
    while done < count and obj.index < obj.formats.count
    {
        dest[done]     = obj.formats[obj.index]
        dest[done].ptd = null
        obj.index      += 1
        done           += 1
    }

    if fetched do
        fetched[] = cast(ULONG) done
    return done == count ? S_OK : S_FALSE
}

private func enumSkip(itf: *IEnumFORMATETC, count: ULONG)->HRESULT
{
    let obj  = formatEnumOf(itf)
    let left = obj.formats.count - obj.index
    obj.index += Math.min(cast(u64) count, left)
    return count <= left ? S_OK : S_FALSE
}

private func enumReset(itf: *IEnumFORMATETC)->HRESULT
{
    formatEnumOf(itf).index = 0
    return S_OK
}

private func enumClone(itf: *IEnumFORMATETC, ppenum: *LPVOID)->HRESULT
{
    let obj = formatEnumOf(itf)
    let res = Memory.new'DragFormatEnum()
    res.lpVtbl  = &g_FormatEnumVtbl
    res.formats = obj.formats
    res.index   = obj.index
    ppenum[]    = cast([*] void) res
    return S_OK
}

private func dropSrcQueryInterface(itf: *IDropSource, riid: const *GUID, ppv: *LPVOID)->HRESULT
{
    ppv[] = null
    if !isEqualGuid(riid[], IID_IUnknown) and !isEqualGuid(riid[], IID_IDropSource) do
        return E_NOINTERFACE

    dropSourceOf(itf).refCount += 1
    ppv[] = cast([*] void) itf
    return S_OK
}

private func dropSrcAddRef(itf: *IDropSource)->ULONG
{
    let obj = dropSourceOf(itf)
    obj.refCount += 1
    return obj.refCount
}

// Reaching zero frees nothing: the object is a member of the session that runs the gesture.
private func dropSrcRelease(itf: *IDropSource)->ULONG
{
    let obj = dropSourceOf(itf)
    if obj.refCount do
        obj.refCount -= 1
    return obj.refCount
}

// Escape gives up, releasing the button drops, and anything else keeps the gesture running.
private func dropSrcQueryContinueDrag(itf: *IDropSource, escapePressed: BOOL, grfKeyState: DWORD)->HRESULT
{
    discard itf
    if escapePressed do
        return DRAGDROP_S_CANCEL
    if !(grfKeyState & (MK_LBUTTON | MK_RBUTTON)) do
        return DRAGDROP_S_DROP
    return S_OK
}

// The desktop draws the copy, move and refuse pointers; there is nothing better to say about the
// cursor. What this callback is really used for is the frame.
//
// `DoDragDrop` runs a modal loop of its own, so the application never reaches its own for the
// length of the gesture, and a source window that stops painting the moment a drag leaves it is
// what the user sees. This is the one place inside that loop where a frame can be drawn, and it
// fires on every move.
//
// Painting is all that happens here, and deliberately so. Running a whole frame would dispatch
// input inside a loop that already owns the mouse and the keyboard, and would destroy windows the
// gesture is standing on. The tree itself stays current without any of that: OLE delivers the
// drop-target callbacks from inside this same loop, so a highlight turning on still turns on.
private func dropSrcGiveFeedback(itf: *IDropSource, effect: DWORD)->HRESULT
{
    discard effect

    let app = dropSourceOf(itf).app
    if app do
        app.paintSurfaces()

    return DRAGDROP_S_USEDEFAULTCURSORS
}

// Longest side, in physical pixels, of the picture the desktop drags under the pointer.
//
// The gesture carries a thumbnail whatever the payload is: a full-resolution capture next to the
// cursor would hide what it is being dropped on, which is the one thing the user is looking at.
private const DragImageMaxSide = 160's32

// Builds the picture the desktop drags under the pointer out of `image`.
//
// The section is 32-bit and top-down, with alpha already multiplied in, because the helper blends
// it against the desktop the way a layered window is blended. Ownership goes to the helper the
// moment `InitializeFromBitmap` succeeds, so nothing here deletes it on that path.
private func buildDragBitmap(image: const *Image)->{ bmp: HBITMAP, width, height: s32 }
{
    var result: retval

    var img = image[]
    if !img.isValid() do
        return result

    if img.width >= img.height and img.width > DragImageMaxSide do
        img.resize(DragImageMaxSide, 0, .CatmullRom)
    elif img.height > img.width and img.height > DragImageMaxSide do
        img.resize(0, DragImageMaxSide, .CatmullRom)

    with var info: BITMAPINFO
    {
        .bmiHeader.biSize        = #sizeof(BITMAPINFOHEADER)
        .bmiHeader.biWidth       = img.width
        .bmiHeader.biHeight      = -img.height
        .bmiHeader.biPlanes      = 1
        .bmiHeader.biBitCount    = 32
        .bmiHeader.biCompression = BI_RGB
    }

    var raw: #null *void
    let bmp = catch CreateDIBSection(null, &info, DIB_RGB_COLORS, &raw, null, 0) as err
    if err != null or !bmp or !raw do
        return result

    let dest = cast([*] u8) raw!
    for y in img.height
    {
        for x in img.width
        {
            let col = img.pixelColor(x, y)
            let at  = cast(u64) (y * img.width + x) * 4
            dest[at + 0] = cast() (cast(u32) col.b * cast(u32) col.a / 255)
            dest[at + 1] = cast() (cast(u32) col.g * cast(u32) col.a / 255)
            dest[at + 2] = cast() (cast(u32) col.r * cast(u32) col.a / 255)
            dest[at + 3] = col.a
        }
    }

    result.bmp    = bmp
    result.width  = img.width
    result.height = img.height
    return result
}

// Gives the gesture the picture the desktop drags under the pointer.
//
// The helper publishes what it is going to draw by calling `SetData` on the data object, which is
// why that object takes formats it did not produce. A machine or a payload that cannot provide a
// picture simply drags with an arrow, the way it did before this existed.
private func attachDragImage(dataObj: *IDataObject, image: const *Image)
{
    let found = dragSourceHelper()
    if !found do
        return

    let helper  = found!
    let picture = buildDragBitmap(image)
    if !picture.bmp do
        return

    with var shape: SHDRAGIMAGE
    {
        .hbmpDragImage = picture.bmp
        .crColorKey    = CLR_NONE
        .sizeDragImage = {picture.width, picture.height}
        .ptOffset      = {picture.width / 2, picture.height / 2}
    }

    // The bitmap is the helper's from here, and only on the path where it took it.
    if helper.lpVtbl.InitializeFromBitmap(helper, &shape, dataObj) != S_OK do
        catch DeleteObject(cast(HGDIOBJ) picture.bmp)
}

internal impl DragSession
{
    // Wires both interfaces onto `data`, which has to outlive the gesture.
    internal mtd setup(data: *DragData, app: #null *Application = null)
    {
        .dataObj.lpVtbl   = &g_DataObjectVtbl
        .dataObj.refCount = 1
        .dataObj.data     = data
        .dataObj.formats  = offeredFormats(data)

        .dropSrc.lpVtbl   = &g_DropSourceVtbl
        .dropSrc.refCount = 1
        .dropSrc.app      = app
    }
}

impl Wnd
{
    // Carries `data` to whatever the pointer is released on, and returns what was done with it.
    //
    // This runs the gesture: it does not return until the user drops or gives up, because the
    // desktop owns the pointer for the whole of it. The payload is borrowed and has to outlive
    // the call, which a local of the calling frame does by construction. `allowed` is what the
    // target may choose from; the answer is the single effect it settled on, or `None` when the
    // drag was cancelled or refused.
    //
    // `picture` is what the desktop draws under the pointer for the length of the gesture, and
    // defaults to the picture the payload already carries. A drag with nothing under the cursor
    // but an arrow reads as a lesser gesture than the same drag out of a file manager, so a
    // source that carries no image of its own is worth handing one.
    //
    // One thing follows from the desktop running the loop: the button that started the drag comes
    // back up inside it, so a control tracking a press has to forget it here rather than waiting
    // for a release event that has already been consumed. The application keeps drawing, from the
    // feedback callback the same loop makes.
    //
    // Answers `None` immediately with no native window, which is what a headless test gets.
    mtd startDrag(data: *DragData, allowed = DropEffect.Copy, picture: #null const *Pixel.Image = null)->DropEffect
    {
        let surface = .surface
        if !surface or !surface.app.renderer.needsNativeWindow() do
            return .None
        if !data.hasFiles() and !data.hasContents() and !data.hasText() and !data.hasImage() do
            return .None

        // The desktop takes the pointer for the duration; a capture still held here would
        // fight it for the mouse messages.
        if .app().mouseCapture() == me do
            .releaseMouse()

        startOle()

        var session: DragSession
        session.setup(data, surface.app)

        let dataObj = cast(*IDataObject) &session.dataObj
        let shown: #null const *Pixel.Image = picture orelse data.image()
        if shown do
            attachDragImage(dataObj, shown!)

        var effect = DROPEFFECT_NONE
        let result = DoDragDrop(dataObj, cast(*IDropSource) &session.dropSrc, fromDropEffect(allowed), &effect)
        if result != DRAGDROP_S_DROP do
            return .None

        return toDropEffect(effect)
    }

    // Whether the pointer has travelled far enough from where it was pressed to mean a drag.
    //
    // Both points are in this window's surface coordinates. The distance is the one the desktop
    // is configured with, so a control does not invent a threshold of its own and a shaky hand
    // on a click does not start dragging.
    mtd const exceedsDragThreshold(origin, current: Math.Point)->bool
    {
        let scale = .surface ? .surface.dpiScale : 1.0
        let dx    = Math.abs(current.x - origin.x) * scale
        let dy    = Math.abs(current.y - origin.y) * scale
        return dx >= cast(f32) GetSystemMetrics(SM_CXDRAG) or dy >= cast(f32) GetSystemMetrics(SM_CYDRAG)
    }
}

internal impl Surface
{
    // Makes the surface receive drags from Explorer and from other applications.
    //
    // Every surface is registered as it is created: a window that ignores drops answers `None`
    // through the regular event path, which is what shows the user the pointer refusing them.
    internal mtd registerDropTarget()
    {
        // The interface is wired whether or not a window backs it, so the COM entry points can
        // be driven directly by a test that has no desktop to drag over.
        let target = &.dropTarget
        target.lpVtbl   = &g_DropTargetVtbl
        target.surface  = me
        target.refCount = 1

        if !.app.renderer.needsNativeWindow() or !.hWnd or .dropTargetActive do
            return

        startOle()
        if RegisterDragDrop(.hWnd, cast(*IDropTarget) target) != S_OK do
            return

        .dropTargetActive = true
    }

    // Stops the surface from receiving drags and releases the reference OLE holds.
    internal mtd revokeDropTarget()
    {
        if !.dropTargetActive do
            return
        .dropTargetActive = false

        // A gesture in flight over a surface being destroyed would otherwise leave the
        // application pointing at a window that is going away. Nothing is told it was left:
        // the whole tree that would hear it is what is being taken down.
        if .app.dragEnterWnd and .app.dragEnterWnd.surface == me do
            .app.dragEnterWnd = null

        if .hWnd do
            discard RevokeDragDrop(.hWnd)
        .dropTarget.data.clear()
    }
}

#init
{
    g_DropTargetVtbl.QueryInterface = &comQueryInterface
    g_DropTargetVtbl.AddRef         = &comAddRef
    g_DropTargetVtbl.Release        = &comRelease
    g_DropTargetVtbl.DragEnter      = &comDragEnter
    g_DropTargetVtbl.DragOver       = &comDragOver
    g_DropTargetVtbl.DragLeave      = &comDragLeave
    g_DropTargetVtbl.Drop           = &comDrop

    g_DataObjectVtbl.QueryInterface        = &srcQueryInterface
    g_DataObjectVtbl.AddRef                = &srcAddRef
    g_DataObjectVtbl.Release               = &srcRelease
    g_DataObjectVtbl.GetData               = &srcGetData
    g_DataObjectVtbl.GetDataHere           = &srcGetDataHere
    g_DataObjectVtbl.QueryGetData          = &srcQueryGetData
    g_DataObjectVtbl.GetCanonicalFormatEtc = &srcGetCanonicalFormatEtc
    g_DataObjectVtbl.SetData               = &srcSetData
    g_DataObjectVtbl.EnumFormatEtc         = &srcEnumFormatEtc
    g_DataObjectVtbl.DAdvise               = &srcDAdvise
    g_DataObjectVtbl.DUnadvise             = &srcDUnadvise
    g_DataObjectVtbl.EnumDAdvise           = &srcEnumDAdvise

    g_FormatEnumVtbl.QueryInterface = &enumQueryInterface
    g_FormatEnumVtbl.AddRef         = &enumAddRef
    g_FormatEnumVtbl.Release        = &enumRelease
    g_FormatEnumVtbl.Next           = &enumNext
    g_FormatEnumVtbl.Skip           = &enumSkip
    g_FormatEnumVtbl.Reset          = &enumReset
    g_FormatEnumVtbl.Clone          = &enumClone

    g_DropSourceVtbl.QueryInterface    = &dropSrcQueryInterface
    g_DropSourceVtbl.AddRef            = &dropSrcAddRef
    g_DropSourceVtbl.Release           = &dropSrcRelease
    g_DropSourceVtbl.QueryContinueDrag = &dropSrcQueryContinueDrag
    g_DropSourceVtbl.GiveFeedback      = &dropSrcGiveFeedback

    g_PngDragFormat        = catch RegisterClipboardFormatA(@dataof("PNG"))
    g_FileDescriptorFormat = catch RegisterClipboardFormatA(@dataof(CFSTR_FILEDESCRIPTORW))
    g_FileContentsFormat   = catch RegisterClipboardFormatA(@dataof(CFSTR_FILECONTENTS))
}
