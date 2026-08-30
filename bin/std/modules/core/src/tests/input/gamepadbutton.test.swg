#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertGamepadButton(button: Input.GamepadButton, index: u32)
{
    Swag.assert(cast(u32) button == index)
}

#test
{
    using Input.GamepadButton

    Swag.assert(Input.GamepadButton.count == 25)

    assertGamepadButton(A, 0)
    assertGamepadButton(B, 1)
    assertGamepadButton(Back, 2)
    assertGamepadButton(BigButton, 3)
    assertGamepadButton(DPadDown, 4)
    assertGamepadButton(DPadLeft, 5)
    assertGamepadButton(DPadRight, 6)
    assertGamepadButton(DPadUp, 7)
    assertGamepadButton(LeftShoulder, 8)
    assertGamepadButton(LeftStick, 9)
    assertGamepadButton(LeftThumbstickDown, 10)
    assertGamepadButton(LeftThumbstickLeft, 11)
    assertGamepadButton(LeftThumbstickRight, 12)
    assertGamepadButton(LeftThumbstickUp, 13)
    assertGamepadButton(LeftTrigger, 14)
    assertGamepadButton(RightShoulder, 15)
    assertGamepadButton(RightStick, 16)
    assertGamepadButton(RightThumbstickDown, 17)
    assertGamepadButton(RightThumbstickLeft, 18)
    assertGamepadButton(RightThumbstickRight, 19)
    assertGamepadButton(RightThumbstickUp, 20)
    assertGamepadButton(RightTrigger, 21)
    assertGamepadButton(Start, 22)
    assertGamepadButton(X, 23)
    assertGamepadButton(Y, 24)
}
