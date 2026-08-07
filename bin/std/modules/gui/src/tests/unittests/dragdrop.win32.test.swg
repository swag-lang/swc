#global if #os == Swag.TargetOs.Windows
#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Win32

// ---------------------------------------------------------------------------
// The Windows entry points, driven exactly as OLE drives them: through the
// interface vtable, with a real IDataObject handing over a real CF_HDROP medium.
// This is what proves the binding layout — FORMATETC, STGMEDIUM, POINTL by
// value — and the shell parsing of a DROPFILES block, none of which the routing
// tests above can see.
// ---------------------------------------------------------------------------

#[Swag.NoCopy]
struct HDropDataObject
{
    lpVtbl: #null *IDataObjectVtbl
    paths:  Array'String
}

var g_HDropVtbl: IDataObjectVtbl = undefined

func hdropQueryInterface(itf: *IDataObject, riid: const *GUID, ppv: *LPVOID)->HRESULT
{
    discard riid
    dref ppv = cast([*] void) itf
    return S_OK
}

func hdropAddRef(itf: *IDataObject)->ULONG
{
    discard itf
    return 1
}

func hdropRelease(itf: *IDataObject)->ULONG
{
    discard itf
    return 1
}

// Builds the DROPFILES block the shell hands a target: the header, then every path as
// zero-terminated UTF-16, then one more zero to end the list.
func hdropGetData(itf: *IDataObject, fmt: const *FORMATETC, med: *STGMEDIUM)->HRESULT
{
    if fmt.cfFormat != cast(CLIPFORMAT) CF_HDROP do
        return DV_E_FORMATETC

    let obj = cast(*HDropDataObject) itf

    var chars = 1'u64
    for &p in obj.paths do
        chars += cast(u64) @countof(p) + 1

    let size  = cast(u64) #sizeof(DROPFILES) + chars * 2
    let hglob = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, size)
    let base  = cast([*] u8) GlobalLock(hglob)!

    let header = cast(*DROPFILES) base
    header.pFiles = #sizeof(DROPFILES)
    header.fWide  = TRUE

    var cursor = cast([*] u16) (base + #sizeof(DROPFILES))
    for &p in obj.paths
    {
        let wide = Utf16.fromUtf8(p.toString())
        Memory.copy(cursor, wide.buffer, wide.count * 2)
        cursor      += wide.count
        dref cursor = 0
        cursor      += 1
    }

    dref cursor = 0
    discard GlobalUnlock(base)

    med.tymed   = TYMED_HGLOBAL
    med.hGlobal = hglob
    return S_OK
}

func hdropNotImpl2(itf: *IDataObject, a: const *FORMATETC, b: *STGMEDIUM)->HRESULT
{
    discard itf
    discard a
    discard b
    return E_NOTIMPL
}

func hdropQueryGetData(itf: *IDataObject, fmt: const *FORMATETC)->HRESULT
{
    discard itf
    return fmt.cfFormat == cast(CLIPFORMAT) CF_HDROP ? S_OK : DV_E_FORMATETC
}

func hdropCanonical(itf: *IDataObject, a: const *FORMATETC, b: *FORMATETC)->HRESULT
{
    discard itf
    discard a
    discard b
    return E_NOTIMPL
}

func hdropSetData(itf: *IDataObject, a: const *FORMATETC, b: *STGMEDIUM, c: BOOL)->HRESULT
{
    discard itf
    discard a
    discard b
    discard c
    return E_NOTIMPL
}

func hdropEnumFormatEtc(itf: *IDataObject, a: DWORD, b: *LPVOID)->HRESULT
{
    discard itf
    discard a
    discard b
    return E_NOTIMPL
}

