#global namespace Input

// Platform virtual-key code, as returned by [[Core.Input.Keyboard.keyToVirtualKey]].
public alias VirtualKey = u32

// Combines keyboard modifiers used by shortcuts and input events.
#[Swag.EnumFlags]
public enum KeyModifiers
{
    None = 0                        // No modifier is active.
    Shift                           // Either Shift key.
    Control                         // Either Control key.
    Alt                             // Either Alt key.
    CtrlShift = Control | Shift     // Control and Shift.
    CtrlAlt   = Control | Alt       // Control and Alt.
}

// Identifies a keyboard key, or a mouse button tested through the keyboard state.
public enum Key
{
    None                   // No key
    A                      // A key
    Add                    // Numeric keypad plus key
    Apps                   // Application menu key
    Attn                   // Attn key
    B                      // B key
    Back                   // Backspace key
    BrowserBack            // Browser Back key
    BrowserFavorites       // Browser Favorites key
    BrowserForward         // Browser Forward key
    BrowserHome            // Browser Home key
    BrowserRefresh         // Browser Refresh key
    BrowserSearch          // Browser Search key
    BrowserStop            // Browser Stop key
    C                      // C key
    Cancel                 // Break key
    Capital                // Caps Lock key, same as `CapsLock`
    CapsLock               // Caps Lock key
    Clear                  // Clear key
    Control                // Control key
    Crsel                  // CrSel key
    D                      // D key
    D0                     // Digit 0 key of the main keyboard
    D1                     // Digit 1 key of the main keyboard
    D2                     // Digit 2 key of the main keyboard
    D3                     // Digit 3 key of the main keyboard
    D4                     // Digit 4 key of the main keyboard
    D5                     // Digit 5 key of the main keyboard
    D6                     // Digit 6 key of the main keyboard
    D7                     // Digit 7 key of the main keyboard
    D8                     // Digit 8 key of the main keyboard
    D9                     // Digit 9 key of the main keyboard
    Decimal                // Numeric keypad decimal key
    Delete                 // Delete key
    Divide                 // Numeric keypad divide key
    Down                   // Down arrow key
    E                      // E key
    End                    // End key
    Enter                  // Enter key
    EraseEof               // Erase EOF key
    Escape                 // Escape key
    Execute                // Execute key
    Exsel                  // ExSel key
    F                      // F key
    F1                     // F1 key
    F10                    // F10 key
    F11                    // F11 key
    F12                    // F12 key
    F13                    // F13 key
    F14                    // F14 key
    F15                    // F15 key
    F16                    // F16 key
    F17                    // F17 key
    F18                    // F18 key
    F19                    // F19 key
    F2                     // F2 key
    F20                    // F20 key
    F21                    // F21 key
    F22                    // F22 key
    F23                    // F23 key
    F24                    // F24 key
    F3                     // F3 key
    F4                     // F4 key
    F5                     // F5 key
    F6                     // F6 key
    F7                     // F7 key
    F8                     // F8 key
    F9                     // F9 key
    FinalMode              // IME final mode key
    G                      // G key
    H                      // H key
    HangulMode             // IME Hangul mode key
    HanjaMode              // IME Hanja mode key
    Help                   // Help key
    Home                   // Home key
    I                      // I key
    ImeAccept              // IME accept key
    ImeConvert             // IME convert key
    ImeModeChange          // IME mode change key
    ImeNonConvert          // IME nonconvert key
    Insert                 // Insert key
    J                      // J key
    JunjaMode              // IME Junja mode key
    K                      // K key
    KanaMode               // IME Kana mode key
    KanjiMode              // IME Kanji mode key
    L                      // L key
    LButton                // Left mouse button
    LControl               // Left Control key
    LMenu                  // Left Alt key
    LShift                 // Left Shift key
    LWin                   // Left Windows key
    LaunchApplication1     // Start Application 1 key
    LaunchApplication2     // Start Application 2 key
    LaunchMail             // Start Mail key
    Left                   // Left arrow key
    LineFeed               // Line feed key
    M                      // M key
    MButton                // Middle mouse button
    MediaNextTrack         // Next Track media key
    MediaPlayPause         // Play/Pause media key
    MediaPreviousTrack     // Previous Track media key
    MediaStop              // Stop media key
    MenuCtrl               // Alt key
    Multiply               // Numeric keypad multiply key
    N                      // N key
    Next                   // Page Down key, same as `PageDown`
    NoName                 // Reserved key
    NumLock                // Num Lock key
    NumPad0                // Numeric keypad 0 key
    NumPad1                // Numeric keypad 1 key
    NumPad2                // Numeric keypad 2 key
    NumPad3                // Numeric keypad 3 key
    NumPad4                // Numeric keypad 4 key
    NumPad5                // Numeric keypad 5 key
    NumPad6                // Numeric keypad 6 key
    NumPad7                // Numeric keypad 7 key
    NumPad8                // Numeric keypad 8 key
    NumPad9                // Numeric keypad 9 key
    O                      // O key
    Oem1                   // Semicolon key on a US keyboard
    Oem102                 // Angle bracket or backslash key on a 102-key keyboard
    Oem2                   // Slash key on a US keyboard
    Oem3                   // Grave accent key on a US keyboard
    Oem4                   // Left bracket key on a US keyboard
    Oem5                   // Backslash key on a US keyboard
    Oem6                   // Right bracket key on a US keyboard
    Oem7                   // Quote key on a US keyboard
    Oem8                   // Layout-specific key
    OemBackslash           // Same as `Oem102`
    OemClear               // Clear key
    OemCloseBrackets       // Same as `Oem6`
    OemComma               // Comma key of any layout
    OemMinus               // Minus key of any layout
    OemOpenBrackets        // Same as `Oem4`
    OemPeriod              // Period key of any layout
    OemPipe                // Same as `Oem5`
    OemPlus                // Plus key of any layout
    OemQuestion            // Same as `Oem2`
    OemQuotes              // Same as `Oem7`
    OemSemicolon           // Same as `Oem1`
    OemTilde               // Same as `Oem3`
    P                      // P key
    Pa1                    // PA1 key
    Packet                 // Unicode character packet
    PageDown               // Page Down key
    PageUp                 // Page Up key
    Pause                  // Pause key
    Play                   // Play key
    Print                  // Print key
    PrintScreen            // Print Screen key
    Prior                  // Page Up key, same as `PageUp`
    Process                // IME process key
    Q                      // Q key
    R                      // R key
    RButton                // Right mouse button
    RControl               // Right Control key
    RMenu                  // Right Alt key
    RShift                 // Right Shift key
    RWin                   // Right Windows key
    Return                 // Enter key, same as `Enter`
    Right                  // Right arrow key
    S                      // S key
    Scroll                 // Scroll Lock key
    Select                 // Select key
    SelectMedia            // Select Media key
    Separator              // Numeric keypad separator key
    Shift                  // Shift key
    Sleep                  // Sleep key
    Space                  // Spacebar
    Subtract               // Numeric keypad minus key
    T                      // T key
    Tab                    // Tab key
    U                      // U key
    Up                     // Up arrow key
    V                      // V key
    VolumeDown             // Volume Down key
    VolumeMute             // Volume Mute key
    VolumeUp               // Volume Up key
    W                      // W key
    X                      // X key
    XButton1               // First extra mouse button
    XButton2               // Second extra mouse button
    Y                      // Y key
    Z                      // Z key
    Zoom                   // Zoom key
}

// Formats `modifiers` and `key` as a display-ready shortcut such as `Ctrl+S`.
public func formatKeyShortcut(modifiers: KeyModifiers, key: Key)->String
{
    var result: retval

    if modifiers & .Alt do
        result += "Alt"

    if modifiers & .Control
    {
        if not result.isEmpty() do
            result += "+"
        result += "Ctrl"
    }

    if modifiers & .Shift
    {
        if not result.isEmpty() do
            result += "+"
        result += "Shift"
    }

    if not result.isEmpty() do
        result += "+"

    var k = key
    switch key
    {
    case .NumPad0:  result += "0"
    case .NumPad1:  result += "1"
    case .NumPad2:  result += "2"
    case .NumPad3:  result += "3"
    case .NumPad4:  result += "4"
    case .NumPad5:  result += "5"
    case .NumPad6:  result += "6"
    case .NumPad7:  result += "7"
    case .NumPad8:  result += "8"
    case .NumPad9:  result += "9"
    case .Add:      result += "+"
    case .Subtract: result += "-"
    default:        result += Reflection.enumName(Input.Key, &k, fullyQualified: false)
    }

    return result
}
