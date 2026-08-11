using Serialization

const PreviewHeight = 256.0
const PreviewWidth  = PreviewHeight * (4 / 3.0)

enum MouseMode
{
    None
    Moving
    Creating
    Selecting
}

const TextFormSuperSample = 3

// The '.scapture' container: a magic word and a format version in front of the
// serialized capture. The version is what a future load dispatches its migrations on;
// a file without the header predates it and reads as version 0. The serialized layout
// itself is pinned by 'serialization.schema.test.swg'.
const CaptureFileMagic      = 0x53434150'u32
const CaptureFileVersion    = 2'u32
const CaptureProfileVersion = 3'u32

// Where the pixels of a capture came from. Stored with the capture so the library can
// distinguish a screen grab from a picture opened for annotation or a blank canvas.
enum CaptureSourceKind
{
    Unknown         // Capture saved before source metadata was recorded.
    Screen          // Pixels captured from the desktop or an application window.
    ImageFile       // Image file opened or dropped into sCapture.
    Clipboard       // Bitmap pasted or dragged without a source file.
    BlankCanvas     // Empty image created in sCapture.
}

// Small profile header read by the library without touching the editable document or pixels.
#[Serialization.Version(1)]
struct CaptureLibraryMetadata
{
    width, height:     s32
    linkedImage:       String
    linkedUpToDate:    bool = true
    sourceKind:        CaptureSourceKind
    capturedAt:        Time.DateTime
    sourceApplication: String
    sourceExecutable:  String
    sourceWindowTitle: String
    sourceWindowClass: String
    favorite:          bool
    rating:            u8
}

// Editable capture state stored independently from the large background images.
#[Serialization.Version(1)]
struct CaptureFileModel
{
    width, height:       s32
    widthOrg, heightOrg: s32
    backImagePos:        Math.Point
    forms:               Array'IForm
    nextStepIndex:       u32  = 1
    nextGroupId:         u64  = 1
    linkedImage:         String
    linkedUpToDate:      bool = true
    title:               String
    sourceKind:          CaptureSourceKind
    capturedAt:          Time.DateTime
    sourceApplication:   String
    sourceExecutable:    String
    sourceWindowTitle:   String
    sourceWindowClass:   String
    tags:                Array'String
    favorite:            bool
    rating:              u8
}

struct Capture
{
    const MinSize = 16
    const MaxSize = 4096
    width, height:       s32
    backImg:             Image
    widthOrg, heightOrg: s32
    backImgOriginal:     Image

    backImagePos:  Math.Point
    preview:       Image
    file:          String
    forms:         Array'IForm
    nextStepIndex: u32 = 1
    nextGroupId:   u64 = 1

    linkedImage:    String
    linkedUpToDate: bool = true

    // User-defined name shown in the library (empty = fall back to the file name).
    title: String

    // Library metadata. Window fields stay empty when the platform cannot identify a
    // window, or when the selected rectangle spans several applications.
    sourceKind:        CaptureSourceKind
    capturedAt:        Time.DateTime
    sourceApplication: String
    sourceExecutable:  String
    sourceWindowTitle: String
    sourceWindowClass: String
    tags:              Array'String
    favorite:          bool
    rating:            u8

    // Dyn
    #[NoSerialize]
    {
        // Anomalies the tolerant load had to swallow: reset fields, unknown types,
        // corrupt payloads. Nonzero means the file did not fully match the current
        // schema and a save would not preserve everything it held.
        loadIssues: u32

        changed:   bool
        mouseMode: MouseMode = None
        editView:  #null *EditView
        gizmo:     GizmoRect
        undoMgr:   UndoManager
        hotForm:   u64       = Swag.U64.Max
        selection: Array'u64
        paintRect: Math.Rectangle

        backTexture: Texture
        snapX:       f32 = -1
        snapY:       f32 = -1

        serialBackTexture: u32
        movingStart:       Math.Point
        movingEnd:         Math.Point
        lastSelectPos:     Math.Point
        lastSelectHit:     u64
        firstMouseMove:    bool
        dirtyBackImg:      bool
        drawSelRect:       bool
        prevSnapActive:    bool
        interactiveMove:   bool

        inPlaceEdit: bool
        inPlacePosX: f32
        inPlacePosY: f32

        haar: ImageStatistics.HaarFeatures
    }
}

