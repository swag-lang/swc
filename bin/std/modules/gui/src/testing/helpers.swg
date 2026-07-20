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
    fileName += GUID64.getRandom().getString()
    fileName += extension
    return Path.combine(folder.toString(), fileName.toString())
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
        dref cast(*u32) pix = Color.fromArgb(255'u8, value, green, blue).argb
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
func commandState(id: #nonull WndId)->CommandStateEvent
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
func(T) actionAccept(wnd: *Wnd, id: #nonull WndId)->bool
{
    let act = @mkinterface(null, #typeof(T), IActionUI)
    return act.accept({wnd: wnd, id: id})
}

// Executes action type T through its IActionUI interface, as the command dispatch would.
func(T) actionExecute(wnd: *Wnd, id: #nonull WndId)->bool
{
    let act = @mkinterface(null, #typeof(T), IActionUI)
    return act.execute({wnd: wnd, id: id})
}

// Updates the command state of action type T through its IActionUI interface.
func(T) actionUpdate(wnd: *Wnd, id: #nonull WndId, evt: *CommandStateEvent)->bool
{
    let act = @mkinterface(null, #typeof(T), IActionUI)
    return act.update({wnd: wnd, id: id}, evt)
}