func hdropDAdvise(itf: *IDataObject, a: const *FORMATETC, b: DWORD, c: #null *void, d: *DWORD)->HRESULT
{
    discard itf
    discard a
    discard b
    discard c
    discard d
    return E_NOTIMPL
}

func hdropDUnadvise(itf: *IDataObject, a: DWORD)->HRESULT
{
    discard itf
    discard a
    return E_NOTIMPL
}

func hdropEnumDAdvise(itf: *IDataObject, a: *LPVOID)->HRESULT
{
    discard itf
    discard a
    return E_NOTIMPL
}

func makeHDropObject(obj: *HDropDataObject, paths: const [..] string)
{
    g_HDropVtbl.QueryInterface        = &hdropQueryInterface
    g_HDropVtbl.AddRef                = &hdropAddRef
    g_HDropVtbl.Release               = &hdropRelease
    g_HDropVtbl.GetData               = &hdropGetData
    g_HDropVtbl.GetDataHere           = &hdropNotImpl2
    g_HDropVtbl.QueryGetData          = &hdropQueryGetData
    g_HDropVtbl.GetCanonicalFormatEtc = &hdropCanonical
    g_HDropVtbl.SetData               = &hdropSetData
    g_HDropVtbl.EnumFormatEtc         = &hdropEnumFormatEtc
    g_HDropVtbl.DAdvise               = &hdropDAdvise
    g_HDropVtbl.DUnadvise             = &hdropDUnadvise
    g_HDropVtbl.EnumDAdvise           = &hdropEnumDAdvise

    obj.lpVtbl = &g_HDropVtbl
    for p in paths do
        obj.paths.add(p)
}

// The OLE entry points, driven through the interface vtable the way OLE drives them.
//
// A headless surface registers with no desktop under it, so the hit test finds no window and the
// answered effect is `None`; what this proves is everything below that — the vtable dispatch, the
// `POINTL` passed by value, the FORMATETC and STGMEDIUM layouts, and the DROPFILES block the shell
// helpers parse back into paths. The routing above it has its own tests.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()

    var data: HDropDataObject
    makeHDropObject(&data, ["c:/tmp/first.png", "c:/tmp/second.png"])

    host.surface.registerDropTarget()
    let target = cast(*IDropTarget) &host.surface.dropTarget
    let source = cast(*IDataObject) &data
    let dropPt = POINTL{60, 60}

    var effect = DROPEFFECT_COPY | DROPEFFECT_MOVE
    @assert(target.lpVtbl.DragEnter(target, source, 0, dropPt, &effect) == S_OK)
    @assert(effect == DROPEFFECT_NONE)

    // The whole path list survived the DROPFILES round trip.
    let payload = &host.surface.dropTarget.data
    @assert(payload.files.count == 2)
    @assert(payload.files[0] == "c:/tmp/first.png")
    @assert(payload.files[1] == "c:/tmp/second.png")
    @assert(payload.singleFile() == null)
    @assert(!payload.hasText())
    @assert(!payload.hasImage())

    // What the source published reaches the target unchanged, phase after phase.
    effect = DROPEFFECT_LINK
    @assert(target.lpVtbl.DragOver(target, MK_SHIFT, dropPt, &effect) == S_OK)
    @assert(host.surface.dropTarget.allowed == DropEffect.Link)

    effect = DROPEFFECT_COPY
    @assert(target.lpVtbl.Drop(target, source, 0, dropPt, &effect) == S_OK)
    @assert(effect == DROPEFFECT_NONE)

    // The gesture is over, so the payload is not kept alive past it.
    @assert(host.surface.dropTarget.data.files.count == 0)
}

// One path alone is what a field naming a document reads through `singleFile`.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()

    var data: HDropDataObject
    makeHDropObject(&data, ["c:/tmp/only.txt"])

    host.surface.registerDropTarget()
    let target = cast(*IDropTarget) &host.surface.dropTarget
    let source = cast(*IDataObject) &data

    var effect = DROPEFFECT_COPY
    discard target.lpVtbl.DragEnter(target, source, 0, POINTL{60, 60}, &effect)
    @assert(host.surface.dropTarget.data.singleFile() == "c:/tmp/only.txt")

    @assert(target.lpVtbl.DragLeave(target) == S_OK)
    @assert(host.surface.dropTarget.data.files.count == 0)
}

// The interface answers the identity questions COM asks of every object.
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
}
