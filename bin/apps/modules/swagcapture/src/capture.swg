using Serialization

const PreviewHeight = 256.0
const PreviewWidth  = PreviewHeight * (4 / 3.0)

// What a mouse drag on the capture is doing.
enum MouseMode
{
    None
    Moving
    Creating
    Selecting
}

const TextFormSuperSample = 3

// Ceiling of one retained form rendering, in device texels per axis, supersampling
// included; a form drawn larger falls back to the direct, view-clipped path so a
// pathological extent can never pin a giant texture.
const MaxFormCacheDim = 4096

// Zoom-stale retained renderings refreshed per repaint. The rest draw scaled from
// their retained texture and sharpen over the following frames.
const MaxFormCacheRefresh = 3

// One retained off-screen rendering of a form. The layer keeps the resolved content
// and its baked shadow alive across frames, so a repaint that did not change the
// form composites two textured quads instead of re-rendering, supersampling, and
// blurring it. Owned by [Capture.formCaches], keyed by the form, pruned by
// [Capture.pruneFormCaches] before the form's memory can be recycled.
struct FormCache
{
    form:    IForm?          // The rendered form; the key of this entry. Set at creation.
    layer:   Layer           // Retained targets: resolved content, plus the shadow once built.
    zoom:    f32             // View zoom the content was rendered at.
    scale:   f32             // Painter content scale the content was rendered at.
    samples: s32             // Samples per pixel the content was rendered with.
    dirty:   bool = true     // The content changed; re-render before the next draw.
}

impl FormCache
{
    mtd opDrop()
    {
        // Entries die outside a recording scope, where a painter-recorded release
        // would be discarded with the next frame's commands.
        .layer.releaseImmediate()
    }
}

// Captures use the application-independent SCC extension. The container kind, not the extension,
// distinguishes a capture from another SCC document.
const CaptureFileExtension = ".scc"

const CaptureProfileVersion = 1'u32

// Where the pixels of a capture came from. Stored with the capture so the library can
// distinguish a screen grab from a picture opened for annotation or a blank canvas.
enum CaptureSourceKind
{
    Unknown         // Capture saved before source metadata was recorded.
    Screen          // Pixels captured from the desktop or an application window.
    ImageFile       // Image file opened or dropped into Swag Capture.
    Clipboard       // Bitmap pasted or dragged without a source file.
    BlankCanvas     // Empty image created in Swag Capture.
}

// Small profile header read by the library without touching the editable document or pixels.
#[Serialization.Version(1)]
#[Serialization.Schema("swag.capture.library-metadata")]
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

impl CaptureLibraryMetadata
{
    private func isValidText(value: String)->bool
    {
        if not Utf8.isValid(value.toSlice()) do
            return false
        for c in value where c < 32 do
            return false
        return true
    }

    // A preview header is optional indexing data. Older migrations can carry bytes from
    // a legacy document field in one of these slots, so discard only the invalid value
    // instead of letting it reach path APIs or visible library text.
    mtd sanitize()
    {
        if not .linkedImage.isEmpty() and (not isValidText(.linkedImage) or not Path.isValidPathName(.linkedImage))
        {
            .linkedImage.clear()
            .linkedUpToDate = true
        }

        if not isValidText(.sourceApplication) do
            .sourceApplication.clear()
        if not .sourceExecutable.isEmpty() and (not isValidText(.sourceExecutable) or not Path.isValidPathName(.sourceExecutable)) do
            .sourceExecutable.clear()
        if not isValidText(.sourceWindowTitle) do
            .sourceWindowTitle.clear()
        if not isValidText(.sourceWindowClass) do
            .sourceWindowClass.clear()
    }
}

// Editable capture state stored independently from the large background images.
#[Serialization.Version(1)]
#[Serialization.Schema("swag.capture.document")]
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

