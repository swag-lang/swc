#global public
#global if #os == Swag.TargetOs.Windows

using Core, Win32, Pixel

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

private func startOle()
{
    if g_OleStarted do
        return
    g_OleStarted = true
    discard OleInitialize(null)
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

// Asks the source for one clipboard format as a memory block, and reports whether it produced it.
//
// The caller owns the medium from here and has to release it. Only `TYMED_HGLOBAL` is asked for,
// so a source offering the same format solely as a stream reads as offering nothing.
private func requestGlobalMedium(dataObj: *IDataObject, format: u32, med: *STGMEDIUM)->bool
{
    var fmt: FORMATETC
    fmt.cfFormat = cast(CLIPFORMAT) format
    fmt.dwAspect = DVASPECT_CONTENT
    fmt.lindex   = -1
    fmt.tymed    = TYMED_HGLOBAL

    return dataObj.lpVtbl.GetData(dataObj, &fmt, med) == S_OK
}

// Returns the payload of `format` as raw bytes, or an empty array when the source offers none.
private func readGlobalFormat(dataObj: *IDataObject, format: u32)->Array'u8
{
    var result: retval

    var med: STGMEDIUM
    if !requestGlobalMedium(dataObj, format, &med) do
        return result
    defer ReleaseStgMedium(&med)

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

// Reads every format the GUI understands out of a native drag, once per gesture.
private func readDragData(dataObj: #null *IDataObject, data: *DragData)
{
    data.clear()
    if !dataObj do
        return

    let obj = dataObj!

    // Files. The medium is a DROPFILES block, which is exactly what the shell drag helpers read.
    #scope
    {
        var med: STGMEDIUM
        if !requestGlobalMedium(obj, CF_HDROP, &med) do
            break
        defer ReleaseStgMedium(&med)

        let hDrop = cast(HDROP) med.hGlobal
        let count = DragQueryFileW(hDrop, Swag.U32.Max, null, 0)

        var buf: Array'u16
        for [i] in count
        {
            let len = DragQueryFileW(hDrop, i, null, 0)
            if !len do
                continue
            buf.resize(len + 1)
            discard DragQueryFileW(hDrop, i, buf.buffer, len + 1)
            data.addFile(Utf8.fromUtf16(@mkslice(buf.buffer!, cast(u64) len)))
        }
    }

    // Text, preferring the Unicode form the way the clipboard does.
    #scope
    {
        let utf16 = readGlobalFormat(obj, CF_UNICODETEXT)
        if utf16.count >= 2
        {
            let pz = cast(const [*] u16) utf16.buffer!
            data.setText(Utf8.fromUtf16(@mkslice(pz, Utf16.lengthZeroTerminated(pz))))
            break
        }

        let ansi = readGlobalFormat(obj, CF_TEXT)
        if ansi.count do
            data.setText(@mkstring(ansi.buffer!, @countof(cast(cstring) ansi.buffer!)))
    }

    // Image. A browser drags PNG bytes and the desktop drags a DIB; both decode from the name.
    #scope
    {
        if g_PngDragFormat
        {
            let png = readGlobalFormat(obj, g_PngDragFormat)
            if png.count
            {
                data.setImage("drag.png", png.toSlice())
                break
            }
        }

        let dib = readGlobalFormat(obj, CF_DIB)
        if dib.count do
            data.setImage("drag.bmp", dib.toSlice())
    }
}

private func dropTargetOf(itf: *IDropTarget)->*SurfaceDropTarget => cast(*SurfaceDropTarget) itf

private func comQueryInterface(itf: *IDropTarget, riid: const *GUID, ppv: *LPVOID)->HRESULT
{
    dref ppv = null
    if !isEqualGuid(dref riid, IID_IUnknown) and !isEqualGuid(dref riid, IID_IDropTarget) do
        return E_NOINTERFACE

    let target = dropTargetOf(itf)
    target.refCount += 1
    dref ppv        = cast([*] void) itf
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

private func comDragEnter(itf: *IDropTarget, dataObj: #null *IDataObject, grfKeyState: DWORD, packedPt: PACKEDPOINTL, pdwEffect: *DWORD)->HRESULT
{
    let pt     = pointFromPacked(packedPt)
    let target = dropTargetOf(itf)
    readDragData(dataObj, &target.data)
    target.allowed = toDropEffect(dref pdwEffect)

    let surface = target.surface!
    let hit     = surface.windowAt({pt.x, pt.y})

    let effect = surface.app.dragUpdate(surface, {pt.x, pt.y}, &target.data, target.allowed, toKeyModifiers(grfKeyState))
    dref pdwEffect = fromDropEffect(effect)
    return S_OK
}

private func comDragOver(itf: *IDropTarget, grfKeyState: DWORD, packedPt: PACKEDPOINTL, pdwEffect: *DWORD)->HRESULT
{
    let pt     = pointFromPacked(packedPt)
    let target = dropTargetOf(itf)
    target.allowed = toDropEffect(dref pdwEffect)

    let surface = target.surface!
    let effect  = surface.app.dragUpdate(surface, {pt.x, pt.y}, &target.data, target.allowed, toKeyModifiers(grfKeyState))
    dref pdwEffect = fromDropEffect(effect)
    return S_OK
}

private func comDragLeave(itf: *IDropTarget)->HRESULT
{
    let target = dropTargetOf(itf)
    target.surface!.app.dragLeave(&target.data)
    target.data.clear()
    return S_OK
}

private func comDrop(itf: *IDropTarget, dataObj: #null *IDataObject, grfKeyState: DWORD, packedPt: PACKEDPOINTL, pdwEffect: *DWORD)->HRESULT
{
    let pt     = pointFromPacked(packedPt)
    let target = dropTargetOf(itf)

    // The object handed to Drop is the authoritative one: a source may publish more on release
    // than it announced while hovering, and a delayed-rendering source only produces here.
    readDragData(dataObj, &target.data)
    target.allowed = toDropEffect(dref pdwEffect)

    let surface = target.surface!
    let effect  = surface.app.dragDrop(surface, {pt.x, pt.y}, &target.data, target.allowed, toKeyModifiers(grfKeyState))
    dref pdwEffect = fromDropEffect(effect)
    target.data.clear()
    return S_OK
}

// ---------------------------------------------------------------------------
// Outgoing: the three interfaces a source has to be, and the gesture that runs them.
// ---------------------------------------------------------------------------

// Formats the payload can produce, most specific first, because a target picks the first
// one it understands out of the enumeration.
private func offeredFormats(data: *DragData)->Array'CLIPFORMAT
{
    var result: retval
    if data.hasFiles() do
        result.add(cast(CLIPFORMAT) CF_HDROP)
    if data.hasImage()
    {
        if g_PngDragFormat do
            result.add(cast(CLIPFORMAT) g_PngDragFormat)
        result.add(cast(CLIPFORMAT) CF_DIB)
    }

    if data.hasText()
    {
        result.add(cast(CLIPFORMAT) CF_UNICODETEXT)
        result.add(cast(CLIPFORMAT) CF_TEXT)
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
        cursor      += wide.count
        dref cursor = 0
        cursor      += 1
    }

    dref cursor = 0
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

// The data object of one outgoing drag. Its payload is borrowed from the caller of
// [[Gui.Wnd.startDrag]], which blocks for the whole gesture.
#[Swag.NoCopy]
internal struct DragDataObject
{
    lpVtbl:   #null *IDataObjectVtbl     // Interface header OLE calls through; must stay first.
    refCount: ULONG = 1                  // Reference count; the session owns the storage.
    data:     #null *DragData            // Payload the formats below are produced from.
    formats:  Array'CLIPFORMAT           // Clipboard formats this object can produce.
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
    formats:  Array'CLIPFORMAT              // Snapshot of what the data object offers.
    index:    u64                           // Next entry the enumeration returns.
}

// The source side of the gesture: what tells OLE to keep going, drop, or give up.
#[Swag.NoCopy]
internal struct DragDropSource
{
    lpVtbl:   #null *IDropSourceVtbl     // Interface header OLE calls through; must stay first.
    refCount: ULONG = 1                  // Reference count; the session owns the storage.
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
    dref ppv = null
    if !isEqualGuid(dref riid, IID_IUnknown) and !isEqualGuid(dref riid, IID_IDataObject) do
        return E_NOINTERFACE

    dataObjectOf(itf).refCount += 1
    dref ppv = cast([*] void) itf
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

// Whether this object can answer `fmt`, which is also the whole of `QueryGetData`.
private func srcOffers(obj: *DragDataObject, fmt: const *FORMATETC)->bool
{
    if !(fmt.tymed & TYMED_HGLOBAL) or fmt.dwAspect != DVASPECT_CONTENT do
        return false
    for f in obj.formats where f == fmt.cfFormat do
        return true
    return false
}

private func srcQueryGetData(itf: *IDataObject, fmt: const *FORMATETC)->HRESULT
{
    return srcOffers(dataObjectOf(itf), fmt) ? S_OK : DV_E_FORMATETC
}

private func srcGetData(itf: *IDataObject, fmt: const *FORMATETC, med: *STGMEDIUM)->HRESULT
{
    let obj = dataObjectOf(itf)
    if !srcOffers(obj, fmt) do
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
        hglob = toGlobalBlock(data.imageBytes.toSlice())

    if !hglob do
        return E_OUTOFMEMORY

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

private func srcSetData(itf: *IDataObject, fmt: const *FORMATETC, med: *STGMEDIUM, release: BOOL)->HRESULT
{
    discard itf
    discard fmt
    discard med
    discard release
    return E_NOTIMPL
}

private func srcEnumFormatEtc(itf: *IDataObject, direction: DWORD, ppenum: *LPVOID)->HRESULT
{
    dref ppenum = null
    if direction != DATADIR_GET do
        return E_NOTIMPL

    let obj = dataObjectOf(itf)
    let res = Memory.new'DragFormatEnum()
    res.lpVtbl  = &g_FormatEnumVtbl
    res.formats = obj.formats
    dref ppenum = cast([*] void) res
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
    dref ppenum = null
    return OLE_E_ADVISENOTSUPPORTED
}

private func enumQueryInterface(itf: *IEnumFORMATETC, riid: const *GUID, ppv: *LPVOID)->HRESULT
{
    dref ppv = null
    if !isEqualGuid(dref riid, IID_IUnknown) and !isEqualGuid(dref riid, IID_IEnumFORMATETC) do
        return E_NOINTERFACE

    formatEnumOf(itf).refCount += 1
    dref ppv = cast([*] void) itf
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
        let entry = &dest[done]
        entry.cfFormat = obj.formats[obj.index]
        entry.ptd      = null
        entry.dwAspect = DVASPECT_CONTENT
        entry.lindex   = -1
        entry.tymed    = TYMED_HGLOBAL
        obj.index      += 1
        done           += 1
    }

    if fetched do
        dref fetched = cast(ULONG) done
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
    dref ppenum = cast([*] void) res
    return S_OK
}

private func dropSrcQueryInterface(itf: *IDropSource, riid: const *GUID, ppv: *LPVOID)->HRESULT
{
    dref ppv = null
    if !isEqualGuid(dref riid, IID_IUnknown) and !isEqualGuid(dref riid, IID_IDropSource) do
        return E_NOINTERFACE

    dropSourceOf(itf).refCount += 1
    dref ppv = cast([*] void) itf
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

// The desktop draws the copy, move and refuse pointers; there is nothing better to say.
private func dropSrcGiveFeedback(itf: *IDropSource, effect: DWORD)->HRESULT
{
    discard itf
    discard effect
    return DRAGDROP_S_USEDEFAULTCURSORS
}

internal impl DragSession
{
    // Wires both interfaces onto `data`, which has to outlive the gesture.
    internal mtd setup(data: *DragData)
    {
        .dataObj.lpVtbl   = &g_DataObjectVtbl
        .dataObj.refCount = 1
        .dataObj.data     = data
        .dataObj.formats  = offeredFormats(data)

        .dropSrc.lpVtbl   = &g_DropSourceVtbl
        .dropSrc.refCount = 1
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
    // Two things follow from the desktop running the loop. The window stops painting until the
    // gesture ends, the way every application that drags does. And the button that started the
    // drag comes back up inside that loop, so a control tracking a press has to forget it here
    // rather than waiting for a release event that has already been consumed.
    //
    // Answers `None` immediately with no native window, which is what a headless test gets.
    mtd startDrag(data: *DragData, allowed = DropEffect.Copy)->DropEffect
    {
        let surface = .surface
        if !surface or !surface.app.renderer.needsNativeWindow() do
            return .None
        if !data.hasFiles() and !data.hasText() and !data.hasImage() do
            return .None

        // The desktop takes the pointer for the duration; a capture still held here would
        // fight it for the mouse messages.
        if .app().mouseCapture() == me do
            .releaseMouse()

        startOle()

        var session: DragSession
        session.setup(data)

        var effect = DROPEFFECT_NONE
        let result = DoDragDrop(cast(*IDataObject) &session.dataObj, cast(*IDropSource) &session.dropSrc, fromDropEffect(allowed), &effect)
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

    g_PngDragFormat = catch RegisterClipboardFormatA(@dataof("PNG"))
}
