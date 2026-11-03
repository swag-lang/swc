// The two typography choices of the editor share one popup: a list of fonts with a search field,
// or a short list of sizes. Both lists use the toolkit's selection, scrolling and focus behavior.
const TextChoicePadding      = 8.0
const TextChoiceFilterHeight = 32.0
const TextChoiceFilterGap    = 8.0
const TextChoiceRowHeight    = 28.0
const TextChoiceListInset    = 16.0
const TextChoiceFaceRows     = 8'u64
const TextChoiceSizeRows     = 10'u64
const TextChoiceFaceWidth    = 256.0
const TextChoiceSizeWidth    = 112.0

// Common sizes are direct choices; the property grid keeps the complete numeric range.
const TextChoiceSizes = [12'u32, 16, 24, 32, 40, 48, 72, 96, 120, 150]

// Installed faces are enumerated only when the font popup first opens.
var g_MiniBarFonts: Array'SystemFontFamilyInfo

enum TextChoiceKind
{
    Face
    Size
}

struct TextChoicePopover
{
    using wnd: Wnd

    late main:   *MainWnd
    late button: *IconButton
    late list:   *ListCtrl
    filter:      *EditBox?
    kind:        TextChoiceKind
    values:      Array'u32     // Each visible row's font index, or its numeric size.
    refreshing:  bool
}

impl TextChoicePopover
{
    func heightForRows(kind: TextChoiceKind, count: u64)->f32
    {
        let header = kind == .Face ? TextChoiceFilterHeight + TextChoiceFilterGap : 0.0
        let rows   = Math.max(1'u64, Math.min(count, kind == .Face ? TextChoiceFaceRows : TextChoiceSizeRows))
        return 2 * TextChoicePadding + header + cast(f32, rows) * TextChoiceRowHeight + TextChoiceListInset
    }

    // Opens the same list surface for both properties. The font version reserves its first row
    // for a real edit box, so typing filters without changing the text being edited on the canvas.
    func open(main: *MainWnd, button: *IconButton, kind: TextChoiceKind)->*TextChoicePopover
    {
        if kind == .Face and g_MiniBarFonts.isEmpty() do
            g_MiniBarFonts = FontFamily.enumerateSystemFonts()

        let width = kind == .Face ? TextChoiceFaceWidth : TextChoiceSizeWidth
        let count = kind == .Face ? g_MiniBarFonts.count + 1 : TextChoiceSizes.count
        let frame = button.createAnchorPopup(width, heightForRows(kind, count))
        with let result = Wnd.create'TextChoicePopover(frame, {})
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
            .main            = main
            .button          = button
            .kind            = kind
        }

        result.build(width, frame.position.height)
        return result
    }

    // Composes standard controls inside the anchored popup, with one list treatment in both cases.
    mtd build(width, height: f32)
    {
        var listTop = TextChoicePadding
        if .kind == .Face
        {
            with .filter = EditBox.create(me, "", {TextChoicePadding, TextChoicePadding, width - 2 * TextChoicePadding, TextChoiceFilterHeight})
            {
                .setPlaceholder(appStrings().ui_Search)
                .sigTextChanged += func|popover = me|(_) { popover.fill() }
                .hookOnEvent = func|popover = me|(_, evt)->bool => popover.filterKey(evt)
            }
            listTop += TextChoiceFilterHeight + TextChoiceFilterGap
        }

        with .list = ListCtrl.createSimple(me, {TextChoicePadding, listTop, width - 2 * TextChoicePadding, height - listTop - TextChoicePadding})
        {
            .setFrameForm(.Transparent)
            .setLineHeight(TextChoiceRowHeight)
            .setFirstColumnIconMargin(false)
            .updateFlags(add: .HotTrack | .PreserveSelectionOnEmptyClick)
            .sigSelectionChanged += func|popover = me|(_) { popover.chooseSelected() }
            .sigKeyPressed += func|popover = me|(_, key) { popover.listKey(key) }
        }
        if .kind == .Face do
            .list.setEmptyText(appStrings().ui_NoMatchingFonts)

        .fill()
        if .filter do
            .filter.setFocus()
        else
        {
            .list.setFocus()
            if .list.lineCount() do
                .list.setFocusedIndex(0)
        }
    }

    // Rebuilds the visible rows from a case-insensitive substring; the current face keeps its
    // selection mark whenever it survives the filter.
    mtd fill()
    {
        .refreshing = true
        defer .refreshing = false
        .list.clear()
        .values.clear()

        let style = .main.selectedTextStyle()
        if not style.found do
            return
        var chosen = Swag.U32.Max

        if .kind == .Face
        {
            var query: String
            if .filter do
                query = String.from(.filter.text()).toLower(.Unicode)

            let defaultFace = .theme().res.defaultTypeFaceR.familyName()
            let defaultLower = String.from(defaultFace).toLower(.Unicode)
            if query.isEmpty() or Utf8.contains(defaultLower.toString(), query.toString())
            {
                chosen = style.face.count == 0 or style.face == defaultFace ? 0 : Swag.U32.Max
                .list.createLine(defaultFace)
                .values.add(Swag.U32.Max)
            }

            for &font, index in g_MiniBarFonts where font.name != defaultFace
            {
                let name = font.name.toString()
                let lower = String.from(name).toLower(.Unicode)
                if not query.isEmpty() and not Utf8.contains(lower.toString(), query.toString()) do
                    continue
                if style.face == name do
                    chosen = cast(u32, .values.count)
                .list.createLine(name)
                .values.add(cast(u32, index))
            }
        }
        else
        {
            for size in TextChoiceSizes
            {
                if Math.abs(style.size - cast(f32, size)) < 0.01 do
                    chosen = cast(u32, .values.count)
                .list.createLine(Format.toString("%", size))
                .values.add(size)
            }
        }

        .fitHeight()
        .list.computeLayout()
        if chosen < .list.lineCount() do
            .list.selectLine(chosen)
    }

    // Keep a filtered list close to its rows. When the popup opened above the button, its bottom
    // edge remains attached as it shrinks; a popup below keeps its top edge.
    mtd fitHeight()
    {
        let frame  = assume cast(*FrameWnd, unwrap .parent)
        let old    = frame.position
        let height = heightForRows(.kind, .values.count)
        if height == old.height do
            return

        let above = frame.surfaceRect().bottom() <= .button.surfaceRect().y
        let y     = above ? old.y + old.height - height : old.y
        frame.setPosition({old.x, y, old.width, height})
        .list.resize(.list.position.width, height - .list.position.y - TextChoicePadding)
    }

    // A click chooses at once; keyboard movement only changes the focused row until Enter.
    mtd chooseSelected()
    {
        if .refreshing do
            return
        let line = .list.selectedLine() orelse .list.focusedLine()
        if line do
            .choose(line.index)
    }

    mtd choose(index: u32)
    {
        if index >= .values.count do
            return
        let style = .main.selectedTextStyle()
        if not style.found do
            return

        let value = .values[index]
        if .kind == .Face
        {
            let face = value == Swag.U32.Max ? "" : g_MiniBarFonts[value].name.toString()
            .main.setSelectedFace(face)
        }
        else
        {
            let size = cast(f32, value)
            .main.propWnd.pushTypedValue(cast #bit (u32, size), style.type, #nameof(FormText.fontSize), true)
        }
        .button.hidePopup()
    }

    // The search field keeps typing focus; Down moves into the results, Return picks the first.
    mtd filterKey(evt: IEvent)->bool
    {
        let key = catch cast(*KeyEvent?, evt)
        if not key or key.kind != .Pressed do
            return false
        switch key.key
        {
        case .Escape: .button.hidePopup()
        case .Down:   .focusFirst()
        case .Return: if .values.count do .choose(0)
        default:      return false
        }
        key.accepted = true
        return true
    }

    mtd focusFirst()
    {
        if not .list.lineCount() do
            return
        .list.setFocus()
        .list.setFocusedIndex(0)
    }

    // The list's ordinary arrow keys also select rows, so intercept them and move only focus.
    mtd listKey(key: *KeyEvent)
    {
        if key.kind != .Pressed do
            return
        let count   = .list.lineCount()
        let focused = .list.focusedLine()
        switch key.key
        {
        case .Escape: .button.hidePopup()
        case .Return, .Enter, .Space:
            if focused do
                .choose(focused.index)
        case .Home, .End, .Up, .Down:
            if count
            {
                var index = focused ? focused.index : 0'u32
                switch key.key
                {
                case .Home: index = 0
                case .End:  index = count - 1
                case .Up:   if index > 0 do index -= 1
                case .Down: if index + 1 < count do index += 1
                }
                .list.setFocusedIndex(index)
            }
        default: return
        }
        key.accepted = true
    }
}
