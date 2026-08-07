#global public

using Core

// Selects what a drop does with the payload it carries.
//
// A source publishes the set it allows and a target answers with the single one it commits to,
// so the two values use the same type: [[Gui.DragDropEvent.allowed]] is a set and
// [[Gui.DragDropEvent.effect]] is one of its members. `None` on the target side rejects the drop
// and is what the pointer shows the user while the gesture is over that window.
#[Swag.EnumFlags]
enum DropEffect
{
    None = 0     // No effect; a target answering this rejects the drop.
    Copy         // Duplicates the payload and leaves the source holding its own copy.
    Move         // Transfers the payload, so the source removes it once the drop succeeds.
    Link         // Records a reference to the payload rather than its content.
}

// Payload of one drag gesture, in both directions.
//
// A target reads it: the value belongs to the framework and is borrowed for the duration of one
// [[Gui.DragDropEvent]] callback and no longer, so a window that wants to keep a path, a text or
// an image copies it out. Every accessor is safe on a drag that carries nothing of that kind.
//
// A source fills it: [[Gui.DragData.addFile]], [[Gui.DragData.setText]] and
// [[Gui.DragData.setImage]] say what the gesture offers, and [[Gui.Wnd.startDrag]] carries it to
// whatever the pointer is released on. Offering both a file and an image is the useful case
// rather than a redundant one — a folder takes the file, a picture editor takes the bitmap.
//
// The image is decoded lazily, because a drag hovering a window announces its formats long before
// anything is dropped: [[Gui.DragData.hasImage]] answers from the raw bytes and
// [[Gui.DragData.image]] is what pays for the decode.
struct DragData
{
    // Absolute paths offered by the source, in the order it listed them, empty when it offers none.
    readonly
    files: Array'String

    // Plain UTF-8 text offered by the source, empty when it offers none.
    readonly
    text: String

    internal
    {
        imageBytes:   Array'u8        // Encoded image bytes as offered, before any decode.
        imageName:    String          // File name whose extension selects the decoder.
        imageValue:   Pixel.Image     // Result of the one decode, kept for further reads.
        imageDecoded: bool            // Whether the decode was already attempted.
    }
}

impl DragData
{
    // Reports whether the source offers at least one file path.
    mtd const hasFiles()->bool => .files.count != 0

    // Reports whether the source offers text.
    mtd const hasText()->bool => !.text.isEmpty()

    // Reports whether the source offers an image, without decoding it.
    mtd const hasImage()->bool => .imageBytes.count != 0

    // Returns the only path offered by the source, or `null` unless it offers exactly one.
    //
    // This is what a control accepting a single document asks: a drag of three files is not a
    // drop it can honour, and answering `null` says so without the caller counting first.
    mtd const singleFile()->#null string
    {
        if .files.count != 1 do
            return null
        return .files[0].toString()
    }

    // Returns the decoded image offered by the source, or `null` when it offers none.
    //
    // The first call decodes and every later one returns the same value. A payload that fails to
    // decode answers `null` from then on. The image belongs to this payload and dies with it.
    mtd image()->#null *Pixel.Image
    {
        if !.imageDecoded
        {
            .imageDecoded = true
            if .imageBytes.count do
                .imageValue = catch Pixel.Image.decode(.imageName.toString(), .imageBytes.toSlice(), {})
        }

        if !.imageValue.isValid() do
            return null
        return &.imageValue
    }

    // Empties the payload so the same storage can carry the next gesture.
    mtd clear()
    {
        @drop(me, 1)
        @init(me, 1)
    }

    // Appends one path to the payload.
    //
    // A source offers its files in the order it adds them, and that is the order the target
    // reads them back in.
    mtd addFile(path: String)
    {
        .files.add(path)
    }

    // Replaces the text of the payload.
    mtd setText(value: String)
    {
        .text = value
    }

    // Replaces the image of the payload with one already encoded.
    //
    // `name` only has to carry the extension that names the encoding, `"drag.png"` for PNG bytes
    // or `"drag.bmp"` for a device-independent bitmap. Nothing is decoded here.
    mtd setImage(name: string, bytes: const [..] u8)
    {
        .imageBytes.clear()
        .imageBytes.add(bytes)
        .imageName    = name
        .imageDecoded = false
        .imageValue   = {}
    }

    // Replaces the image of the payload with a picture to encode.
    //
    // The bytes are produced now, because a source is asked for them at unpredictable moments
    // once the gesture is running. PNG is what is stored: it is lossless, every application
    // reads it, and the platform layer derives the bitmap forms it also has to offer from the
    // picture itself rather than from these bytes.
    mtd setImage(image: Pixel.Image) fail
    {
        var opt: Pixel.Png.EncodeOptions
        opt.compressionLevel = .BestSpeed

        var img    = image
        var buffer = try img.encode("drag.png", opt)
        buffer.makeLinear()

        .imageBytes.clear()
        .imageBytes.add(buffer.toSlice()!)
        .imageName    = "drag.png"
        .imageDecoded = true
        .imageValue   = image
    }
}

// Carries one phase of a drag and drop gesture over a window.
//
// The event is routed to the window under the pointer and bubbles to its ancestors the way every
// other input event does, so a control that ignores drops costs nothing and a container can
// answer for the whole of its content. A target commits to a drop by setting
// [[Gui.DragDropEvent.effect]] to one member of [[Gui.DragDropEvent.allowed]]; leaving it at
// `None` rejects the gesture and lets it bubble further.
//
// `Enter` and `Leave` bracket the time the pointer spends over one window and are what a control
// showing a drop highlight turns on and off. `Leave` is also delivered when the user cancels the
// drag or drops it elsewhere, so a highlight is never left behind.
//
// A target that shows the gesture repaints itself, the way it does for a mouse event: nothing is
// invalidated on its behalf, so a control that draws nothing costs nothing per pointer move.
struct DragDropEvent
{
    // Identifies the phase of a drag and drop gesture.
    enum Kind
    {
        Enter     // The pointer entered this window carrying a payload.
        Over      // The pointer moved inside this window carrying a payload.
        Leave     // The pointer left this window, or the gesture ended elsewhere.
        Drop      // The payload was released over this window.
    }

