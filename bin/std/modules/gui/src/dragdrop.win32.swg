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

private func comDragEnter(itf: *IDropTarget, dataObj: #null *IDataObject, grfKeyState: DWORD, pt: POINTL, pdwEffect: *DWORD)->HRESULT
{
    let target = dropTargetOf(itf)
    readDragData(dataObj, &target.data)
    target.allowed = toDropEffect(dref pdwEffect)

    let effect = target.surface!.app.dragUpdate({pt.x, pt.y}, &target.data, target.allowed, toKeyModifiers(grfKeyState))
    dref pdwEffect = fromDropEffect(effect)
    return S_OK
}

private func comDragOver(itf: *IDropTarget, grfKeyState: DWORD, pt: POINTL, pdwEffect: *DWORD)->HRESULT
{
    let target = dropTargetOf(itf)
    target.allowed = toDropEffect(dref pdwEffect)

    let effect = target.surface!.app.dragUpdate({pt.x, pt.y}, &target.data, target.allowed, toKeyModifiers(grfKeyState))
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

private func comDrop(itf: *IDropTarget, dataObj: #null *IDataObject, grfKeyState: DWORD, pt: POINTL, pdwEffect: *DWORD)->HRESULT
{
    let target = dropTargetOf(itf)

    // The object handed to Drop is the authoritative one: a source may publish more on release
    // than it announced while hovering, and a delayed-rendering source only produces here.
    readDragData(dataObj, &target.data)
    target.allowed = toDropEffect(dref pdwEffect)

    let effect = target.surface!.app.dragDrop({pt.x, pt.y}, &target.data, target.allowed, toKeyModifiers(grfKeyState))
    dref pdwEffect = fromDropEffect(effect)
    target.data.clear()
    return S_OK
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

    g_PngDragFormat = catch RegisterClipboardFormatA(@dataof("PNG"))
}
