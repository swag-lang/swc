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

// Shadows are smooth masks in capture coordinates. Small forms keep native
// resolution; large ones cap the mask size while the content remains sharp.
const MaxFormShadowDim = 1536
const FormShadowMargin = 8
const FormShadowRadius = 8.0'f32

// Ceiling of one retained form rendering, in device texels per axis, supersampling
// included; a form drawn larger falls back to the direct, view-clipped path so a
// pathological extent can never pin a giant texture.
const MaxFormCacheDim = 4096

// Zoom-stale retained renderings refreshed per repaint. The rest draw scaled from
// their retained texture and sharpen over the following frames.
const MaxFormCacheRefresh = 3

// One retained off-screen rendering of a form. Sharp content can be rebuilt
// after zoom while its document-space shadow mask stays put. An unchanged form
// composites two textures without supersampling or blurring again. Owned by
// [Capture.formCaches], keyed by the form, pruned by
// [Capture.pruneFormCaches] before the form's memory can be recycled.
struct FormCache
{
    form:        IForm?           // The rendered form; the key of this entry. Set at creation.
    layer:       Layer            // Retained sharp content at the current view zoom.
    shadow:      Layer            // Blurred mask retained across view zooms.
    shadowScale: f32              // Capture-to-mask scale used for the shadow bake.
    zoom:        f32              // View zoom the content was rendered at.
    scale:       f32              // Painter content scale the content was rendered at.
    samples:     s32              // Samples per pixel the content was rendered with.
    dirty:       bool = true      // The content changed; re-render before the next draw.
    clipped:     bool             // The retained layer covers the view rather than the whole form.
    origin:      Math.Vector2     // Layer origin relative to the capture rectangle when clipped.
}

impl FormCache
{
    mtd opDrop()
    {
        // Entries die outside a recording scope, where a painter-recorded release
        // would be discarded with the next frame's commands.
        .layer.releaseImmediate()
        .shadow.releaseImmediate()
    }
}

// Captures use the application-independent SCC extension. The container kind, not the extension,
// distinguishes a capture from another SCC document.
const CaptureFileExtension = ".scc"

// The frames of a timed capture live beside it, named after it with this extension, so moving,
// trashing or restoring the capture carries them along and a save of the capture never rewrites
// them.
const CaptureMediaExtension = ".frames"

// New video stems start with `video-`; legacy exact-stem MP4 files remain readable. Distinct
// stems keep players from auto-loading a capture's SCC document as Scenarist Closed Captions.
const CaptureVideoExtension = ".mp4"

// Profile written for a picture, which every earlier Swag Capture reads.
const CapturePictureProfileVersion = 1'u32

// Newest profile this version reads and the one written for a timed capture, whose frames an
// earlier version could not show.
const CaptureProfileVersion = 2'u32

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

// What a capture keeps of its source. A picture is the zero-length case of a timeline: the canvas
// always shows `Capture.backImg`, which a timed capture refreshes from the frame at its playhead,
// so every editing path stays shared between media.
enum CaptureMedia
{
    Picture       // One picture.
    Animation     // A short silent recording, exported as an animated picture.
    Video         // A screen recording with optional separate sound tracks.
}

// The time of a timed capture. Its frames are in the frame file beside the capture
// ([[CaptureMediaExtension]]).
struct CaptureTimeline
{
    frameCount: u64     // Number of frames recorded.
    duration:   u64     // Time from the first frame to the end of the last one, in microseconds.
    mediaSize:  u64     // Size of the frame file when it was recorded; another size means it was replaced.

    // The part kept by playback and exports, in microseconds from the start: from `inPoint`,
    // until `outPoint` excluded, or to the end when `outPoint` is zero. The frames themselves are
    // never cut.
    inPoint:  u64
    outPoint: u64
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
    media:             CaptureMedia
    duration:          u64     // Length of a timed capture, in microseconds.
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
    media:               CaptureMedia
    timeline:            CaptureTimeline
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

    // What the capture keeps, and the time of a timed one.
    media:    CaptureMedia
    timeline: CaptureTimeline

