#global if #os == Swag.TargetOs.Linux
#global namespace Input

public impl Keyboard
{
    // Returns the canonical X11 keysym of key, or zero for an unmapped key.
    //
    // This is a layout symbol, not an X11 hardware keycode. Generic modifier aliases and
    // mouse buttons have no keysym; use the state query for those keys.
    func keyToVirtualKey(key: Key)->VirtualKey
    {
        switch key
        {
        case .A:                       return 0x61
        case .B:                       return 0x62
        case .C:                       return 0x63
        case .D:                       return 0x64
        case .E:                       return 0x65
        case .F:                       return 0x66
        case .G:                       return 0x67
        case .H:                       return 0x68
        case .I:                       return 0x69
        case .J:                       return 0x6A
        case .K:                       return 0x6B
        case .L:                       return 0x6C
        case .M:                       return 0x6D
        case .N:                       return 0x6E
        case .O:                       return 0x6F
        case .P:                       return 0x70
        case .Q:                       return 0x71
        case .R:                       return 0x72
        case .S:                       return 0x73
        case .T:                       return 0x74
        case .U:                       return 0x75
        case .V:                       return 0x76
        case .W:                       return 0x77
        case .X:                       return 0x78
        case .Y:                       return 0x79
        case .Z:                       return 0x7A
        case .D0:                      return 0x30
        case .D1:                      return 0x31
        case .D2:                      return 0x32
        case .D3:                      return 0x33
        case .D4:                      return 0x34
        case .D5:                      return 0x35
        case .D6:                      return 0x36
        case .D7:                      return 0x37
        case .D8:                      return 0x38
        case .D9:                      return 0x39
        case .F1:                      return 0xFFBE
        case .F2:                      return 0xFFBF
        case .F3:                      return 0xFFC0
        case .F4:                      return 0xFFC1
        case .F5:                      return 0xFFC2
        case .F6:                      return 0xFFC3
        case .F7:                      return 0xFFC4
        case .F8:                      return 0xFFC5
        case .F9:                      return 0xFFC6
        case .F10:                     return 0xFFC7
        case .F11:                     return 0xFFC8
        case .F12:                     return 0xFFC9
        case .F13:                     return 0xFFCA
        case .F14:                     return 0xFFCB
        case .F15:                     return 0xFFCC
        case .F16:                     return 0xFFCD
        case .F17:                     return 0xFFCE
        case .F18:                     return 0xFFCF
        case .F19:                     return 0xFFD0
        case .F20:                     return 0xFFD1
        case .F21:                     return 0xFFD2
        case .F22:                     return 0xFFD3
        case .F23:                     return 0xFFD4
        case .F24:                     return 0xFFD5
        case .NumPad0:                 return 0xFFB0
        case .NumPad1:                 return 0xFFB1
        case .NumPad2:                 return 0xFFB2
        case .NumPad3:                 return 0xFFB3
        case .NumPad4:                 return 0xFFB4
        case .NumPad5:                 return 0xFFB5
        case .NumPad6:                 return 0xFFB6
        case .NumPad7:                 return 0xFFB7
        case .NumPad8:                 return 0xFFB8
        case .NumPad9:                 return 0xFFB9
        case .Back:                    return 0xFF08
        case .Tab:                     return 0xFF09
        case .LineFeed:                return 0xFF0A
        case .Clear:                   return 0xFF0B
        case .Enter, .Return:          return 0xFF0D
        case .Pause:                   return 0xFF13
        case .Scroll:                  return 0xFF14
        case .Escape:                  return 0xFF1B
        case .Delete:                  return 0xFFFF
        case .Home:                    return 0xFF50
        case .Left:                    return 0xFF51
        case .Up:                      return 0xFF52
        case .Right:                   return 0xFF53
        case .Down:                    return 0xFF54
        case .PageUp, .Prior:          return 0xFF55
        case .PageDown, .Next:         return 0xFF56
        case .End:                     return 0xFF57
        case .Select:                  return 0xFF60
        case .Print, .PrintScreen:     return 0xFF61
        case .Execute:                 return 0xFF62
        case .Insert:                  return 0xFF63
        case .Apps:                    return 0xFF67
        case .Help:                    return 0xFF6A
        case .Cancel:                  return 0xFF69
        case .NumLock:                 return 0xFF7F
        case .Space:                   return 0x20
        case .LShift:                  return 0xFFE1
        case .RShift:                  return 0xFFE2
        case .LControl:                return 0xFFE3
        case .RControl:                return 0xFFE4
        case .Capital, .CapsLock:      return 0xFFE5
        case .LMenu:                   return 0xFFE9
        case .RMenu:                   return 0xFFEA
        case .LWin:                    return 0xFFEB
        case .RWin:                    return 0xFFEC
        case .Multiply:                return 0xFFAA
        case .Add:                     return 0xFFAB
        case .Separator:               return 0xFFAC
        case .Subtract:                return 0xFFAD
        case .Decimal:                 return 0xFFAE
        case .Divide:                  return 0xFFAF
        case .Oem1, .OemSemicolon:     return 0x3B
        case .OemPlus:                 return 0x3D
        case .OemComma:                return 0x2C
        case .OemMinus:                return 0x2D
        case .OemPeriod:               return 0x2E
        case .Oem2, .OemQuestion:      return 0x2F
        case .Oem3, .OemTilde:         return 0x60
        case .Oem4, .OemOpenBrackets:  return 0x5B
        case .Oem5, .OemPipe:          return 0x5C
        case .Oem6, .OemCloseBrackets: return 0x5D
        case .Oem7, .OemQuotes:        return 0x27
        case .Oem102, .OemBackslash:   return 0x3C
        default:                       return 0
        }
    }

