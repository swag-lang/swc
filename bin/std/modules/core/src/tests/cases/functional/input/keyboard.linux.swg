#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

// Canonical keys must reach portable controls and shortcuts rather than their legacy aliases.
#test
{
    let screenshot = Input.Keyboard.keyToVirtualKey(.PrintScreen)
    Swag.require(screenshot == 0xFF61)
    Swag.require(Input.Keyboard.virtualKeyToKey(screenshot) == .PrintScreen)
    Swag.require(Input.Keyboard.virtualKeyToKey(Input.Keyboard.keyToVirtualKey(.Print)) == .PrintScreen)
    Swag.require(Input.Keyboard.virtualKeyToKey('a') == .A)
    Swag.require(Input.Keyboard.virtualKeyToKey(0) == .None)
    Swag.require(Input.Keyboard.virtualKeyToKey(0xFF0D) == .Return)
    Swag.require(Input.Keyboard.virtualKeyToKey(0xFF56) == .PageDown)
    Swag.require(Input.Keyboard.virtualKeyToKey(0xFFE5) == .CapsLock)
}

// Keypad navigation and Enter share the portable commands of their main-keyboard counterparts.
#test
{
    let symbols = [0xFF80'u32, 0xFF89, 0xFF8D, 0xFF91, 0xFF92, 0xFF93, 0xFF94,
                   0xFF95, 0xFF96, 0xFF97, 0xFF98, 0xFF99, 0xFF9A, 0xFF9B, 0xFF9C,
                   0xFF9D, 0xFF9E, 0xFF9F, 0xFFBD]
    let expected: const [..]Input.Key = [.Space, .Tab, .Return, .F1, .F2, .F3, .F4,
                                         .Home, .Left, .Up, .Right, .Down, .PageUp, .PageDown, .End,
                                         .Clear, .Insert, .Delete, .OemPlus]
    for index in symbols.count do
        Swag.require(Input.Keyboard.virtualKeyToKey(symbols[index]) == expected[index])
    for index in 10 do
        Swag.require(Input.Keyboard.virtualKeyToKey(0xFFB0 + cast(u32, index)) == cast(Input.Key, cast(u32, Input.Key.NumPad0) + cast(u32, index)))
}