    // Editing state, rebuilt at run time rather than stored with the capture.
    #[NoSerialize]
    {
        // Frames of a timed capture, open while it is edited, and the frame `backImg` shows.
        frames:   *TimedReader?
        playhead: u64

        // The frame file of a timed capture is missing, unreadable or was replaced.
        mediaMissing: bool

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

// One decoded capture and its failure remain owned until the requesting window accepts them.
struct CaptureLoadJob
{
    task:    Swag.Task
    file:    String
    capture: *Capture?
    error:   Swag.Error
}

// One duplicate owns both paths until its SCC and timed media files are ready.
struct CaptureDuplicateJob
{
    task:   Swag.Task
    source: String
    target: String
    error:  Swag.Error
}

// An already rendered image is encoded and written without holding the interface thread.
struct CaptureImageWriteJob
{
    task: Swag.Task
    image: Image
    source: String
    target: String
    error: Swag.Error
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

// One library edit owns its values until the file worker has written them.
struct CaptureMetadataJob
{
    task:        Swag.Task
    late owner:  *MainWnd
    file:        String
    title:       String
    tags:        Array'String
    favorite:    bool
    rating:      u8
    hasTitle:    bool
    hasTags:     bool
    hasFavorite: bool
    hasRating:   bool
    error:       Swag.Error
}

// The file-writer lane. The automatic save owns one snapshot slot; library metadata edits wait
// behind it and run in request order. Readers, moves and deletions flush the affected file first.
struct CaptureSaveQueue
{
    pending: *CaptureSaveJob?
    metadataPending: *CaptureMetadataJob?
    metadataWaiting: Array'*CaptureMetadataJob
}

var g_CaptureSaves: CaptureSaveQueue

impl CaptureSaveQueue
{
    // Returns whether the writer lane has unfinished work.
    mtd busy()->bool
    {
        if .metadataPending or not .metadataWaiting.isEmpty() do
            return true
        return .pending and not .pending.task.isDone()
    }

    mtd metadataTargets(file: string)->bool
    {
        if .metadataPending and .metadataPending.file == file do
            return true
        for job in .metadataWaiting where job.file == file do
            return true
        return false
    }

    mtd writing(file: string)->bool => (.pending and .pending.file == file) or .metadataTargets(file)

    mtd adoptMetadata(job: *CaptureMetadataJob)
    {
        .metadataWaiting.add(job)
        .startMetadata()
    }

    private mtd startMetadata()
    {
        if .pending or .metadataPending or .metadataWaiting.isEmpty() do
            return
        let job = .metadataWaiting[0]
        .metadataWaiting.removeAt(0)
        .metadataPending = job
        job.owner.startMetadataTask(job)
    }

    // The timer or a synchronous flush lands one result and advances the serial queue.
    mtd finishMetadata()
    {
        let job = .metadataPending
        if not job or not job.task.isDone() do
            return
        .metadataPending = null
        if not job.error.isEmpty()
        {
            let message = job.hasTitle ? appStrings().msg_FailedRename : appStrings().msg_FailedSaveMetadata
            job.owner.reportFailure(message)
            if job.owner.libWnd != null and job.owner.libWnd.view != null do
                catch job.owner.libWnd.view.fill()
        }
        Memory.delete(job)
        .startMetadata()
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

        var result: #returntype
        if job.failed do
            result = job.file
        .pending = null
        Memory.delete(job)
        .startMetadata()
        return result
    }

    // Waits for the automatic save and queued metadata edits that precede `file` (all files when
    // null). Returns the automatic save's failed file, empty otherwise; metadata failures are
    // reported by their owner.
    mtd flush(file: string? = null)->String
    {
        var failed: String
        if .pending and (file == null or .pending.file == file or .metadataTargets(file))
        {
            .pending.task.wait()
            failed = .collect()
        }
        while .metadataPending or not .metadataWaiting.isEmpty()
        {
            if file != null and not .metadataTargets(file) do
                break
            .startMetadata()
            let job = unwrap .metadataPending
            job.task.wait()
            .finishMetadata()
        }
        return failed
    }
}

// Visits the forms listed in `selection` (an array of slots in capture.forms) that
// match T; `BaseForm` matches every form. The injected block sees the typed form as
// `form`, its interface as `itf`, and a visit counter as `idx`. `continue` skips a
// form without advancing `idx` — the exact contract needed to pair `idx` with arrays
// built by a previous, identically-filtered pass — and `break` stops the visit.
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
    // Stores a copy of `itf` in the field its kind names.
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

    // Creates a new form from the stored copy, set up for `capture`.
    mtd toForm(capture: *Capture)->IForm?
    {
        var result: #returntype

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
        var result: #returntype
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
            .editView!.app().renderer.removeTexture(&.backTexture)
        freeForms(.forms)
        .closeMedia()
    }

    // Attaches the capture to `view`, and makes a drag of the canvas gizmo resize the canvas as
    // one undo step.
    mtd setup(view: *EditView)
    {
        .editView         = view
        .gizmo.sigChanged = func|capture = me|(g, _, _)
        {
            let editView  = unwrap capture.editView
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
