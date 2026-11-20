using Core

// A missing record uses the registered bindings. A record with no key disables them.
internal struct ShortcutOverride
{
    command:   String
    modifiers: Input.KeyModifiers
    key:       Input.Key
    source:    bool
}

internal func shortcutOverride(bindings: const [..] ShortcutOverride, id: WndId)->const *ShortcutOverride?
{
    for &binding in bindings where binding.command == id do
        return binding
    return null
}

internal func setShortcutOverride(bindings: *Array'ShortcutOverride, id: WndId, modifiers: Input.KeyModifiers, key: Input.Key, source = false)
{
    for &binding in bindings[] where binding.command == id
    {
        binding.modifiers = modifiers
        binding.key       = key
        binding.source    = source
        return
    }
    bindings.add({command: id, modifiers: modifiers, key: key, source: source})
}

internal func resetShortcutOverride(bindings: *Array'ShortcutOverride, id: WndId)
{
    for binding, index in bindings[] where binding.command == id
    {
        bindings.removeAtOrdered(index)
        return
    }
}

internal func sameChord(a, b: KeyShortcut)->bool => a.key == b.key and a.modifiers == b.modifiers

internal func hasShortcutChord(shortcuts: const [..] KeyShortcut, shortcut: KeyShortcut)->bool
{
    for existing in shortcuts where sameChord(existing, shortcut) do
        return true
    return false
}

internal func effectiveShortcuts(defaults: const [..] KeyShortcut, bindings: const [..] ShortcutOverride,
                                 result: *Array'KeyShortcut)
{
    for shortcut in defaults where not shortcutOverride(bindings, shortcut.id) do
        result.add(shortcut)
    for &binding in bindings where binding.key != .None
    {
        for shortcut in defaults where shortcut.id == binding.command
        {
            result.add({binding.modifiers, binding.key, shortcut.id, shortcut.target})
            break
        }
    }
}

public impl Application
{
    // Registers a default system-wide shortcut that can be changed from Keyboard Shortcuts.
    //
    // Register these once per command and target. Multiple defaults may route to the same
    // command. A saved binding replaces all its defaults, and an explicitly cleared binding
    // registers nothing. A native registration failure leaves the default in the options.
    mtd registerUserHotKey(modifiers: Input.KeyModifiers, key: Input.Key, id: WndId, target: *Wnd) fail
    {
        let configured = shortcutOverride(.shortcutOverrides.toSlice(), id)
        var alreadyRegistered = false
        for shortcut in .defaultUserHotKeys where shortcut.id == id and shortcut.target == target
        {
            if shortcut.modifiers == modifiers and shortcut.key == key do
                return
            alreadyRegistered = true
        }

        .defaultUserHotKeys.add({modifiers, key, id, target})
        var chord = KeyShortcut{modifiers, key, id, target}
        if configured
        {
            if alreadyRegistered or configured.key == .None do
                return
            chord.modifiers = configured.modifiers
            chord.key       = configured.key
        }
        for current in .hotKeys where sameChord(chord, current)
        {
            if current.id == id and current.target == target do
                return
            fail shortcutUnavailable(chord)
        }
        try .registerHotKey(chord.modifiers, chord.key, id, target)
    }

    // Lists the configured system-wide shortcuts that the application could not register.
    mtd unavailableUserHotKeys()->Array'String
    {
        var wanted: Array'KeyShortcut
        effectiveShortcuts(.defaultUserHotKeys.toSlice(), .shortcutOverrides.toSlice(), &wanted)
        var result: #returntype
        for shortcut in wanted
        {
            let active = .hotKeyShortcut(shortcut.modifiers, shortcut.key)
            if active.id != shortcut.id or active.wnd != shortcut.target do
                result.add(Input.formatKeyShortcut(shortcut.modifiers, shortcut.key))
        }
        return result
    }

    internal mtd notifyShortcutsChanged()
    {
        for surface in .surfaces where surface.wnd.view != null
        {
            surface.wnd.view.notifyEvent(.ShortcutsChanged)
            surface.wnd.view.invalidate()
        }
    }

    internal mtd isUserHotKey(id: WndId)->bool
    {
        for shortcut in .defaultUserHotKeys where shortcut.id == id do
            return true
        return false
    }

    internal mtd retireUserHotKeys(wnd: *Wnd)
    {
        for index in reversed(.defaultUserHotKeys.count) where .defaultUserHotKeys[index].target == wnd do
            .defaultUserHotKeys.removeAtOrdered(index)
    }

    internal mtd restoreShortcuts(bindings: Array'ShortcutOverride)
    {
        catch .updateShortcuts(bindings, persist: false)
    }

    internal mtd routeCustomizedShortcut(target: *Wnd, key: const *KeyEvent)->bool
    {
        if .shortcutOverrides.isEmpty() or target is EditBox do
            return false
        let overrides = .shortcutOverrides.toSlice()
        var hasSources, matchesLocal: bool
        for &binding in overrides
        {
            if binding.source do
                hasSources = true
            elif binding.key == key.key and binding.modifiers == key.modifiers and not .isUserHotKey(binding.command) do
                matchesLocal = true
        }

        var replacesDefault: bool
        var lens: *Lens.View?
        var node: *Wnd? = target
        while node
        {
            if hasSources and not lens and node.shortcutLens and not node.shortcutLens.isPendingDestroy do
                lens = node.shortcutLens
            for chord in node.keyShortcuts where chord.key == key.key and chord.modifiers == key.modifiers
            {
                if shortcutOverride(overrides, chord.id) do
                    replacesDefault = true
            }
            node = node.ownerOrParent()
        }
        if lens and lens.routeSourceShortcut(target, key) do
            return true
        if matchesLocal or replacesDefault
        {
            if let id = target.keyShortcut(key.modifiers, key.key)
            {
                target.sendCommandEvent(id)
                return true
            }
        }
        return replacesDefault
    }

    // Keep existing claims until new chords and the preference file have both succeeded.
    internal mtd updateShortcuts(bindings: Array'ShortcutOverride, persist = true) fail
    {
        var previous, wanted: Array'KeyShortcut
        effectiveShortcuts(.defaultUserHotKeys.toSlice(), .shortcutOverrides.toSlice(), &previous)
        effectiveShortcuts(.defaultUserHotKeys.toSlice(), bindings.toSlice(), &wanted)

        var active, claimed: Array'KeyShortcut
        var committed = false
        defer
        {
            if not committed
            {
                for shortcut in claimed do
                    unregisterNativeHotKey(shortcut.modifiers, shortcut.key)
            }
        }

        for shortcut in .hotKeys where not .isUserHotKey(shortcut.id) do
            active.add(shortcut)

        for shortcut in wanted
        {
            if hasShortcutChord(active.toSlice(), shortcut)
            {
                if persist do
                    fail shortcutUnavailable(shortcut)
                continue
            }

            if not .hotKeysDisabled and not hasShortcutChord(.hotKeys.toSlice(), shortcut)
            {
                catch registerNativeHotKey(shortcut.modifiers, shortcut.key)
                {
                    // An existing unavailable chord does not block an unrelated edit.
                    if persist and not hasShortcutChord(previous.toSlice(), shortcut) do
                        fail shortcutUnavailable(shortcut)
                    continue
                }
                claimed.add(shortcut)
            }
            active.add(shortcut)
        }

        let old = .shortcutOverrides
        .shortcutOverrides = bindings
        if persist
        {
            catch .saveState()
            {
                .shortcutOverrides = old
                fail Swag.err
            }
        }

        if not .hotKeysDisabled
        {
            for shortcut in .hotKeys where not hasShortcutChord(active.toSlice(), shortcut) do
                unregisterNativeHotKey(shortcut.modifiers, shortcut.key)
        }
        .hotKeys   = #move active
        committed = true
        .notifyShortcutsChanged()
    }
}

private func shortcutUnavailable(chord: KeyShortcut)->Errors.InvalidFormatError
{
    let name = Input.formatKeyShortcut(chord.modifiers, chord.key)
    return {Format.toString(strings().shortcuts_Unavailable, name).toString()}
}
