#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

// Canonical keys must reach portable controls and shortcuts rather than their legacy aliases.
#test
{
    let screenshot = Input.Keyboard.keyToVirtualKey(.PrintScreen)
    Swag.assert(screenshot == 0xFF61)
    Swag.assert(Input.Keyboard.virtualKeyToKey(screenshot) == .PrintScreen)
    Swag.assert(Input.Keyboard.virtualKeyToKey(Input.Keyboard.keyToVirtualKey(.Print)) == .PrintScreen)
    Swag.assert(Input.Keyboard.virtualKeyToKey('a') == .A)
    Swag.assert(Input.Keyboard.virtualKeyToKey(0) == .None)
    Swag.assert(Input.Keyboard.virtualKeyToKey(0xFF0D) == .Return)
    Swag.assert(Input.Keyboard.virtualKeyToKey(0xFF56) == .PageDown)
    Swag.assert(Input.Keyboard.virtualKeyToKey(0xFFE5) == .CapsLock)
}