// A capture document: the image, the forms drawn over it, the image file it may be linked to,
// and where it came from.
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

    // Editing state, rebuilt at run time rather than stored with the capture.
    #[NoSerialize]
    {
        // Anomalies the tolerant load had to swallow: reset fields, unknown types,
        // corrupt payloads. Nonzero means the file did not fully match the current
        // schema and a save would not preserve everything it held.
        loadIssues: u32

        // Encoded SCC thumbnail retained by the library until a visible cell needs pixels.
        previewBytes: Array'u8

        changed:   bool
        mouseMode: MouseMode = .None
        editView:  *EditView?
        gizmo:     GizmoRect
        undoMgr:   UndoManager
        hotForm:   u64       = Swag.U64.Max
        selection: Array'u64
        paintRect: Math.Rectangle

        backTexture: Texture
        snapX:       f32 = -1
        snapY:       f32 = -1

        // Retained per-form renderings (see FormCache) and the per-repaint budget for
        // sharpening the ones a zoom left behind.
        formCaches:       ArrayPtr'FormCache
        cacheRefreshLeft: s32
        cacheNeedsRefine: bool

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

// Everything one save writes, snapshotted from the capture so a worker can
// produce the container while the user keeps editing.
struct CaptureSaveJob
{
    task:       Swag.Task     // Runtime task; it borrows this value until the save is collected.
    file:       String        // Destination path, atomically replaced when the write lands.
    manifest:   Scc.Manifest
    modelBytes: Array'u8     // Document model, already TagBin-encoded: forms are only safe to read on the interface thread.
    backImg:    Image        // Owned pixel copies, because a later crop or flatten must not race the encoder.
    backOrig:   Image
    preview:    Image
    failed:     bool     // Set by the worker when producing or replacing the file failed.
}

// The one automatic save in flight. A single slot is deliberate: the automatic save
// always targets the edited capture, and every other reader or writer of a capture
// file flushes this slot first, which keeps one writer per file at all times.
struct CaptureSaveQueue
{
    pending: *CaptureSaveJob?
}

var g_CaptureSaves: CaptureSaveQueue

impl CaptureSaveQueue
{
    // Returns whether a scheduled save is still producing its file.
    mtd busy()->bool
    {
        if not .pending do
            return false
        let job = .pending
        return not job.task.isDone()
    }

    // Adopts one snapshot the caller has already submitted. The caller collected or flushed
    // the previous save first, so the slot holds one writer per file at all times.
    mtd adopt(job: *CaptureSaveJob)
    {
        Swag.assert(not .pending)
        .pending = job
    }

    // Frees a finished save and returns the file it failed to write, empty on success
    // or when nothing finished. A save still running is left alone.
    mtd collect()->String
    {
        if not .pending do
            return ""
        let job = .pending
        if not job.task.isDone() do
            return ""

        var result: retval
        if job.failed do
            result = job.file
        .pending = null
        Memory.delete(job)
        return result
    }

    // Waits for the save in flight when it targets `file` (any file when null), then
    // returns the file it failed to write, empty otherwise. Every other reader or
    // writer of a capture file goes through here before touching it.
    mtd flush(file: string? = null)->String
    {
        if not .pending do
            return ""
        let job = .pending
        if file != null and job.file != file do
            return ""
        job.task.wait()
        return .collect()
    }
}

// Visits the forms listed in 'selection' (an array of slots in capture.forms) that
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
            if Swag.kindOf(f) != T do
                continue
        }

        #inject(stmt, form = assume cast(*T, f), itf = f, idx = visitIdx)
        visitIdx += 1
    }
}

// Which field of a `CaptureClipboardForm` holds the copied form.
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

// One form copied to the clipboard, stored by value in the field its kind names.
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

// The forms a copy puts on the clipboard, as a typed value only Swag Capture reads back.
#[Serialization.Schema("swag.capture.clipboard-forms")]
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
            .arrow = form[]

        case FormDraw as form:
            .kind = .Draw
            .draw = form[]

        case FormImage as form:
            .kind  = .Image
            .image = form[]

        case FormLine as form:
            .kind = .Line
            .line = form[]

        case FormPolygon as form:
            .kind    = .Polygon
            .polygon = form[]

        case FormShape as form:
            .kind  = .Shape
            .shape = form[]

        case FormStep as form:
            .kind = .Step
            .step = form[]

        case FormText as form:
            .kind = .Text
            .text = form[]

        case FormCallout as form:
            .kind    = .Callout
            .callout = form[]

        default:
            .kind = .None
        }
    }

    mtd toForm(capture: *Capture)->IForm?
    {
        var result: retval

        switch .kind
        {
        case .Arrow:
            let form = Memory.new'FormArrow()
            form[] = .arrow
            result = form

        case .Draw:
            let form = Memory.new'FormDraw()
            form[] = .draw
            result = form

        case .Image:
            let form = Memory.new'FormImage()
            form[] = .image
            result = form

        case .Line:
            let form = Memory.new'FormLine()
            form[] = .line
            result = form

        case .Polygon:
            let form = Memory.new'FormPolygon()
            form[] = .polygon
            result = form

        case .Shape:
            let form = Memory.new'FormShape()
            form[] = .shape
            result = form

        case .Step:
            let form = Memory.new'FormStep()
            form[] = .step
            result = form

        case .Text:
            let form = Memory.new'FormText()
            form[] = .text
            result = form

        case .Callout:
            let form = Memory.new'FormCallout()
            form[] = .callout
            result = form

        case .None:
            return result
        }

        result!.setup(capture)
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
        for it in forms do
            Memory.delete(it.buffer, Swag.kindOf(it))
    }

    mtd opDrop()
    {
        if .backTexture.isValid() do
            g_App.renderer.removeTexture(&.backTexture)
        freeForms(.forms)
    }

    mtd setup(view: *EditView)
    {
        .editView         = view
        .gizmo.sigChanged = func|capture = me|(g, ?, ?)
        {
            let editView  = capture.editView!
            with let undo = capture.newUndo(.MoveCapture)
            {
                .newPosX  = cast(s32, ((g.rect.x - g.movingRect.x) / editView.zoom))
                .newPosY  = cast(s32, ((g.rect.y - g.movingRect.y) / editView.zoom))
                .newSizeX = cast(s32, ((g.movingRect.width - g.rect.width) / editView.zoom))
                .newSizeY = cast(s32, ((g.movingRect.height - g.rect.height) / editView.zoom))
            }

            capture.pushUndo(undo)
            editView.invalidate()
        }
    }
}
