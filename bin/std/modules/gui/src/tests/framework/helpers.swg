#global public
#global namespace Testing

using Core, Pixel

// Shared helpers for headless test suites (module and application unittests).

// Asserts that 'rect' equals the given coordinates within 'eps'.
func assertRect(rect: Math.Rectangle, x, y, width, height: f32, eps: f32 = 0.001)
{
    @assert(Math.abs(rect.x - x) < eps)
    @assert(Math.abs(rect.y - y) < eps)
    @assert(Math.abs(rect.width - width) < eps)
    @assert(Math.abs(rect.height - height) < eps)
}

// Asserts that 'pt' equals the given coordinates within 'eps'.
func assertPoint(pt: Math.Vector2, x, y: f32, eps: f32 = 0.001)
{
    @assert(Math.abs(pt.x - x) < eps)
    @assert(Math.abs(pt.y - y) < eps)
}

// Asserts that no window in the tree is smaller than the content it says it needs.
//
// Every window is asked through [[Gui.IWnd.measureContent]], whatever size its author
// gave it, so this catches the caption pinned to a width that only fitted in English as
// surely as the paragraph a layout pass measured. Run it once per shipped language to
// prove a surface holds its own translations. The console line names the offender,
// because a failed assertion on a rectangle does not say which text was cut.
func assertContentFits(root: *Wnd, tolerance = 0.5'f32)
{
    if !root.isLocallyVisible() do
        return

    let content = root.itf.measureContent({root.position.width, root.position.height})
    if content.x > root.position.width + tolerance or content.y > root.position.height + tolerance
    {
        Console.println("content does not fit in ",
                        root.type.name,
                        " '",
                        root.name.raw,
                        "': needs ",
                        content.x,
                        "x",
                        content.y,
                        ", arranged ",
                        root.position.width,
                        "x",
                        root.position.height)
        @assert(false)
    }

    for child in root.children do
        assertContentFits(child, tolerance)
}

// Returns a unique file path in a dedicated 'swag-tests' sub-folder of the system
// temp folder (created on demand). A dedicated folder keeps test files out of the
// source tree and stays nearly empty, so tests that drive a real file dialog into
// it only enumerate a handful of entries, not the whole system temp folder.
func tempFilePath(prefix, extension: string)->String
{
    let tempDir = Env.getSpecialDirectory(Env.SpecialDirectory.Temp)
    let folder  = Path.combine(tempDir.toString(), "swag-tests")
    if !Directory.exists(folder) do
        catch Directory.create(folder)

    var fileName = String.from(prefix)
    fileName += Guid64.random().toString()
    fileName += extension
    return Path.combine(folder.toString(), fileName.toString())
}

// The bytes of 'text', with no terminator, which is what a payload carries.
func textBytes(text: string)->Array'u8
{
    var result: retval
    result.add(@mkslice(cast(const [*] u8) @dataof(text), cast(u64) @countof(text)))
    return result
}

// Whether a byte payload holds exactly the bytes of 'text'.
//
// Two slices compare as the views they are rather than as their content, so a test that means
// "these bytes say this" has to ask for it.
func bytesAre(bytes: const [..] u8, text: string)->bool
{
    if @countof(bytes) != cast(u64) @countof(text) do
        return false
    return Memory.compare(@dataof(bytes), @dataof(text), @countof(bytes)) == 0
}

// Deterministic BGRA test image: every pixel derives from its coordinates, so a
// save/load round-trip can be verified byte-for-byte.
func indexedImage(w, h: s32)->Image
{
    var result = Image.create(w, h, .BGRA8)
    result.visitPixels()
    {
        let value = cast(u8) ((1 + x + y * 17) % 251)
        let green = cast(u8) ((cast(u32) value + 3) % 251)
        let blue  = cast(u8) ((cast(u32) value + 7) % 251)
        dref cast(*u32) pix! = Color.fromArgb(255'u8, value, green, blue).argb
    }

    return result
}

// Number of non-zero bytes in the image pixels (cheap "something was painted" probe).
func countNonZeroBytes(img: Image)->u64
{
    var count: u64
    let bytes = img.pixels.toSlice()
    for b in bytes
    {
        if b != 0 do
            count += 1
    }

    return count
}

// Returns a command state event for the given command id.
func commandState(id: WndId)->CommandStateEvent
{
    var evt: CommandStateEvent
    @init(&evt.name, 1)
    @init(&evt.longName, 1)
    @init(&evt.shortcut, 1)
    @init(&evt.toolTip, 1)
    evt.id = id
    return evt
}

// Asks action type T whether it accepts the command, through its IActionUI interface.
func(T) actionAccept(wnd: #null *Wnd, id: WndId)->bool
{
    let act = @mkinterface(null, #typeof(T), IActionUI)
    return act.accept({wnd: wnd, id: id})
}

// Executes action type T through its IActionUI interface, as the command dispatch would.
func(T) actionExecute(wnd: #null *Wnd, id: WndId)->bool
{
    let act = @mkinterface(null, #typeof(T), IActionUI)
    return act.execute({wnd: wnd, id: id})
}

// Updates the command state of action type T through its IActionUI interface.
func(T) actionUpdate(wnd: *Wnd, id: WndId, evt: *CommandStateEvent)->bool
{
    let act = @mkinterface(null, #typeof(T), IActionUI)
    return act.update({wnd: wnd, id: id}, evt)
}