    using base: Event                              // Embedded base state.
    kind:       Kind                               // Gesture phase being reported.
    data:       *DragData          = undefined     // Payload being dragged, borrowed for this call.
    surfacePos: Math.Point                         // Pointer position in surface coordinates.
    modifiers:  Input.KeyModifiers = None          // Modifiers held during the gesture.
    allowed:    DropEffect         = None          // Effects the source permits.
    effect:     DropEffect         = None          // Effect this target commits to; `None` rejects.
}

impl IEvent for DragDropEvent {}

// Returns the effect the desktop convention asks for, restricted to what the source allows.
//
// This is the answer a target gives unless it has a reason of its own: `Control` copies, `Shift`
// moves, both together link, and nothing held takes the first of copy, move, and link the source
// offers. A modifier naming an effect the source refuses falls back the same way, so the returned
// value is always a member of `allowed` or `None`.
func pickDropEffect(allowed: DropEffect, modifiers: Input.KeyModifiers)->DropEffect
{
    if allowed == .None do
        return .None

    let wantsLink = modifiers.has(.Control) and modifiers.has(.Shift)
    if wantsLink and allowed.has(.Link) do
        return .Link
    if !wantsLink and modifiers.has(.Shift) and allowed.has(.Move) do
        return .Move
    if !wantsLink and modifiers.has(.Control) and allowed.has(.Copy) do
        return .Copy

    if allowed.has(.Copy) do
        return .Copy
    if allowed.has(.Move) do
        return .Move
    if allowed.has(.Link) do
        return .Link
    return .None
}

impl Application
{
    // Sends one drag phase to `target` and returns the effect it committed to.
    //
    // The event bubbles like every other input event, so the effect is the answer of the first
    // ancestor that claimed the gesture.
    private mtd sendDragEvent(target: *Wnd, kind: DragDropEvent.Kind, screenPos: Math.Point, data: *DragData, allowed: DropEffect, modifiers: Input.KeyModifiers)->DropEffect
    {
        var evt = DragDropEvent{kind: kind}
        evt.data       = data
        evt.surfacePos = target.screenToSurface(screenPos)
        evt.modifiers  = modifiers
        evt.allowed    = allowed
        evt.target     = target
        .sendEventPrivate(&evt, null)
        return evt.effect
    }

    // Moves the drag to the window under `screenPos` and returns the effect that window commits to.
    //
    // The platform layer calls this for both the first notification of a gesture and every later
    // move: entering and leaving are derived here, so a window is told exactly once when the
    // pointer arrives and exactly once when it goes. `screenPos` is in physical screen pixels,
    // like every other position crossing the platform boundary.
    internal mtd dragUpdate(screenPos: Math.Point, data: *DragData, allowed: DropEffect, modifiers: Input.KeyModifiers)->DropEffect
    {
        return .dragUpdateTo(skipDisabled(.windowAt(screenPos)), screenPos, data, allowed, modifiers)
    }

    // Same, for a target already resolved. A harness driving a gesture without a desktop under it
    // says which window the pointer is over instead of hit-testing a surface it never registered.
    internal mtd dragUpdateTo(target: #null *Wnd, screenPos: Math.Point, data: *DragData, allowed: DropEffect, modifiers: Input.KeyModifiers)->DropEffect
    {
        .dragScreenPos = screenPos

        if target != .dragEnterWnd
        {
            if .dragEnterWnd do
                discard .sendDragEvent(.dragEnterWnd, .Leave, screenPos, data, .None, modifiers)
            .dragEnterWnd = target
            if target do
                discard .sendDragEvent(target, .Enter, screenPos, data, allowed, modifiers)
        }

        if !target do
            return .None

        return .sendDragEvent(target, .Over, screenPos, data, allowed, modifiers)
    }

    // Ends the gesture without a drop, telling the window the pointer was over that it left.
    internal mtd dragLeave(data: *DragData)
    {
        let target = .dragEnterWnd
        .dragEnterWnd = null
        if !target do
            return

        discard .sendDragEvent(target, .Leave, .dragScreenPos, data, .None, Input.KeyModifiers.None)
    }

    // Releases the payload over the window under `screenPos` and returns the effect it performed.
    //
    // The window is told the gesture left it whatever it answers, so a drop highlight is cleared
    // by the same path as a cancelled drag.
    internal mtd dragDrop(screenPos: Math.Point, data: *DragData, allowed: DropEffect, modifiers: Input.KeyModifiers)->DropEffect
    {
        return .dragDropTo(skipDisabled(.windowAt(screenPos)), screenPos, data, allowed, modifiers)
    }

    // Same, for a target already resolved. See [[Gui.Application.dragUpdateTo]].
    internal mtd dragDropTo(target: #null *Wnd, screenPos: Math.Point, data: *DragData, allowed: DropEffect, modifiers: Input.KeyModifiers)->DropEffect
    {
        .dragScreenPos = screenPos

        if .dragEnterWnd and .dragEnterWnd != target do
            discard .sendDragEvent(.dragEnterWnd, .Leave, screenPos, data, .None, modifiers)
        .dragEnterWnd = null

        if !target do
            return .None

        let effect = .sendDragEvent(target, .Drop, screenPos, data, allowed, modifiers)
        discard .sendDragEvent(target, .Leave, screenPos, data, .None, modifiers)
        return effect
    }
}
