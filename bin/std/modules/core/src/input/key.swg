#global namespace Input

// Represents a virtual system key
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

// Defines the keys on a keyboard
public enum Key
{
    None                   // No option is selected.
    A                      // Selects a.
    Add                    // Selects add.
    Apps                   // Selects apps.
    Attn                   // Selects attn.
    B                      // Selects b.
    Back                   // Selects back.
    BrowserBack            // Selects browser back.
    BrowserFavorites       // Selects browser favorites.
    BrowserForward         // Selects browser forward.
    BrowserHome            // Selects browser home.
    BrowserRefresh         // Selects browser refresh.
    BrowserSearch          // Selects browser search.
    BrowserStop            // Selects browser stop.
    C                      // Selects c.
    Cancel                 // Selects cancel.
    Capital                // Selects capital.
    CapsLock               // Selects caps lock.
    Clear                  // Selects clear.
    Control                // Selects control.
    Crsel                  // Selects crsel.
    D                      // Selects d.
    D0                     // Selects d0.
    D1                     // Selects d1.
    D2                     // Selects d2.
    D3                     // Selects d3.
    D4                     // Selects d4.
    D5                     // Selects d5.
    D6                     // Selects d6.
    D7                     // Selects d7.
    D8                     // Selects d8.
    D9                     // Selects d9.
    Decimal                // Selects decimal.
    Delete                 // Selects delete.
    Divide                 // Selects divide.
    Down                   // Selects down.
    E                      // Selects e.
    End                    // Selects end.
    Enter                  // Selects enter.
    EraseEof               // Selects erase eof.
    Escape                 // Selects escape.
    Execute                // Selects execute.
    Exsel                  // Selects exsel.
    F                      // Selects f.
    F1                     // Selects f1.
    F10                    // Selects f10.
    F11                    // Selects f11.
    F12                    // Selects f12.
    F13                    // Selects f13.
    F14                    // Selects f14.
    F15                    // Selects f15.
    F16                    // Selects f16.
    F17                    // Selects f17.
    F18                    // Selects f18.
    F19                    // Selects f19.
    F2                     // Selects f2.
    F20                    // Selects f20.
    F21                    // Selects f21.
    F22                    // Selects f22.
    F23                    // Selects f23.
    F24                    // Selects f24.
    F3                     // Selects f3.
    F4                     // Selects f4.
    F5                     // Selects f5.
    F6                     // Selects f6.
    F7                     // Selects f7.
    F8                     // Selects f8.
    F9                     // Selects f9.
    FinalMode              // Selects final mode.
    G                      // Selects g.
    H                      // Selects h.
    HangulMode             // Selects hangul mode.
    HanjaMode              // Selects hanja mode.
    Help                   // Selects help.
    Home                   // Selects home.
    I                      // Selects i.
    ImeAccept              // Selects IME input acceptance.
    ImeConvert             // Selects IME conversion.
    ImeModeChange          // Selects an IME mode change.
    ImeNonConvert          // Selects IME input without conversion.
    Insert                 // Selects insert.
    J                      // Selects j.
    JunjaMode              // Selects junja mode.
    K                      // Selects k.
    KanaMode               // Selects kana mode.
    KanjiMode              // Selects kanji mode.
    L                      // Selects l.
    LButton                // Selects l button.
    LControl               // Selects l control.
    LMenu                  // Selects l menu.
    LShift                 // Selects l shift.
    LWin                   // Selects l win.
    LaunchApplication1     // Selects launch application1.
    LaunchApplication2     // Selects launch application2.
    LaunchMail             // Selects launch mail.
    Left                   // Selects left.
    LineFeed               // Selects line feed.
    M                      // Selects m.
    MButton                // Selects m button.
    MediaNextTrack         // Selects media next track.
    MediaPlayPause         // Selects media play pause.
    MediaPreviousTrack     // Selects media previous track.
    MediaStop              // Selects media stop.
    MenuCtrl               // Selects menu ctrl.
    Multiply               // Selects multiply.
    N                      // Selects n.
    Next                   // Selects next.
    NoName                 // Selects no name.
    NumLock                // Selects num lock.
    NumPad0                // Selects num pad0.
    NumPad1                // Selects num pad1.
    NumPad2                // Selects num pad2.
    NumPad3                // Selects num pad3.
    NumPad4                // Selects num pad4.
    NumPad5                // Selects num pad5.
    NumPad6                // Selects num pad6.
    NumPad7                // Selects num pad7.
    NumPad8                // Selects num pad8.
    NumPad9                // Selects num pad9.
    O                      // Selects o.
    Oem1                   // Selects oem1.
    Oem102                 // Selects oem102.
    Oem2                   // Selects oem2.
    Oem3                   // Selects oem3.
    Oem4                   // Selects oem4.
    Oem5                   // Selects oem5.
    Oem6                   // Selects oem6.
    Oem7                   // Selects oem7.
    Oem8                   // Selects oem8.
    OemBackslash           // Selects oem backslash.
    OemClear               // Selects oem clear.
    OemCloseBrackets       // Selects oem close brackets.
    OemComma               // Selects oem comma.
    OemMinus               // Selects oem minus.
    OemOpenBrackets        // Selects oem open brackets.
    OemPeriod              // Selects oem period.
    OemPipe                // Selects oem pipe.
    OemPlus                // Selects oem plus.
    OemQuestion            // Selects oem question.
    OemQuotes              // Selects oem quotes.
    OemSemicolon           // Selects oem semicolon.
    OemTilde               // Selects oem tilde.
    P                      // Selects p.
    Pa1                    // Selects pa1.
    Packet                 // Selects packet.
    PageDown               // Selects page down.
    PageUp                 // Selects page up.
    Pause                  // Selects pause.
    Play                   // Selects play.
    Print                  // Selects print.
    PrintScreen            // Selects print screen.
    Prior                  // Selects prior.
    Process                // Selects process.
    Q                      // Selects q.
    R                      // Selects r.
    RButton                // Selects r button.
    RControl               // Selects r control.
    RMenu                  // Selects r menu.
    RShift                 // Selects r shift.
    RWin                   // Selects r win.
    Return                 // Selects return.
    Right                  // Selects right.
    S                      // Selects s.
    Scroll                 // Selects scroll.
    Select                 // Selects select.
    SelectMedia            // Selects select media.
    Separator              // Selects separator.
    Shift                  // Selects shift.
    Sleep                  // Selects sleep.
    Space                  // Selects space.
    Subtract               // Selects subtract.
    T                      // Selects t.
    Tab                    // Selects tab.
    U                      // Selects u.
    Up                     // Selects up.
    V                      // Selects v.
    VolumeDown             // Selects volume down.
    VolumeMute             // Selects volume mute.
    VolumeUp               // Selects volume up.
    W                      // Selects w.
    X                      // Selects x.
    XButton1               // Selects x button1.
    XButton2               // Selects x button2.
    Y                      // Selects y.
    Z                      // Selects z.
    Zoom                   // Selects zoom.
}

// Formats `modifiers` and `key` as a display-ready shortcut such as `Ctrl+S`.
public func formatKeyShortcut(modifiers: KeyModifiers, key: Key)->String
{
    var result: retval

    if modifiers & .Alt do
        result += "Alt"

    if modifiers & .Control
    {
        if result.length do
            result += "+"
        result += "Ctrl"
    }

    if modifiers & .Shift
    {
        if result.length do
            result += "+"
        result += "Shift"
    }

    if result.length do
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