// Visit the forms listed in 'selection' (an array of slots in capture.forms) that
// match T; 'BaseForm' matches every form. The injected block sees the typed form as
// 'form', its interface as 'itf', and a visit counter as 'idx'. 'continue' skips a
// form without advancing 'idx' — the exact contract needed to pair 'idx' with arrays
// built by a previous, identically-filtered pass — and 'break' stops the visit.
#[Swag.Macro]
func(T) foreachSelected(capture: *Capture, selection: Array'u64, stmt: #code(form: *T, itf: IForm, idx: u64))
{
    var visitIdx = 0'u64
    for s in selection
    {
        let f = capture.forms[s]
        #static if T != BaseForm
        {
            if @kindof(f) != T do
                continue
        }

        #inject(stmt, form = cast(*T) @dataof(f), itf = f, idx = visitIdx)
        visitIdx += 1
    }
}

enum CaptureClipboardFormKind
{
    None
    Arrow
    Draw
    Image
    Line
    Polygon
    Shape
    Step
    Text
    Callout
}

struct CaptureClipboardForm
{
    kind:    CaptureClipboardFormKind
    arrow:   FormArrow
    draw:    FormDraw
    image:   FormImage
    line:    FormLine
    polygon: FormPolygon
    shape:   FormShape
    step:    FormStep
    text:    FormText
    callout: FormCallout
}

struct CaptureClipboardForms
{
    forms: Array'CaptureClipboardForm
}

impl CaptureClipboardForm
{
    mtd add(itf: IForm)
    {
        switch itf
        {
        case FormArrow as form:
            .kind  = .Arrow
            .arrow = dref form

        case FormDraw as form:
            .kind = .Draw
            .draw = dref form

        case FormImage as form:
            .kind  = .Image
            .image = dref form

        case FormLine as form:
            .kind = .Line
            .line = dref form

        case FormPolygon as form:
            .kind    = .Polygon
            .polygon = dref form

        case FormShape as form:
            .kind  = .Shape
            .shape = dref form

        case FormStep as form:
            .kind = .Step
            .step = dref form

        case FormText as form:
            .kind = .Text
            .text = dref form

        case FormCallout as form:
            .kind    = .Callout
            .callout = dref form

        default:
            .kind = .None
        }
    }

    mtd toForm(capture: *Capture)->#null IForm
    {
        var result: retval

        switch .kind
        {
        case .Arrow:
            let form = Memory.new'FormArrow()
            dref form = .arrow
            result    = form

        case .Draw:
            let form = Memory.new'FormDraw()
            dref form = .draw
            result    = form

        case .Image:
            let form = Memory.new'FormImage()
            dref form = .image
            result    = form

        case .Line:
            let form = Memory.new'FormLine()
            dref form = .line
            result    = form

        case .Polygon:
            let form = Memory.new'FormPolygon()
            dref form = .polygon
            result    = form

        case .Shape:
            let form = Memory.new'FormShape()
            dref form = .shape
            result    = form

        case .Step:
            let form = Memory.new'FormStep()
            dref form = .step
            result    = form

        case .Text:
            let form = Memory.new'FormText()
            dref form = .text
            result    = form

        case .Callout:
            let form = Memory.new'FormCallout()
            dref form = .callout
            result    = form

        case .None:
            return result
        }

        let r = result!
        r.setup(capture)
        return result
    }
}

impl CaptureClipboardForms
{
    mtd add(itf: IForm)
    {
        var item: CaptureClipboardForm
        item.add(itf)
        if item.kind != .None do
            .forms.add(#move item)
    }

    mtd toForms(capture: *Capture)->Array'IForm
    {
        var result: retval
        for &item in .forms
        {
            let form = item.toForm(capture)
            if form do
                result.add(form)
        }

        return result
    }
}

impl Capture
{
    // Records the source of a screen capture. The native backend supplies as much window
    // identity as Windows allows; empty values deliberately mean "not available".
    mtd setScreenSource(application, executable, windowTitle, windowClass: String)
    {
        .sourceKind        = .Screen
        .capturedAt        = Time.DateTime.now()
        .sourceApplication = application
        .sourceExecutable  = executable
        .sourceWindowTitle = windowTitle
        .sourceWindowClass = windowClass
    }

    // Returns whether this capture owns `tag`, without making tag spelling case-sensitive.
    mtd const hasTag(tag: String)->bool
    {
        for own in .tags where Utf8.compare(own.toSlice(), tag, .Latin1NoCase) == 0 do
            return true
        return false
    }

    func freeForms(forms: Array'IForm)
    {
        for it in forms
        {
            let type = @kindof(it)
            Memory.delete(@dataof(it), type)
        }
    }

    mtd opDrop()
    {
        freeForms(.forms)
    }

    mtd setup(view: *EditView)
    {
        .editView         = view
        .gizmo.sigChanged = func|capture = me|(g, first, hitMove)
        {
            let editView = capture.editView!
            var undo     = capture.newUndo(.MoveCapture)
            undo.newPosX  = cast(s32) ((g.rect.x - g.movingRect.x) / editView.zoom)
            undo.newPosY  = cast(s32) ((g.rect.y - g.movingRect.y) / editView.zoom)
            undo.newSizeX = cast(s32) ((g.movingRect.width - g.rect.width) / editView.zoom)
            undo.newSizeY = cast(s32) ((g.movingRect.height - g.rect.height) / editView.zoom)
            capture.pushUndo(undo)
            editView.invalidate()
        }
    }

    //////////////////////////////
    // IMAGE
    //////////////////////////////

    mtd computePreview()
    {
        if !.editView do
            return
        let zoom = Math.min(PreviewWidth / .width, PreviewHeight / .height)
        .preview = .toImage(zoom)
        .preview.applyKernel(.GaussianBlur3x3Light)
        .changed = true
    }

    mtd toImage(zoom: f32 = 1, onlySel = false)->Image
    {
        var result: retval

        let rect    = Math.Rectangle{width: .width * zoom, height: .height * zoom}
        let render  = g_App.renderer
        var painter = Pixel.Painter.create(render)
        let srf     = (.editView!.surface)!
        render.begin(srf.renderingContext())
        painter.begin()

        var layer: Layer
        layer.begin(&painter, {width: cast(s32) rect.width, height: cast(s32) rect.height, paintAlpha: false, clearColor: Color.fromArgb(Argb.White)})

        .paintBackImage(&painter, 0, 0, zoom)
        with painter
        {
            .setColorMaskColor()
            .setParams(.Antialiased)
        }

        if onlySel
        {
            for sel in .selection
            {
                let f = .forms[sel]
                let b = cast(*BaseForm) @dataof(f)
                if b.subKind == .PixSel do
                    continue
                paintForm(&painter, {}, rect, f, zoom, snapMode: true)
            }
        }
        else
        {
            for f in .forms
            {
                let b = cast(*BaseForm) @dataof(f)
                if b.subKind == .PixSel do
                    continue
                paintForm(&painter, {}, rect, f, zoom, snapMode: true)
            }
        }

        layer.end()
        painter.end()

        render.draw(&painter)
        render.end()

        let rt     = layer.contentTarget!
        var buffer = render.readTexturePixels(rt.colorBuffer, .BGRA8)
        result = Image.create(rt.colorBuffer.width, rt.colorBuffer.height, .BGRA8, buffer.toSlice())
        result.crop(0, 0, cast(s32) rect.width, cast(s32) rect.height)
        render.releaseRenderTarget(rt)

        return result
    }

    //////////////////////////////
    // FILE
    //////////////////////////////

    mtd hasChanged()
    {
        .changed        = true
        .linkedUpToDate = false

        // During an interactive form drag this runs twice per mouse move (undo() +
        // pushUndo()). The full-view invalidate here would repaint every form and the
        // recent-thumbnail strip each frame, defeating the per-form partial invalidate
        // done by GizmoRect.apply. Skip the heavy refresh while dragging; it is done
        // once when the drag ends (see Capture.mouse / endInteractiveMove).
        if .interactiveMove do
            return

        let editView = .editView
        if !editView do
            return
        editView.invalidate()
        editView.main.captureHasChanged()
        editView.main.updateRecent()
    }

    // Called once when an interactive form move/resize ends, to refresh the toolbar
    // state / recent strip / full view that hasChanged() skipped during the drag.
    mtd endInteractiveMove()
    {
        if !.interactiveMove do
            return
        .interactiveMove = false
        .hasChanged()
    }

    private func sccId(text: string)->Guid128
    {
        var result: Guid128
        let valid = Guid128.tryParse(text, &result)
        Debug.assert(valid)
        return result
    }

    private func containerKind()->Guid128 => sccId("7355af24-cf65-447b-918c-18ac74e6dc66")
    private func tagBinType()->Guid128 => sccId("cbb8ce58-7baa-4381-aa22-3b95365a8ba2")
    private func pngType()->Guid128 => sccId("7de5d04e-37f9-4143-81ac-e7bc6f694b38")
    private func modelRole()->Guid128 => sccId("e4848e3e-60f5-405f-adad-f109e897a351")
    private func previewRole()->Guid128 => sccId("f53e06c1-05a7-4537-9c6a-d85609209874")
    private func backgroundRole()->Guid128 => sccId("04267f4e-d659-4d32-9296-cc68be5bdb9d")
    private func originalRole()->Guid128 => sccId("11d1a796-38d8-46ca-a4e6-5e2271ebd321")

    private func(T) encodeValue(value: const *T)->Array'u8 fail
    {
        var output:  ConcatBuffer
        var encoder: Encoder'Write.TagBin
        encoder.writeAll(&output, dref value)
        output.makeLinear()

        var result: retval
        result.add(output.toSlice()!)
        return result
    }

    private mtd libraryMetadata()->CaptureLibraryMetadata
    {
        var result: retval
        result.width             = .width
        result.height            = .height
        result.linkedImage       = .linkedImage
        result.linkedUpToDate    = .linkedUpToDate
        result.sourceKind        = .sourceKind
        result.capturedAt        = .capturedAt
        result.sourceApplication = .sourceApplication
        result.sourceExecutable  = .sourceExecutable
        result.sourceWindowTitle = .sourceWindowTitle
        result.sourceWindowClass = .sourceWindowClass
        result.favorite          = .favorite
        result.rating            = .rating
        return result
    }

    private mtd fileModel()->CaptureFileModel
    {
        var result: retval
        result.width             = .width
        result.height            = .height
        result.widthOrg          = .widthOrg
        result.heightOrg         = .heightOrg
        result.backImagePos      = .backImagePos
        result.forms             = .forms
        result.nextStepIndex     = .nextStepIndex
        result.nextGroupId       = .nextGroupId
        result.linkedImage       = .linkedImage
        result.linkedUpToDate    = .linkedUpToDate
        result.title             = .title
        result.sourceKind        = .sourceKind
        result.capturedAt        = .capturedAt
        result.sourceApplication = .sourceApplication
        result.sourceExecutable  = .sourceExecutable
        result.sourceWindowTitle = .sourceWindowTitle
        result.sourceWindowClass = .sourceWindowClass
        result.tags              = .tags
        result.favorite          = .favorite
        result.rating            = .rating
        return result
    }

    private func fromLibraryMetadata(metadata: CaptureLibraryMetadata, manifest: const *Scc.Manifest)->*Capture
    {
        let result = Memory.new'Capture()
        result.width             = metadata.width
        result.height            = metadata.height
        result.linkedImage       = metadata.linkedImage
        result.linkedUpToDate    = metadata.linkedUpToDate
        result.title             = manifest.name
        result.sourceKind        = metadata.sourceKind
        result.capturedAt        = metadata.capturedAt
        result.sourceApplication = metadata.sourceApplication
        result.sourceExecutable  = metadata.sourceExecutable
        result.sourceWindowTitle = metadata.sourceWindowTitle
        result.sourceWindowClass = metadata.sourceWindowClass
        result.tags              = manifest.tags
        result.favorite          = metadata.favorite
        result.rating            = metadata.rating
        return result
    }

    private func fromFileModel(model: *CaptureFileModel)->*Capture
    {
        let result = Memory.new'Capture()
        result.width             = model.width
        result.height            = model.height
        result.widthOrg          = model.widthOrg
        result.heightOrg         = model.heightOrg
        result.backImagePos      = model.backImagePos
        result.forms             = #move model.forms
        result.nextStepIndex     = model.nextStepIndex
        result.nextGroupId       = model.nextGroupId
        result.linkedImage       = #move model.linkedImage
        result.linkedUpToDate    = model.linkedUpToDate
        result.title             = #move model.title
        result.sourceKind        = model.sourceKind
        result.capturedAt        = model.capturedAt
        result.sourceApplication = #move model.sourceApplication
        result.sourceExecutable  = #move model.sourceExecutable
        result.sourceWindowTitle = #move model.sourceWindowTitle
        result.sourceWindowClass = #move model.sourceWindowClass
        result.tags              = #move model.tags
        result.favorite          = model.favorite
        result.rating            = model.rating
        return result
    }

    mtd save() fail
    {
        if !.changed do
            return

        var metadata = .libraryMetadata()
        var model    = .fileModel()
        var manifest: Scc.Manifest
        manifest.profileVersion = CaptureProfileVersion
        manifest.name           = .title
        manifest.createdAt      = .capturedAt
        manifest.modifiedAt     = Time.DateTime.now()
        manifest.tags           = .tags
        manifest.profileData    = try encodeValue(&metadata)

        var writer: Scc.Writer
        writer.initialize(containerKind())
        dref writer.manifest() = #move manifest
        let typeTagBin     = tagBinType()
        let typePng        = pngType()
        let roleModel      = modelRole()
        let roleBackground = backgroundRole()
        let roleOriginal   = originalRole()
        let rolePreview    = previewRole()
        let codecDeflate   = Scc.deflateCodecId()
        var modelBytes     = try encodeValue(&model)
        let modelId        = try writer.addChunk(modelBytes.toSlice(), {typeId: typeTagBin, roleId: roleModel, codecId: codecDeflate, flags: .Required | .Metadata})

        var variants: Array'Guid128
        if .backImg.isValid()
        {
            var bytes = try encodeValue(&.backImg)
            variants.add(try writer.addChunk(bytes.toSlice(), {typeId: typeTagBin, roleId: roleBackground, codecId: codecDeflate, flags: .Required}))
        }

        if .backImgOriginal.isValid()
        {
            var bytes = try encodeValue(&.backImgOriginal)
            variants.add(try writer.addChunk(bytes.toSlice(), {typeId: typeTagBin, roleId: roleOriginal, codecId: codecDeflate}))
        }

        if .preview.isValid()
        {
            var bytes = try .preview.encodeToBytes("preview.png")
            variants.add(try writer.addChunk(bytes.toSlice(), {typeId: typePng, roleId: rolePreview, flags: .Streamable}))
        }

        var entry: Scc.Entry
        entry.id            = Guid128.random()
        entry.kind          = .File
        entry.name          = String.from(Path.fileName(.file) orelse "")
        entry.tags          = .tags
        entry.primaryChunk  = modelId
        entry.variantChunks = #move variants
        writer.manifest().entries.add(#move entry)
        writer.saveAtomic(.file)
        .changed = false
    }

    private func loadScc(file: String, preview: bool)->*Capture fail
    {
        var reader: Scc.Reader
        reader.initialize(file)
        if reader.kind() != containerKind() do
            fail Core.Errors.InvalidFormatError{"capture file has a different SCC profile"}
        if reader.manifest().profileVersion > CaptureProfileVersion do
            fail Core.Errors.InvalidVersion{wantedVersion: CaptureProfileVersion, foundVersion: reader.manifest().profileVersion}

        var capture: *Capture = undefined
        if preview
        {
            var decoder: Decoder'Read.TagBin
            let metadata = decoder.readAll'CaptureLibraryMetadata(reader.manifest().profileData.toSlice())!
            defer Memory.delete(metadata)
            capture = fromLibraryMetadata(dref metadata, reader.manifest())
        }
        else
        {
            let info = reader.findRole(modelRole())
            if !info do
                fail Core.Errors.InvalidFormatError{"capture SCC has no document model chunk"}
            var bytes = try reader.readChunk(info.id)
            var decoder: Decoder'Read.TagBin
            decoder.flags |= .IgnoreStructFieldError
            let model = decoder.readAll'CaptureFileModel(bytes.toSlice())!
            defer Memory.delete(model)
            capture = fromFileModel(model)

            let diag = decoder.serializer.diag
            capture.loadIssues = diag.fieldErrors + diag.unknownTypes + diag.corruptPayloads

            let background = reader.findRole(backgroundRole())
            if background
            {
                var imageBytes = try reader.readChunk(background.id)
                var imageDecoder: Decoder'Read.TagBin
                let image      = imageDecoder.readAll'Image(imageBytes.toSlice())!
                capture.backImg = #move dref image
                Memory.delete(image)
            }

            let original = reader.findRole(originalRole())
            if original
            {
                var imageBytes = try reader.readChunk(original.id)
                var imageDecoder: Decoder'Read.TagBin
                let image      = imageDecoder.readAll'Image(imageBytes.toSlice())!
                capture.backImgOriginal = #move dref image
                Memory.delete(image)
            }
        }

        let previewInfo = reader.findRole(previewRole())
        if previewInfo
        {
            var imageBytes = try reader.readChunk(previewInfo.id)
            capture.preview = try Image.decode("preview.png", imageBytes.toSlice())
        }

        capture.file = file
        for itf in capture.forms do
            itf.setup(capture)
        reader.close()
        return capture
    }

    private func loadLegacy(file: String, preview: bool)->*Capture fail
    {
        var res = File.readAllBytes(file)

        // Strip the container header when it is there; a headerless file predates it.
        var payload: const [..] u8 = res.toSlice()
        var version                = 0'u32
        if @countof(payload) >= 8
        {
            var header = ByteStream.openRead(payload)
            let magic  = catch header.readNative'u32()
            if magic == CaptureFileMagic
            {
                version = catch header.readNative'u32()
                payload = header.remainingBytes()
            }
        }

        if version > CaptureFileVersion do
            fail Core.Errors.InvalidVersion{wantedVersion: CaptureFileVersion, foundVersion: version}

        var decoder: Decoder'Read.TagBin
        decoder.flags |= .IgnoreStructFieldError
        if preview
        {
            decoder.serializer.ignoreElements.add(#nameof(Capture.backImg))
            decoder.serializer.ignoreElements.add(#nameof(Capture.backImgOriginal))
        }

        let capture = decoder.readAll'Capture(payload)!
        capture.file = file
        let diag = decoder.serializer.diag
        capture.loadIssues = diag.fieldErrors + diag.unknownTypes + diag.corruptPayloads
        for itf in capture.forms do
            itf.setup(capture)
        return capture
    }

    func load(file: String, preview = false)->#null *Capture fail
    {
        if try Scc.hasSignature(file) do
            return try loadScc(file, preview)
        return try loadLegacy(file, preview)
    }

    //////////////////////////////
    // CLIPBOARD
    //////////////////////////////

    mtd copyAll()
    {
        Cursor.activateWait()
        Clipboard.addImage(.toImage())
    }

    mtd copy()
    {
        var payload: CaptureClipboardForms

        var imgDone = false
        for s in .selection
        {
            let itf = .forms[s]

            // Add real image
            if !imgDone and @kindof(itf) == FormImage
            {
                let fimg = cast(*FormImage) @dataof(itf)
                if fimg.kind == .Image and fimg.image.isValid()
                {
                    imgDone = true
                    Clipboard.addImage(fimg.image)
                }
            }

            payload.add(itf)
        }

        Clipboard.addTypedValue(&payload, #typeof(payload))
    }

    mtd cut()
    {
        .copy()
        .pushUndo(.newUndo(.DeleteSelection))
    }

    mtd pasteImageInside()
    {
        let img = Clipboard.getImage()
        if !img.isValid() do
            return

        let undo = .newUndo(.SetImageInside)
        undo.newImg = img
        .pushUndo(undo)
        .selectionHasChanged()
    }

    mtd clearImageInside()
    {
        let undo = .newUndo(.SetImageInside)
        .pushUndo(undo)
        .selectionHasChanged()
    }

    mtd paste()
    {
        var res:     Array'IForm
        var payload: CaptureClipboardForms
        if Clipboard.getTypedValue(&payload, #typeof(payload))
        {
            res = payload.toForms(me)
        }
        else
        {
            let img = Clipboard.getImage()
            if img.isValid()
            {
                let formImg = Memory.new'FormImage()
                formImg.w             = img.width
                formImg.h             = img.height
                formImg.image         = img
                formImg.borderColor.a = 0
                formImg.backColor.a   = 0
                res.add(formImg)
            }
            else do
                return
        }

        // Pasted copies keep their internal grouping but must not re-join the originals
        // (or collide with groups from another capture file), so mint fresh ids.
        .remapGroups(res)

        let undo = .newUndo(.CreateForm)
        .selection.clear()

        var boundRect: Math.Rectangle

        for itf, idx in res
        {
            itf.setup(me)
            let bound = itf.boundRect()
            if idx == 0 do
                boundRect = bound
            else do
                boundRect.combine(bound)
        }

        undo.oldForms = res

        // Move around mouse
        let editView = .editView!
        var pt       = editView.app().mouse.position()
        pt   = editView.screenToSurface(pt)
        pt   = editView.surfaceToLocal(pt)
        pt   += editView.scrollPos
        pt.x -= .paintRect.x
        pt.y -= .paintRect.y
        let zoom = .paintRect.width / .width
        pt.x /= zoom
        pt.y /= zoom

        for itf in undo.oldForms
        {
            let dx = -boundRect.x + pt.x - (boundRect.width * 0.5)
            let dy = -boundRect.y + pt.y - (boundRect.height * 0.5)
            itf.moveForm(cast() dx, cast() dy)
        }

        let countBefore = .forms.count
        .pushUndo(undo)

        // Select added forms
        .selection.clear()
        for i in @countof(undo.oldForms) do
            .selection.add(countBefore + i)

        .selectionHasChanged()
    }

    //////////////////////////////
    // PAINT
    //////////////////////////////

    func paintForm(painter: *Painter, clip, rect: Math.Rectangle, f: IForm, zoom: f32, quickMode = false, snapMode = false)
    {
        var boundRect = f.boundRect()
        boundRect.width  = Math.max(boundRect.width, 1)
        boundRect.height = Math.max(boundRect.height, 1)
        boundRect.inflate(FormPaintOverdraw)

        var clipOffset:    Math.Vector2
        var savePaintPos:  Math.Rectangle
        var saveNoClipPos: Math.Rectangle
        var wt2, ht2:      s32
        with let base = cast(*BaseForm) @dataof(f)
        {
            savePaintPos = .paintPos

            .paintPos.x      = rect.x + (boundRect.x * zoom)
            .paintPos.y      = rect.y + (boundRect.y * zoom)
            .paintPos.width  = boundRect.width * zoom
            .paintPos.height = boundRect.height * zoom

            saveNoClipPos = .paintPos

            if !quickMode and !clip.isEmpty()
            {
                if .paintPos.x >= clip.right() do
                    return
                if .paintPos.y >= clip.bottom() do
                    return
                if .paintPos.x < clip.x do
                    clipOffset.x = clip.x - .paintPos.x
                if .paintPos.y < clip.y do
                    clipOffset.y = clip.y - .paintPos.y
                if .paintPos.right() > clip.right() do
                    .paintPos.setRight(clip.right())
                if .paintPos.bottom() > clip.bottom() do
                    .paintPos.setBottom(clip.bottom())
            }

            .paintPos.width  += .paintPos.x - Math.round(.paintPos.x)
            .paintPos.height += .paintPos.y - Math.round(.paintPos.y)
            .paintPos.round()

            wt2 = cast(s32) (.paintPos.width - clipOffset.x)
            ht2 = cast(s32) (.paintPos.height - clipOffset.y)
        }

        let textSuperSample = (!quickMode and @kindof(f) == FormText) ? TextFormSuperSample : 1
        var layer: Layer
        layer.begin(painter, {width: wt2, height: ht2, renderScale: textSuperSample})

        with painter
        {
            .pushTransform()
            .translateTransform(((-boundRect.x * zoom) - clipOffset.x) * textSuperSample, ((-boundRect.y * zoom) - clipOffset.y) * textSuperSample)
            var cxt: FormPaintContext
            cxt.z           = zoom
            cxt.renderScale = cast() textSuperSample
            cxt.quickMode   = quickMode
            f.paint(painter, cxt)
            .popTransform()
        }

        layer.end()

        var colForm: Color
        if quickMode and base.subKind == .Highlight do
            colForm = Argb.White
        elif quickMode and base.subKind == .PixSel do
            colForm = Argb.White
        else do
            colForm = Color.fromArgb(cast(u8) Math.map(cast(f32) base.alpha, 0, 100, 0, 255), Argb.White)

        var paintRect: Math.Rectangle
        paintRect.x      = base.paintPos.x + clipOffset.x
        paintRect.y      = base.paintPos.y + clipOffset.y
        paintRect.width  = wt2
        paintRect.height = ht2

        // Rotation
        painter.pushTransform()

        if base.subKind != .Highlight and base.subKind != .PixSel and !quickMode and !Math.isZeroEpsilon(base.rotate)
        {
            painter.translateTransform(saveNoClipPos.horzCenter(), saveNoClipPos.vertCenter())
            paintRect.offset(-saveNoClipPos.horzCenter(), -saveNoClipPos.vertCenter())

            let angle = Math.map(base.rotate, -180, 180, -Math.ConstF32.Pi, Math.ConstF32.Pi)
            painter.rotateTransformInPlace(angle)
        }

        defer painter.popTransform()

        var drawInfo: LayerDrawInfo
        drawInfo.dstRect           = paintRect
        drawInfo.color             = colForm
        drawInfo.interpolationMode = base.paintShadow ? .Linear : .Pixel
        drawInfo.shadow.enabled    = base.paintShadow
        drawInfo.shadow.radius     = quickMode ? 4.0 : 8.0
        drawInfo.shadow.offsetX    = base.shadowOffsetX
        drawInfo.shadow.offsetY    = base.shadowOffsetY
        layer.draw(drawInfo)

        with painter
        {
            .setColorMaskColor()
            .setBlendingMode(.Alpha)
            .setInterpolationMode(.Linear)
            .setAntialiased(true)
        }

        if snapMode do
            base.paintPos = savePaintPos
    }

    mtd paintBackImage(painter: *Painter, x, y: f32, z: f32)
    {
        let editView = .editView!
        let renderer = editView.app().renderer

        // Background image
        if !.backTexture.isValid() and .backImg.width > 0
        {
            .backTexture       = renderer.addImage(.backImg)
            .serialBackTexture += 1
        }

        if .backTexture.isValid()
        {
            // Background image has been changed
            if .dirtyBackImg
            {
                renderer.removeTexture(&.backTexture)
                .backTexture       = renderer.addImage(.backImg)
                .dirtyBackImg      = false
                .serialBackTexture += 1
            }

            var backRect: Math.Rectangle
            if .inPlaceEdit
            {
                backRect.x      = 0
                backRect.y      = 0
                backRect.width  = editView.position.width
                backRect.height = editView.position.height
            }
            else
            {
                backRect.x      = (.backImagePos.x * z) + x
                backRect.y      = (.backImagePos.y * z) + y
                backRect.width  = .backImg.width * z
                backRect.height = .backImg.height * z
            }

            painter.setInterpolationMode(.Linear)
            painter.drawTexture(backRect, .backTexture)
        }
    }

    // Invalidate only the region a just-moved/resized form occupied before ('oldRect',
    // in capture coordinates) and now occupies, so a single-form drag re-renders just
    // that form rather than every form. Falls back to a full repaint while snap guides
    // are (or just were) visible, since those lines span the whole capture.
    mtd invalidateAfterMove(iform: IForm, oldRect: Math.Rectangle)
    {
        let view = .editView
        if !view do
            return

        let snapNow = .snapX != -1 or .snapY != -1
        defer me.prevSnapActive = snapNow
        if snapNow or .prevSnapActive
        {
            view.invalidate()
            return
        }

        let nb   = iform.boundRect()
        let minx = Math.min(oldRect.x, nb.x)
        let miny = Math.min(oldRect.y, nb.y)
        let maxx = Math.max(oldRect.right(), nb.right())
        let maxy = Math.max(oldRect.bottom(), nb.bottom())

        // Union of old + new bound, padded for the drop shadow / stroke extent.
        var r = Math.Rectangle{minx, miny, maxx - minx, maxy - miny}
        r.inflate(48)

        // To view-local pixels, then pad for the gizmo handles / rotation knob.
        var local = r * view.zoom
        local.offset(.paintRect.x, .paintRect.y)
        local.inflate(56, 56)
        view.invalidateRect(local)
    }

    mtd paint(painter: *Painter, clip, rect: Math.Rectangle)
    {
        painter.fillRect(rect, Argb.LightGray)
        painter.fillRect(rect, Brush.createHatch(.CheckBoardLarge, Argb.DarkGray))
        painter.setParams(.Antialiased)

        .paintRect = rect
        let zoom = rect.width / .width

        // Cull forms against the real invalidated region, not just the full view clip.
        // When a single form is dragged we only invalidate its rectangle (see
        // GizmoRect.apply), so the surface clips the painter to that region; testing
        // each form against it lets the static forms be skipped entirely instead of
        // re-rendering all of them (with their supersampled layers + shadow blur) every
        // frame. On a full repaint the painter clip is the whole view, so nothing changes.
        var cullClip = clip
        if painter.hasClippingRect()
        {
            var pc        = painter.clippingRect()
            let transform = painter.transform()
            pc.offset(-transform.tx, -transform.ty)
            cullClip.intersect(pc)
        }

        // Background image
        painter.setAntialiased(false)
        .paintBackImage(painter, rect.x, rect.y, zoom)

        // Shapes
        for f in .forms
        {
            // Cull against the form's actual painted extent. 'paintForm' inflates the
            // bound by 200 (the rendered geometry - arrow caps, thick strokes, shadow -
            // can reach well beyond the tight 'boundRect') and draws it offset by 'rect'.
            // Testing the raw, un-offset bound wrongly hid forms whose tight bound fell
            // just outside the clip (e.g. a thin arrow).
            var cull = f.boundRect()
            cull.width  = Math.max(cull.width, 1)
            cull.height = Math.max(cull.height, 1)
            cull.inflate(FormPaintOverdraw)
            cull = cull * zoom
            cull.offset(rect.x, rect.y)
            if !cull.intersects(cullClip) do
                continue

            if f.mustClipToBound()
            {
                var pp = f.boundRect() * zoom
                pp.offset(rect.x, rect.y)
                painter.pushClippingRect(pp)
                paintForm(painter, clip, rect, f, zoom)
                painter.popClippingRect()
            }
            else
            {
                paintForm(painter, clip, rect, f, zoom)
            }
        }

        // Gizmos
        for f, i in .forms
        {
            var flags = FormFlags.Zero
            if i == .hotForm do
                flags.add(.Hot)
            if .selection.contains(i) do
                flags.add(.Selected)

            painter.pushTransform()
            painter.translateTransform(rect.x, rect.y)
            f.paintGizmo(painter, zoom, flags)
            painter.popTransform()
        }

        // Group outline: a dashed, embossed box around each selected group communicates
        // that its forms move as one unit (the individual member gizmos still show).
        if .selection.count
        {
            var ids: Array'u64
            for s in .selection
            {
                let g = formOuterGroup(.forms[s])
                if g != 0 and !ids.contains(g) do
                    ids.add(g)
            }

            for gid in ids
            {
                var bound = Math.Rectangle{Swag.F32.Max, Swag.F32.Max, 0, 0}
                for f in .forms
                {
                    if formOuterGroup(f) != gid do
                        continue
                    let br = f.boundRect()
                    bound.x = Math.min(bound.x, br.x)
                    bound.y = Math.min(bound.y, br.y)
                    bound.setRight(Math.max(bound.right(), br.right()))
                    bound.setBottom(Math.max(bound.bottom(), br.bottom()))
                }

                var vr = bound * zoom
                vr.offset(rect.x, rect.y)
                vr.inflate(6)
                painter.drawRect(vr, Pen.createDash(.Dash, Argb.DarkGray, 3))
                painter.drawRect(vr, Pen.createDash(.Dash, Argb.White, 1))
            }
        }

        // Selection rectangle
        if .drawSelRect
        {
            with var r: Math.Rectangle
            {
                .x      = me.movingStart.x
                .y      = me.movingStart.y
                .width  = me.movingEnd.x - me.movingStart.x
                .height = me.movingEnd.y - me.movingStart.y
            }

            r.offset(.paintRect.x, .paintRect.y)
            painter.fillRect(r, Color.fromArgb(0x1F, Argb.Cyan))
            painter.drawRect(r, Argb.Cyan, 2)
        }

        // Snap
        if .snapX != -1 do
            painter.drawLine(rect.x + .snapX * zoom, rect.y, rect.x + .snapX * zoom, rect.bottom(), Argb.Purple, 2)
        if .snapY != -1 do
            painter.drawLine(rect.x, rect.y + .snapY * zoom, rect.right(), rect.y + .snapY * zoom, Argb.Purple, 2)
    }

    //////////////////////////////
    // SNAP
    //////////////////////////////

    mtd getSnapPoint(bound: Math.Rectangle, right, bottom: bool, nx, ny: s32, idxPt: u32, editForm: #null IForm = null)->Math.Point
    {
        var result: retval

        let form = editForm orelse .forms[.selection[0]]
        let type = @kindof(form)

        if .selection.count == 1 and type == FormPolygon
        {
            let poly = cast(*FormPolygon) @dataof(form)
            result.x = poly.points[idxPt].x + nx
            result.y = poly.points[idxPt].y + ny
        }
        elif (.selection.count == 1 or editForm) and (type == FormLine or type == FormArrow)
        {
            let line = cast(*FormLine) @dataof(form)
            if !right or !bottom
            {
                result.x = line.xa
                result.y = line.ya
            }
            else
            {
                result.x = line.xb
                result.y = line.yb
            }

            result.x += nx
            result.y += ny
        }
        else
        {
            result.x = right ? bound.right() : bound.x
            result.y = bottom ? bound.bottom() : bound.y
            result.x += nx
            result.y += ny
        }

        return result
    }

    mtd getSelectionBoundRect(editForm: #null IForm = null)->Math.Rectangle
    {
        if editForm do
            return editForm.boundRect()

        var bound = Math.Rectangle{Swag.F32.Max, Swag.F32.Max, 0, 0}
        foreachSelected'BaseForm(me, .selection)
        {
            let r = itf.boundRect()
            bound.x = Math.min(bound.x, r.x)
            bound.y = Math.min(bound.y, r.y)
            bound.setRight(Math.max(bound.right(), r.right()))
            bound.setBottom(Math.max(bound.bottom(), r.bottom()))
        }

        return bound
    }

    mtd snap(x, y: #null *s32, right, bottom: bool, idxPt: u32 = 0, editForm: #null IForm = null)
    {
        const SnapToler = 10

        if x do
            .snapX = -1
        if y do
            .snapY = -1

        let editView    = .editView!
        let keyboard    = &editView.app().keyboard
        let ctrlPressed = keyboard.isKeyPressed(.Control) or keyboard.isKeyPressed(.RControl) or keyboard.isKeyPressed(.LControl)
        if !editView.main.snap and !ctrlPressed do
            return

        var nx = x ? dref x : 0
        var ny = y ? dref y : 0

        let bound = .getSelectionBoundRect(editForm)

        var arrX: Array's32
        var arrY: Array's32

        arrX.add(0)
        arrX.add(.width)
        arrX.add(.width / 2)
        arrY.add(0)
        arrY.add(.height)
        arrY.add(.height / 2)

        for f, i in .forms
        {
            let autoSel = .selection.contains(i) or @dataof(f) == @dataof(editForm)
            let form    = cast(*BaseForm) @dataof(f)

            switch f
            {
            case FormLine, FormArrow:
                let form2 = cast(*FormLine) form
                if !autoSel or (idxPt != 0 and Math.abs(form2.ya - form2.yb) > 25) do
                    arrX.add(cast(s32) form2.xa)
                if !autoSel or (idxPt != 0 and Math.abs(form2.xa - form2.xb) > 25) do
                    arrY.add(cast(s32) form2.ya)

                if !autoSel or idxPt != 1
                {
                    arrX.add(cast(s32) form2.xb)
                    arrY.add(cast(s32) form2.yb)
                }

            case FormPolygon:
                let form2 = cast(*FormPolygon) form
                for pt, idx in form2.points
                {
                    if !autoSel or idx != idxPt
                    {
                        arrX.add(cast(s32) pt.x)
                        arrY.add(cast(s32) pt.y)
                    }
                }

            case FormDraw:
                if autoSel do
                    continue
                let boundR = f.boundRect()
                arrX.add(cast(s32) boundR.x)
                arrX.add(cast(s32) boundR.right())
                arrY.add(cast(s32) boundR.y)
                arrY.add(cast(s32) boundR.bottom())

            default:
                if autoSel do
                    continue
                arrX.add(cast(s32) form.x)
                arrX.add(cast(s32) (form.x + form.w))
                arrY.add(cast(s32) form.y)
                arrY.add(cast(s32) (form.y + form.h))
            }
        }

        var bestX      = Swag.F32.Max
        var bestY      = Swag.F32.Max
        var bestCoordX = 0.0
        var bestCoordY = 0.0

        let pMoved = .getSnapPoint(bound, right, bottom, nx, ny, idxPt, editForm)

        if x
        {
            for ax in arrX
            {
                let nbX = Math.abs(pMoved.x - ax)
                if nbX < bestX
                {
                    bestX      = nbX
                    bestCoordX = ax
                }
            }
        }

        if y
        {
            for ay in arrY
            {
                let nbY = Math.abs(pMoved.y - ay)
                if nbY < bestY
                {
                    bestY      = nbY
                    bestCoordY = ay
                }
            }
        }

        let pOrg = .getSnapPoint(bound, right, bottom, 0, 0, idxPt, editForm)

        if x and bestX < SnapToler
        {
            .snapX = bestCoordX
            nx     = cast(s32) (bestCoordX - pOrg.x)
        }

        if y and bestY < SnapToler
        {
            .snapY = bestCoordY
            ny     = cast(s32) (bestCoordY - pOrg.y)
        }

        if x do
            dref x = nx
        if y do
            dref y = ny
    }

    //////////////////////////////
    // CONTENT
    //////////////////////////////

    mtd popupMenu(view: *EditView, pos: Math.Point)
    {
        with let menu = MenuCtrl.createPopup(view)
        {
            // Actions specific to the current selection. They all hide themselves
            // when they don't apply, and the trailing separator collapses when none
            // of them is visible.
            .addItem(ActionEdit.EditText)
            .addItem(ActionCopyPaste.PasteImageInside)
            .addItem(ActionEdit.ClearImageInside)
            .addSeparator()

            .addItem(ActionCopyPaste.Copy)
            .addItem(ActionCopyPaste.Cut)
            .addItem(ActionCopyPaste.Paste)
            .addSeparator()
            .addItem(ActionCopyPaste.CopyAsImage)
            .addSeparator()
            .addItem(ActionSelection.DeleteSelection)
            .addSeparator()
        }

        with let popup0 = MenuCtrl.createPopup(view)
        {
            .addItem(ActionAlign.AlignLeft)
            .addItem(ActionAlign.AlignCenter)
            .addItem(ActionAlign.AlignRight)
            .addSeparator()
            .addItem(ActionAlign.AlignTop)
            .addItem(ActionAlign.AlignMiddle)
            .addItem(ActionAlign.AlignBottom)
            menu.addPopup(appStrings().ui_MenuAlign, popup0)
        }

        with let popup1 = MenuCtrl.createPopup(view)
        {
            .addItem(ActionAlign.SendToFront)
            .addItem(ActionAlign.SendToBack)
            .addItem(ActionAlign.MoveForward)
            .addItem(ActionAlign.MoveBackward)
            menu.addPopup(appStrings().ui_MenuArrange, popup1)
        }

        with menu
        {
            .addItem(ActionGroup.Group)
            .addItem(ActionGroup.Ungroup)
            .addSeparator()
            .addItem(ActionEdit.ResetRotation)
            .addSeparator()
            .addItem(ActionSelection.SelectAll)
            .addItem(ActionSelection.SelectSameAll)
            .addItem(ActionSelection.DeSelectAll)
            .addSeparator()
            .addItem(ActionFlatten.Flatten)
            .addItem(ActionFlatten.FlattenAll)
            .addSeparator()
            .addItem(ActionSelection.Snap)
        }

        discard menu.doModal(pos)
        view.setFocus()
    }

    mtd mouse(view: *EditView, evt: *MouseEvent)->bool
    {
        let app = view.app()

        // When a form drag/resize ends, commit the GUI refresh that hasChanged()
        // deferred during the interactive move (runs on every exit of this handler).
        defer
        {
            if evt.kind == .Released do
                me.endInteractiveMove()
        }

        var localPos = view.surfaceToLocal(evt.surfacePos)
        localPos   += view.scrollPos
        localPos.x -= .paintRect.x
        localPos.y -= .paintRect.y

        if .mouseMode == .None
        {
            // Resize capture
            .snapX, .snapY = -1
            if .gizmo.mouse(view, localPos, evt)
            {
                view.invalidate()
                evt.accepted = true
                if evt.kind != .Leave do
                    return true
            }

            // Specific moves only if one single selection
            if .selection.count == 1
            {
                let selForm = .forms[.selection[0]]
                let p       = cast(*BaseForm) @dataof(selForm)
                if !view.main.freezeSel or !p.freeze
                {
                    if selForm.mouse(view, localPos, evt)
                    {
                        evt.accepted = true
                        if evt.kind != .Leave do
                            return true
                    }
                }
            }

            // Popup
            if evt.kind == .Pressed and evt.button == .Right
            {
                .popupMenu(view, evt.surfacePos)
                return true
            }

            if evt.kind == .Leave
            {
                .hotForm = Swag.U64.Max
            }
            else
            {
                var ht = .hitTest(localPos)
                if ht != Swag.U64.Max
                {
                    let p = cast(*BaseForm) @dataof(.forms[ht])
                    if view.main.freezeSel and p.freeze do
                        ht = Swag.U64.Max
                }

                if ht != .hotForm
                {
                    view.invalidate()
                    .hotForm = ht
                }
            }
        }

        if .hotForm != Swag.U64.Max do
            app.setFrameCursor(Cursor.from(.Move))

        let shiftPressed = cast(bool) (evt.modifiers & .Shift)
        let ctrlPressed  = cast(bool) (evt.modifiers & .Control)

        // Start of mode
        ///////////////////////
        if .mouseMode == .None and evt.button == .Left
        {
            if evt.kind == .Pressed or evt.kind == .DoubleClick
            {
                // Ctrl+Shift force the selection mode
                if (shiftPressed and ctrlPressed) or view.main.editMode == .Selection
                {
                    .mouseMode      = .Selecting
                    .firstMouseMove = true
                    .movingStart    = localPos
                    view.captureMouse()
                    view.invalidate()
                    .drawSelRect = true
                }
                else
                {
                    // Double-click on a grouped form enters the group: select just that
                    // child so it can be moved/edited on its own (standard "enter group").
                    if evt.kind == .DoubleClick and .hotForm != Swag.U64.Max and formOuterGroup(.forms[.hotForm]) != 0
                    {
                        .selection.clear()
                        .selection.add(.hotForm)
                        .selectionHasChanged()
                        .lastSelectPos  = evt.surfacePos
                        .mouseMode      = .Moving
                        .firstMouseMove = true
                        .movingStart    = localPos
                        view.captureMouse()
                        view.invalidate()
                        return true
                    }

                    var here = .selection.contains(.hotForm)

                    // Swap between objects at the same position if no mouse move
                    if .lastSelectPos.isEqualEpsilon(evt.surfacePos)
                    {
                        if !evt.modifiers.has(.Control) and .selection.count
                        {
                            .selection.clear()
                            .selectionHasChanged()
                        }

                        let res = .hitTests(localPos, false)
                        .lastSelectHit += 1
                        if .lastSelectHit >= res.count do
                            .lastSelectHit = 0
                        .hotForm = res[.lastSelectHit]
                        here     = .selection.contains(.hotForm)
                    }
                    elif !evt.modifiers.has(.Control) and !here and .selection.count
                    {
                        .updateModelValuesFromSelection()
                        .selection.clear()
                        .selectionHasChanged()
                        .lastSelectHit = 0
                    }

                    if .hotForm != Swag.U64.Max
                    {
                        if !here
                        {
                            .lastSelectPos = evt.surfacePos
                            .selection.add(.hotForm)
                            .expandSelectionToGroups()
                            .selectionHasChanged()
                        }

                        .mouseMode      = .Moving
                        .firstMouseMove = true
                        .movingStart    = localPos
                        view.captureMouse()
                        view.invalidate()
                    }
                    else
                    {
                        .mouseMode      = .Creating
                        .firstMouseMove = true
                        .movingStart    = localPos
                        view.captureMouse()
                        view.invalidate()
                    }
                }
            }
        }

        // End of mode
        ///////////////////////
        if evt.kind == .Released and evt.button == .Left
        {
            .snapX, .snapY = -1

            if .mouseMode == .Selecting
            {
                view.releaseMouse()
                view.invalidate()
                .mouseMode   = .None
                .drawSelRect = false
                view.main.updateState()
            }

            if .mouseMode == .Moving or .firstMouseMove
            {
                let wasMoving = .mouseMode == .Moving
                view.releaseMouse()
                view.invalidate()
                .mouseMode = .None

                // A body-drag move ends here (it does NOT go through GizmoRect/sigHasChanged,
                // unlike a resize). Refresh the Properties panel so x/y reflect the new
                // position, mirroring the rotate path.
                if wasMoving and @isset(view.main.propWnd) do
                    view.main.propWnd.selectionHasChanged()
            }
        }

        // Mode
        ///////////////////////
        switch .mouseMode
        {
        case .Selecting:
            var r: Math.Rectangle

            .movingEnd = localPos
            r.set(.movingStart, .movingEnd)

            // Rebuild the selection from scratch, then notify only if the set actually
            // changed: selectionHasChanged() triggers a full rebuild of the Properties
            // and QuickStyles panels, far too heavy to run on every mouse move.
            var newSel: Array'u64
            if ctrlPressed do
                newSel = .selection

            for f, idx in .forms
            {
                let pp = f.boundRect() * view.zoom
                if pp.intersects(r) and !newSel.contains(idx) do
                    newSel.add(idx)
            }

            // Touching any group member with the lasso selects the whole group.
            .expandGroups(&newSel)

            var selChanged = newSel.count != .selection.count
            if !selChanged
            {
                for i in newSel.count
                {
                    if newSel[i] != .selection[i]
                    {
                        selChanged = true
                        break
                    }
                }
            }

            .firstMouseMove = false
            view.invalidate()
            if selChanged
            {
                .selection = newSel
                .selectionHasChanged()
            }

            return true

        case .Moving:
            let newPosX = cast(s32) ((localPos.x - .movingStart.x) / view.zoom)
            let newPosY = cast(s32) ((localPos.y - .movingStart.y) / view.zoom)

            if .firstMouseMove
            {
                if Math.abs(newPosX) <= 3 and Math.abs(newPosY) <= 3 do
                    return true
                .firstMouseMove = false
            }
            else do
                .undo()

            let u = .newUndo(.OffsetSelection)

            // Snap by bottom/right
            var nx = newPosX
            var ny = newPosY
            .snap(&nx, &ny, true, true)
            let saveSnapX = .snapX
            let saveSnapY = .snapY

            // Snap by top/left
            var nx1 = newPosX
            var ny1 = newPosY
            .snap(&nx1, &ny1, false, false)

            if Math.abs(nx - newPosX) > Math.abs(nx1 - newPosX)
            {
                .snapX    = saveSnapX
                u.newPosX = nx
            }
            else do
                u.newPosX = nx1
            if Math.abs(ny - newPosY) > Math.abs(ny1 - newPosY)
            {
                .snapY    = saveSnapY
                u.newPosY = ny
            }
            else do
                u.newPosY = ny1

            .pushUndo(u)
            view.invalidate()
            return true

        case .Creating:
            let newPosX = cast(s32) ((localPos.x - .movingStart.x) / view.zoom)
            let newPosY = cast(s32) ((localPos.y - .movingStart.y) / view.zoom)

            if .firstMouseMove
            {
                let editView = .editView!
                if Math.abs(newPosX) <= 3 and Math.abs(newPosY) <= 3 and editView.main.editMode != .Step do
                    return true
                .firstMouseMove = false

                let mode = editView.main.getEditMode()
                let itf  = editView.main.newFormFromModel(mode, clear: true)
                if itf do
                    itf.setup(me)
                let base = cast(*BaseForm) @dataof(itf)
                if base and editView.main.editMode == .PixSel do
                    base.subKind = .PixSel
                let undo = .newUndo(.CreateForm)
                undo.oldForms.add(itf)
                .pushUndo(undo)

                if itf != FormStep
                {
                    .selection.clear()
                    .selection.add(.forms.count - 1)
                    .selectionHasChanged()
                }
            }

            let f = .forms.back()
            if !f.edit(evt, .movingStart, localPos, view.zoom)
            {
                view.releaseMouse()
                view.invalidate()
                .mouseMode = .None
            }

            .hasChanged()
            return true
        }

        return false
    }

    mtd hitTest(localPos: Math.Point)->u64
    {
        // Holding 'O' makes the mouse ignore every form, so a click can start a
        // lasso or create a new form on top of existing ones.
        if .editView!.app().keyboard.isKeyPressed(Input.Key.O) do
            return Swag.U64.Max
        let res = .hitTests(localPos, true)
        if res.isEmpty() do
            return Swag.U64.Max
        return res[0]
    }

    mtd hitTests(localPos: Math.Point, retFirst: bool)->Array'u64
    {
        var result: retval
        if !.forms.count do
            return result
        let editView = .editView!
        for #reverse i in @countof(.forms)
        {
            let f = .forms[i]
            if !f.hitTest(localPos, editView.zoom) do
                continue
            result.add(i)
            if retFirst do
                break
        }

        return result
    }

    //////////////////////////////
    // SELECTION
    //////////////////////////////

    mtd getSelectedBaseForm()->#null *BaseForm
    {
        if .selection.isEmpty() do
            return null
        return cast(*BaseForm) @dataof(.forms[.selection.back()])
    }

    mtd getSelectedFormType()->#null typeinfo
    {
        if .selection.isEmpty() do
            return null
        let i = .forms[.selection.back()]
        return @kindof(i)
    }

    mtd updateEditModeFromSelection()
    {
        if !.selection.count do
            return

        let main = .editView!.main
        if main.editMode == .Selection do
            return

        let f = .forms[.selection.back()]
        main.updateEditMode(f)
    }

    mtd updateModelValuesFromSelection()
    {
        if !.selection.count do
            return
        let f        = .forms[.selection.back()]
        let editView = .editView!
        editView.main.updateModelValues(f)
    }

    mtd updateModelFromSelection()
    {
        if !.selection.count do
            return
        let f        = .forms[.selection.back()]
        let editView = .editView!
        editView.main.updateModel(f)
    }

    mtd selectionHasChanged()
    {
        .updateEditModeFromSelection()
        .updateModelFromSelection()
        let editView = .editView!
        editView.main.updateState()
        editView.invalidate()
    }

    //////////////////////////////
    // GROUP
    //////////////////////////////

    // Outermost group id a form belongs to (0 = ungrouped). Selecting/hit-testing a
    // grouped form expands to every form sharing this id, so a group moves as a whole.
    func formOuterGroup(f: IForm)->u64
    {
        let b = cast(*BaseForm) @dataof(f)
        if b.groups.isEmpty() do
            return 0
        return b.groups[0]
    }

    func groupIndexOf(arr: Array'u64, v: u64)->s64
    {
        for x, i in arr where x == v do
            return i
        return -1
    }

    mtd newGroupId()->u64
    {
        let id = .nextGroupId
        .nextGroupId += 1
        return id
    }

    // Grow a selection so that whenever one member of a group is selected, the entire
    // outermost group is too. Called after a click/lasso builds a raw set.
    mtd expandGroups(sel: *Array'u64)
    {
        var ids: Array'u64
        for s in dref sel
        {
            let g = formOuterGroup(.forms[s])
            if g != 0 and !ids.contains(g) do
                ids.add(g)
        }

        if ids.isEmpty() do
            return

        for f, i in .forms
        {
            let g = formOuterGroup(f)
            if g != 0 and ids.contains(g) and !sel.contains(i) do
                sel.add(i)
        }

        sel.sort()
    }

    mtd expandSelectionToGroups()
    {
        .expandGroups(&.selection)
    }

    // Grouping wraps two or more selected items into one new group; a single item has
    // nothing to combine with.
    mtd canGroup()->bool
    {
        return .selection.count >= 2
    }

    // Ungrouping applies as soon as any selected item is part of a group.
    mtd canUngroup()->bool
    {
        foreachSelected'BaseForm(me, .selection)
        {
            if formOuterGroup(itf) != 0 do
                return true
        }

        return false
    }

    // True when the selection contains at least one pixel-selection form
    mtd hasSelectedPixSel()->bool
    {
        foreachSelected'BaseForm(me, .selection)
        {
            if form.subKind == .PixSel do
                return true
        }

        return false
    }

    // Give every distinct group id in 'forms' a fresh id, keeping the relative nesting
    // structure. Used when pasting so copies form their own groups instead of silently
    // re-joining the originals (or colliding across capture files).
    mtd remapGroups(forms: Array'IForm)
    {
        var oldIds: Array'u64
        var newIds: Array'u64

        for f in forms
        {
            let b = cast(*BaseForm) @dataof(f)
            for gid in b.groups
            {
                if gid == 0 or groupIndexOf(oldIds, gid) >= 0 do
                    continue
                oldIds.add(gid)
                newIds.add(.newGroupId())
            }
        }

        for f in forms
        {
            let b = cast(*BaseForm) @dataof(f)
            for i in b.groups.count
            {
                let idx = groupIndexOf(oldIds, b.groups[i])
                if idx >= 0 do
                    b.groups[i] = newIds[idx]
            }
        }
    }

    //////////////////////////////
    // UNDO
    //////////////////////////////

    // Allocate a new (not yet pushed) Undo command. To group several commands into one
    // undo/redo step, mint a shared id with .undoMgr.newSerial() and pass it to pushUndo.
    mtd newUndo(kind: UndoKind)->*Undo
    {
        let ptr = Memory.new'Undo()
        ptr.kind = kind
        return ptr
    }

    mtd canUndo()->bool
    {
        return .undoMgr.canUndo()
    }

    mtd canRedo()->bool
    {
        return .undoMgr.canRedo()
    }

    mtd undo()
    {
        .undoMgr.undo()

        // During an interactive drag, apply() calls undo() every move to re-apply the
        // move from scratch; the per-form partial invalidate handles the repaint.
        if !.interactiveMove do
            .editView?.invalidate()
    }

    mtd redo()
    {
        .undoMgr.redo()

        if !.interactiveMove do
            .editView?.invalidate()
    }

    // Push a command onto the undo timeline. A non-zero 'serial' groups this command with the
    // others sharing that value into one undo/redo step (0 = its own fresh group); get a shared
    // id from .undoMgr.newSerial().
    mtd pushUndo(u: *Undo, serial: u64 = 0)
    {
        u.capture = me

        // Capture the "before" state, then hand the command to the generic manager which
        // discards the redo tail (freeing those commands) and applies this one via redo()/doIt().
        u.init()
        .undoMgr.pushCmd(u, serial, apply: true)
    }
}
