#global public

using Core, Pixel

// Edits a password without storing its plaintext in a regular text backing store.
//
// The private child edit box contains only one mask character per rune. Plaintext bytes stay in
// fixed-capacity storage, clipboard shortcuts are disabled, and destruction clears the storage.
struct PasswordEdit
{
    using wnd: Wnd     // Embedded window behavior and presentation.

    sigChanged:   SigArray'func||(*PasswordEdit)     // Emitted after the password changes.
    sigSubmitted: SigArray'func||(*PasswordEdit)     // Emitted when Enter is pressed.
    sigCancelled: SigArray'func||(*PasswordEdit)     // Emitted when Escape is pressed.

    internal
    #[Swag.Late]
    edit:      *EditBox      // Mask-only child owned by this control.
    storage:   [1024] u8     // Fixed storage avoids reallocating plaintext through a general allocator.
    byteCount: u64           // Number of occupied plaintext bytes.
    runeCount: u64           // Number of entered Unicode code points.
}

private impl PasswordEdit
{
    mtd byteOffsetAt(runeIndex: u64)->u64
    {
        var byteOffset = 0'u64
        for [i] in runeIndex
        {
            discard i
            let {?, eat} = Utf8.decodeRune(.storage[byteOffset until .byteCount])
            byteOffset += eat
        }

        return byteOffset
    }

    mtd refresh(caret: u64)
    {
        var mask: Array'u8
        mask.resize(.runeCount)
        if mask.count do
            @memset(mask.buffer, '*', mask.count)
        .edit.setText(mask.count ? @mkstring(mask.buffer, mask.count) : "", false)
        .edit.setSelection(caret, caret)
    }

    mtd eraseRunes(start, end: u64)
    {
        if start >= end do
            return

        let firstByte  = .byteOffsetAt(start)
        let endByte    = .byteOffsetAt(end)
        let removeSize = endByte - firstByte
        let tailSize   = .byteCount - endByte
        if tailSize do
            Memory.copyOverlapping(&.storage[firstByte], &.storage[endByte], tailSize)
        Crypto.secureClear(.storage[.byteCount - removeSize until .byteCount])
        .byteCount -= removeSize
        .runeCount -= end - start
    }

    mtd eraseSelection()->{ changed: bool, caret: u64 }
    {
        let start = Math.min(.edit.selBeg, .edit.selEnd)
        let end   = Math.max(.edit.selBeg, .edit.selEnd)
        if start == end do
            return {false, start}
        .eraseRunes(start, end)
        return {true, start}
    }

    mtd insertRune(value: rune)
    {
        var encoded: [4] u8
        let count = Utf8.encodeRune(encoded, value)

        let erased = .eraseSelection()
        let caret  = erased.caret
        if .byteCount + count > #sizeof(.storage)
        {
            Crypto.secureClear(encoded)
            .refresh(caret)
            if erased.changed do
                .sigChanged.call(me)
            return
        }

        let byteOffset = .byteOffsetAt(caret)
        let tailSize   = .byteCount - byteOffset
        if tailSize do
            Memory.copyOverlapping(&.storage[byteOffset + count], &.storage[byteOffset], tailSize)
        @memcpy(&.storage[byteOffset], &encoded[0], count)
        .byteCount += count
        .runeCount += 1
        Crypto.secureClear(encoded)
        .refresh(caret + 1)
        .sigChanged.call(me)
    }

    mtd eraseFromKey(key: Input.Key)
    {
        let selection = .eraseSelection()
        var changed   = selection.changed
        var caret     = selection.caret
        if !changed and key == .Back and caret
        {
            .eraseRunes(caret - 1, caret)
            caret   -= 1
            changed = true
        }
        elif !changed and key == .Delete and caret < .runeCount
        {
            .eraseRunes(caret, caret + 1)
            changed = true
        }

        if changed
        {
            .refresh(caret)
            .sigChanged.call(me)
        }
    }

    mtd handleEditEvent(wnd: *Wnd, evt: IEvent)->bool
    {
        discard wnd
        switch evt
        {
        case KeyEvent as key:
            if key.kind == .Character
            {
                if key.character >= 0x20'rune do
                    .insertRune(key.character)
                key.accepted = true
                return true
            }

            if key.kind == .Pressed and (key.key == .Back or key.key == .Delete)
            {
                .eraseFromKey(key.key)
                key.accepted = true
                return true
            }

            // Clipboard text is never imported or exported. This also prevents the child edit
            // box from changing its mask without changing the password storage.
            if key.kind == .Pressed and
               ((key.modifiers & Input.KeyModifiers.Control) and
                (key.key == .C or key.key == .X or key.key == .V or key.key == .Insert) or
                (key.modifiers & Input.KeyModifiers.Shift) and
                key.key == .Insert)
            {
                key.accepted = true
                return true
            }
        }

        return false
    }
}

impl IWnd for PasswordEdit
{
    // Keeps the private edit box fitted to this control.
    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        discard evt
        if @isset(.edit) do
            .edit.setPosition(.clientRect())
    }

    // Clears plaintext before the GUI releases the widget allocation.
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        discard evt
        Crypto.secureClear(.storage)
        .byteCount = 0
        .runeCount = 0
    }
}

public impl PasswordEdit
{
    // Maximum number of UTF-8 plaintext bytes held by one password edit.
    const MaximumByteLength = 1024

    // Creates an empty password edit with an optional command identifier.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: #null WndId = null)->*PasswordEdit
    {
        Debug.assert(parent != null)
        var pos = position
        if pos.height == 0 do
            pos.height = parent.themeMetrics().editBox_Height
        if pos.width == 0 do
            pos.width = parent.themeMetrics().editBox_Width

        let result = Wnd.create'PasswordEdit(parent, null, pos, id)
        result.focusStrategy     = .None
        result.edit              = EditBox.create(result, "", result.clientRect(), flags: .ReleaseFocusOnEnterOrEscape)
        result.edit.hookOnEvent  = func|password = result|(wnd, evt) => password.handleEditEvent(wnd, evt)
        result.edit.sigSubmitted += func|password = result|(edit)
        {
            discard edit
            password.sigSubmitted.call(password)
        }
        result.edit.sigCancelled += func|password = result|(edit)
        {
            discard edit
            password.sigCancelled.call(password)
        }
        return result
    }

    // Returns a borrowed view of the UTF-8 plaintext bytes.
    // The view remains valid until the password changes or the widget is destroyed.
    mtd const bytes()->const [..] u8 => .storage[until .byteCount]

    // Returns true when no password bytes are stored.
    mtd const isEmpty()->bool => !.byteCount

    // Gives keyboard focus to the private edit box.
    mtd setFocus() => .edit.setFocus()

    // Reports whether the private edit box owns keyboard focus.
    mtd hasFocus()->bool => .edit.hasFocus()

    // Selects the complete masked password.
    mtd selectAll() => .edit.selectAll()

    // Changes the placeholder displayed while the password is empty.
    mtd setPlaceholder(placeholder: #null string) => .edit.setPlaceholder(placeholder)

    // Changes the edit-box background and border form.
    mtd setForm(form: EditBoxForm) => .edit.setForm(form)

    // Changes the leading icon.
    mtd setIcon(icon: Icon) => .edit.setIcon(icon)

    // Clears the plaintext and visible mask, optionally emitting [[sigChanged]].
    mtd clear(notify = true)
    {
        let changed = .byteCount != 0
        Crypto.secureClear(.storage)
        .byteCount = 0
        .runeCount = 0
        .edit.setText("", false)
        if changed and notify do
            .sigChanged.call(me)
    }
}
