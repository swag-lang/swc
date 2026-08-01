#global if WINDOWS
#global namespace Input

using Win32

// Stores the platform keyboard snapshot embedded by [[Core.Input.KeyboardState]].
//
// This type is public only because it participates in the cross-platform
// representation of `KeyboardState`; callers should use `Keyboard` queries.
public struct KeyboardStateNative
{
    nativeState: [256] BYTE     // Platform key-state bytes; use [[Core.Input.Keyboard]] for portable queries.
}

impl KeyboardStateNative
{
    mtd updateNative()
    {
        discard GetKeyboardState(.nativeState)
    }

    mtd isKeyPressed(key: Input.Key)->bool
    {
        let vkey = Keyboard.mapKeyToVKey[key]
        if vkey == 0 do
            return false
        return .nativeState[vkey] & 0x80 ? true : false
    }
}
