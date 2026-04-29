#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

func assertGamePadButton(button: Input.GamePadButton, index: u32)
{
    @assert(cast(u32) button == index)
}

#test
{
    using Input.GamePadButton

    @assert(@countof(Input.GamePadButton) == 25)

    assertGamePadButton(A, 0)
    assertGamePadButton(B, 1)
    assertGamePadButton(Back, 2)
    assertGamePadButton(BigButton, 3)
    assertGamePadButton(DPadDown, 4)
    assertGamePadButton(DPadLeft, 5)
    assertGamePadButton(DPadRight, 6)
    assertGamePadButton(DPadUp, 7)
    assertGamePadButton(LeftShoulder, 8)
    assertGamePadButton(LeftStick, 9)
    assertGamePadButton(LeftThumbstickDown, 10)
    assertGamePadButton(LeftThumbstickLeft, 11)
    assertGamePadButton(LeftThumbstickRight, 12)
    assertGamePadButton(LeftThumbstickUp, 13)
    assertGamePadButton(LeftTrigger, 14)
    assertGamePadButton(RightShoulder, 15)
    assertGamePadButton(RightStick, 16)
    assertGamePadButton(RightThumbstickDown, 17)
    assertGamePadButton(RightThumbstickLeft, 18)
    assertGamePadButton(RightThumbstickRight, 19)
    assertGamePadButton(RightThumbstickUp, 20)
    assertGamePadButton(RightTrigger, 21)
    assertGamePadButton(Start, 22)
    assertGamePadButton(X, 23)
    assertGamePadButton(Y, 24)
}
