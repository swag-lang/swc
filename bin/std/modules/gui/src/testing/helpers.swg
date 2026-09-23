#global public
#global namespace Testing

using Core, Pixel

// Shared helpers for headless test suites (module and application unittests).

// Asserts that `rect` equals the given coordinates within `eps`.
func assertRect(rect: Math.Rectangle, x, y, width, height: f32, eps: f32 = 0.001)
{
    Swag.assert(Math.abs(rect.x - x) < eps)
    Swag.assert(Math.abs(rect.y - y) < eps)
    Swag.assert(Math.abs(rect.width - width) < eps)
    Swag.assert(Math.abs(rect.height - height) < eps)
}

// Asserts that `pt` equals the given coordinates within `eps`.
func assertPoint(pt: Math.Vector2, x, y: f32, eps: f32 = 0.001)
{
    Swag.assert(Math.abs(pt.x - x) < eps)
    Swag.assert(Math.abs(pt.y - y) < eps)
}

// True when this window has said its content may be cut: a label that ends an overflowing
// line with an ellipsis is asking to be given less than its text.
private func settlesForLess(wnd: *Wnd)->bool
{
    if wnd.itf is Label as label do
        return label.flags.has(.Ellipsis)
    return false
}

// Asserts that no window in the tree is smaller than the content it says it needs.
//
// Every window is asked through [[Gui.IWnd.measureContent]], whatever size its author
// gave it, so this catches the caption pinned to a width that only fitted in English as
// surely as the paragraph a layout pass measured. Run it once per shipped language to
// prove a surface holds its own translations. The console line names the offender,
// because a failed assertion on a rectangle does not say which text was cut.
//
// A window is excused when it, or one of its own children, ends in an ellipsis:
// [[Gui.IWnd.measureContent]] answers the width the text would like, and
// [[Gui.LabelFlags.Ellipsis]] is the author answering that this one settles for less. Without
// that, a file name deliberately longer than the panel showing it reads as a layout fault.
func assertContentFits(root: *Wnd, tolerance = 0.5'f32)
{
    if not root.isLocallyVisible() do
        return

    let content = root.itf.measureContent({root.position.width, root.position.height})
    if content.x > root.position.width + tolerance or content.y > root.position.height + tolerance
    {
        var excused = settlesForLess(root)
        for child in root.children
        {
            if child.isLocallyVisible() and settlesForLess(child)
            {
                excused = true
                break
            }
        }

        if not excused
        {
            Console.println("content does not fit in ",
                            Swag.kindOf(root.itf).name,
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
            Swag.assert(false)
        }
    }

    for child in root.children do
        assertContentFits(child, tolerance)
}

// Returns a unique file path in the `swag-tests` folder of the system temp folder.
//
// The folder is created on demand. A dedicated folder keeps test files out of the source
// tree and stays nearly empty, so tests that drive a real file dialog into it only
// enumerate a handful of entries, not the whole system temp folder. The file itself is not
// created.
func tempFilePath(prefix, extension: string)->String
{
    let tempDir = Env.getSpecialDirectory(Env.SpecialDirectory.Temp)
    let folder  = Path.combine(tempDir.toString(), "swag-tests")
    if not Directory.exists(folder) do
        catch Directory.create(folder)

    var fileName = String.from(prefix)
    fileName += Guid64.random().toString()
    fileName += extension
    return Path.combine(folder.toString(), fileName.toString())
}

// Returns a copy of the bytes of `text`, with no terminator, which is what a payload carries.
func textBytes(text: string)->Array'u8
{
    var result: retval
    result.add(cast(const [..] u8) text)
    return result
}

// Returns whether `bytes` holds exactly the bytes of `text`.
//
// Slices compare over their content, but bytes and text are different types, so the
// reinterpretation is spelled once here instead of at every call site.
func bytesAre(bytes: const [..] u8, text: string)->bool => bytes == cast(const [..] u8) text

// Returns an owned snapshot of the image sources successfully decoded by an HTML view.
//
// Each source appears once, in first-use order. Failed loads are excluded. The snapshot does
// not load or paint anything; it lets a test check lazy resource loading without a wall clock.
func htmlImageSources(view: const *HtmlView)->Array'String
{
    var result: retval
    for entry in view.images.entries where entry.loaded do
        result.add(entry.source)
    return result
}

// Returns a deterministic BGRA test image of `w` by `h` pixels.
//
// Every pixel derives from its coordinates, so a save/load round-trip can be verified
// byte-for-byte.
func indexedImage(w, h: s32)->Image
{
    var result = Image.create(w, h, .BGRA8)
    result.visitPixels()
    {
        let value = cast(u8) ((1 + x + y * 17) % 251)
        let green = cast(u8) ((cast(u32) value + 3) % 251)
        let blue  = cast(u8) ((cast(u32) value + 7) % 251)
        (cast(*u32) pix)[] = Color.fromArgb(255'u8, value, green, blue).argb
    }

    return result
}

// Returns the number of non-zero bytes in the pixels of `img`, a cheap probe that something was painted.
func countNonZeroBytes(img: Image)->u64
{
    var count: u64
    for b in img.pixels.toSlice() where b != 0 do
        count += 1
    return count
}

// Returns an empty command state event for the command `id`.
func commandState(id: WndId)->CommandStateEvent
{
    var evt: CommandStateEvent
    evt.id = id
    return evt
}

// Asks the action type `T` whether it accepts the command, through its [[Gui.IActionUI]] interface.
func(T) actionAccept(wnd: *Wnd?, id: WndId)->bool
{
    let act = Swag.makeInterface(null, #typeof(T), IActionUI)
    return act.accept({wnd: wnd, id: id})
}

// Executes the action type `T` through its [[Gui.IActionUI]] interface, as the command dispatch would.
func(T) actionExecute(wnd: *Wnd?, id: WndId)->bool
{
    let act = Swag.makeInterface(null, #typeof(T), IActionUI)
    return act.execute({wnd: wnd, id: id})
}

// Updates the command state of the action type `T` through its [[Gui.IActionUI]] interface.
func(T) actionUpdate(wnd: *Wnd, id: WndId, evt: *CommandStateEvent)->bool
{
    let act = Swag.makeInterface(null, #typeof(T), IActionUI)
    return act.update({wnd: wnd, id: id}, evt)
}
