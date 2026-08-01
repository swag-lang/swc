#global if WINDOWS
#global public
#global namespace Input

using XInput, Win32, Core.Errors

#run
{
    using GamepadState, GamepadButton
    mapButtons[Math.trailingZeros(XINPUT_GAMEPAD_A)]              = A
    mapButtons[Math.trailingZeros(XINPUT_GAMEPAD_B)]              = B
    mapButtons[Math.trailingZeros(XINPUT_GAMEPAD_X)]              = X
    mapButtons[Math.trailingZeros(XINPUT_GAMEPAD_Y)]              = Y
    mapButtons[Math.trailingZeros(XINPUT_GAMEPAD_LEFT_THUMB)]     = LeftStick
    mapButtons[Math.trailingZeros(XINPUT_GAMEPAD_RIGHT_THUMB)]    = RightStick
    mapButtons[Math.trailingZeros(XINPUT_GAMEPAD_START)]          = Start
    mapButtons[Math.trailingZeros(XINPUT_GAMEPAD_BACK)]           = Back
    mapButtons[Math.trailingZeros(XINPUT_GAMEPAD_LEFT_SHOULDER)]  = LeftShoulder
    mapButtons[Math.trailingZeros(XINPUT_GAMEPAD_RIGHT_SHOULDER)] = RightShoulder
    mapButtons[Math.trailingZeros(XINPUT_GAMEPAD_DPAD_UP)]        = DPadUp
    mapButtons[Math.trailingZeros(XINPUT_GAMEPAD_DPAD_DOWN)]      = DPadDown
    mapButtons[Math.trailingZeros(XINPUT_GAMEPAD_DPAD_LEFT)]      = DPadLeft
    mapButtons[Math.trailingZeros(XINPUT_GAMEPAD_DPAD_RIGHT)]     = DPadRight
}

impl GamepadState
{
    private var mapButtons: [16] GamepadButton = undefined

    // Compute the current state of the given pad index
    mtd update(padIndex: u32) fail
    {
        var state: XINPUT_STATE = undefined
        let res                 = XInputGetState(padIndex, &state)
        switch res
        {
        case ERROR_SUCCESS:              break
        case ERROR_DEVICE_NOT_CONNECTED: fail Swag.SystemError{"not connected"}
        default:                         Win32.failWinError(res)
        }

        // Gamepad button state
        for [i] in 16'u16 do
            .pressed[mapButtons[i]] = state.Gamepad.wButtons & cast(u16) (1 << i)

        // Move
        using GamepadButton
        .position[LeftStick].x    = state.Gamepad.sThumbLX / 32767.0'f32
        .position[LeftStick].y    = state.Gamepad.sThumbLY / 32767.0'f32
        .position[RightStick].x   = state.Gamepad.sThumbRX / 32767.0'f32
        .position[RightStick].y   = state.Gamepad.sThumbRY / 32767.0'f32
        .position[LeftTrigger].y  = state.Gamepad.bLeftTrigger / 255.0'f32
        .position[RightTrigger].y = state.Gamepad.bRightTrigger / 255.0'f32

        // Simulate pressed with #move
        #[Swag.Inline]
        mtd activationThreshold(button: GamepadButton)->f32
        {
            const SmallToler = 0.7'f32
            const BigToler   = 0.9'f32
            return .pressed[button] ? SmallToler : BigToler
        }

        .pressed[LeftThumbstickDown]  = .position[LeftStick].y < -activationThreshold(me, LeftThumbstickDown)
        .pressed[LeftThumbstickUp]    = .position[LeftStick].y > activationThreshold(me, LeftThumbstickUp)
        .pressed[LeftThumbstickLeft]  = .position[LeftStick].x < -activationThreshold(me, LeftThumbstickLeft)
        .pressed[LeftThumbstickRight] = .position[LeftStick].x > activationThreshold(me, LeftThumbstickRight)

        .pressed[RightThumbstickDown]  = .position[RightStick].y < -activationThreshold(me, RightThumbstickDown)
        .pressed[RightThumbstickUp]    = .position[RightStick].y > activationThreshold(me, RightThumbstickUp)
        .pressed[RightThumbstickLeft]  = .position[RightStick].x < -activationThreshold(me, RightThumbstickLeft)
        .pressed[RightThumbstickRight] = .position[RightStick].x > activationThreshold(me, RightThumbstickRight)

        .pressed[LeftTrigger]  = .position[LeftTrigger].y > activationThreshold(me, LeftTrigger)
        .pressed[RightTrigger] = .position[RightTrigger].y > activationThreshold(me, RightTrigger)
    }
}
