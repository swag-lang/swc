#global if #os == Swag.TargetOs.Linux
#global namespace Input

// Stores the X11 snapshot embedded by KeyboardState; use Keyboard for portable queries.
//
// The core X11 protocol provides the first three mouse buttons only. Extra mouse buttons
// are reported released. Keyboard, mapping and pointer requests are separate snapshots.
public struct KeyboardStateNative
{
    internal
    {
        nativePressed: [Key]bool
        nativeRunes:   [Key]rune
    }
}

private func keysymRune(symbol: u32)->rune
{
    if (symbol >= 0x20 and symbol <= 0x7E) or (symbol >= 0xA0 and symbol <= 0xFF) do
        return cast(rune, symbol)
    if symbol >= 0x01000100 and symbol <= 0x0110FFFF
    {
        let code = symbol - 0x01000000
        if code < 0xD800 or code > 0xDFFF do
            return cast(rune, code)
    }

    if symbol >= 0xFFB0 and symbol <= 0xFFB9 do
        return cast(rune, symbol - 0xFFB0 + '0')
    switch symbol
    {
    case 0xFFAA: return '*'
    case 0xFFAB: return '+'
    case 0xFFAC: return ','
    case 0xFFAD: return '-'
    case 0xFFAE: return '.'
    case 0xFFAF: return '/'
    default:     return 0'rune
    }
}

impl KeyboardStateNative
{
    internal mtd updateNative()
    {
        Memory.clear(&.nativePressed, #sizeof(.nativePressed))
        Memory.clear(&.nativeRunes, #sizeof(.nativeRunes))
        let context    = catch LinuxDesktop.ensure() { return; }
        let connection = unwrap context.connection
        let setup      = context.xcb_get_setup(connection)
        let count      = cast(u32, setup.max_keycode) - setup.min_keycode + 1
        if count > 255 do
            return
        let keys = context.xcb_query_keymap_reply(connection, context.xcb_query_keymap(connection), null)
        if not keys do
            return
        defer Linux.free(keys)
        let mapping = context.xcb_get_keyboard_mapping_reply(connection,
                                                             context.xcb_get_keyboard_mapping(connection, setup.min_keycode, cast(u8, count)),
                                                             null)
        if not mapping do
            return
        defer Linux.free(mapping)
        let columns = mapping.keysyms_per_keycode
        let length  = context.xcb_get_keyboard_mapping_keysyms_length(mapping)
        if columns == 0 or length < 0 or cast(u32, length) < count * columns do
            return
        let symbols = context.xcb_get_keyboard_mapping_keysyms(mapping)
        var mask: u16
        let pointer = context.xcb_query_pointer_reply(connection, context.xcb_query_pointer(connection, context.screen.root), null)
        if pointer
        {
            mask = pointer.mask
            Linux.free(pointer)
        }

        for key in Key
        {
            let wanted = Keyboard.keyToVirtualKey(key)
            if wanted == 0 do
                continue
            for index in 0 until count
            {
                let offset = index * columns
                let base   = symbols[offset]
                if base != wanted do
                    continue
                let code = index + setup.min_keycode
                if (keys.keys[code / 8] & (1 << (code % 8))) != 0 do
                    .nativePressed[key] = true
                let shifted = columns > 1 ? symbols[offset + 1] : 0'u32
                var symbol  = (mask & 1) and shifted != 0 ? shifted : base
                if base >= 'a' and base <= 'z'
                {
                    let upper = ((mask & 1) != 0) != ((mask & 2) != 0)
                    symbol = upper ? base - 'a' + 'A' : base
                }

                .nativeRunes[key] = keysymRune(symbol)
            }
        }

        .nativePressed[.Shift]    = .nativePressed[.LShift] or .nativePressed[.RShift]
        .nativePressed[.Control]  = .nativePressed[.LControl] or .nativePressed[.RControl]
        .nativePressed[.MenuCtrl] = .nativePressed[.LMenu] or .nativePressed[.RMenu]
        .nativePressed[.LButton]  = (mask & (1 << 8)) != 0
        .nativePressed[.MButton]  = (mask & (1 << 9)) != 0
        .nativePressed[.RButton]  = (mask & (1 << 10)) != 0
    }

    internal mtd isKeyPressed(key: Key)->bool => .nativePressed[key]
}