    // Returns the canonical portable key for an X11 keysym, or None.
    //
    // Return, PageDown, PrintScreen, and CapsLock are preferred over their historical
    // aliases. Keypad navigation and Enter map to the matching portable commands.
    // Other aliases choose the first portable key with the same keysym.
    func virtualKeyToKey(vkey: VirtualKey)->Key
    {
        switch vkey
        {
        case 0xFF0D, 0xFF8D: return .Return
        case 0xFF56:         return .PageDown
        case 0xFF61:         return .PrintScreen
        case 0xFFE5:         return .CapsLock
        case 0xFF80:         return .Space
        case 0xFF89:         return .Tab
        case 0xFF91:         return .F1
        case 0xFF92:         return .F2
        case 0xFF93:         return .F3
        case 0xFF94:         return .F4
        case 0xFF95:         return .Home
        case 0xFF96:         return .Left
        case 0xFF97:         return .Up
        case 0xFF98:         return .Right
        case 0xFF99:         return .Down
        case 0xFF9A:         return .PageUp
        case 0xFF9B:         return .PageDown
        case 0xFF9C:         return .End
        case 0xFF9D:         return .Clear
        case 0xFF9E:         return .Insert
        case 0xFF9F:         return .Delete
        case 0xFFBD:         return .OemPlus
        }

        if vkey != 0
        {
            for key in Key where keyToVirtualKey(key) == vkey do
                return key
        }

        return .None
    }

    // Queries the current X11 key/button state; unavailable keys or display return false.
    //
    // Only the first three pointer buttons are supported by this core-protocol adapter.
    func isKeyPressed(key: Key)->bool
    {
        var snapshot: KeyboardStateNative
        snapshot.updateNative()
        return snapshot.isKeyPressed(key)
    }

    // Returns the simple X11 character captured by the latest update, or zero.
    //
    // Handles Latin-1, Unicode keysyms and Shift/Caps Lock in the first keyboard group,
    // including standard PC keypad digits or navigation according to NumLock and Shift.
    // This is not text composition: dead keys, compose sequences, legacy non-Latin
    // keysyms, additional groups, and IME text must use a future text-input adapter.
    mtd keyToRune(key: Key)->rune => .currentState.native.nativeRunes[key]
}
