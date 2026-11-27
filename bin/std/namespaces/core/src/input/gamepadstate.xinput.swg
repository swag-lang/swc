#global if WINDOWS
#global namespace Input

using Win32, Win32.XInput, Core.Errors

private func rawButtons(buttons: u16)->RawGamepadButtons
{
    var result: #returntype
    if buttons & XINPUT_GAMEPAD_A
    {
        result |= .A
    }

    if buttons & XINPUT_GAMEPAD_B
    {
        result |= .B
    }

    if buttons & XINPUT_GAMEPAD_X
    {
        result |= .X
    }

    if buttons & XINPUT_GAMEPAD_Y
    {
        result |= .Y
    }

    if buttons & XINPUT_GAMEPAD_LEFT_THUMB
    {
        result |= .LeftStick
    }

    if buttons & XINPUT_GAMEPAD_RIGHT_THUMB
    {
        result |= .RightStick
    }

    if buttons & XINPUT_GAMEPAD_START
    {
        result |= .Start
    }

    if buttons & XINPUT_GAMEPAD_BACK
    {
        result |= .Back
    }

    if buttons & XINPUT_GAMEPAD_LEFT_SHOULDER
    {
        result |= .LeftShoulder
    }

    if buttons & XINPUT_GAMEPAD_RIGHT_SHOULDER
    {
        result |= .RightShoulder
    }

    if buttons & XINPUT_GAMEPAD_DPAD_UP
    {
        result |= .DPadUp
    }

    if buttons & XINPUT_GAMEPAD_DPAD_DOWN
    {
        result |= .DPadDown
    }

    if buttons & XINPUT_GAMEPAD_DPAD_LEFT
    {
        result |= .DPadLeft
    }

    if buttons & XINPUT_GAMEPAD_DPAD_RIGHT
    {
        result |= .DPadRight
    }

    return result
}

func readRawGamepadState(padIndex: u32)->RawGamepadState fail
{
    var state: XINPUT_STATE
    let status = XInputGetState(padIndex, &state)
    switch status
    {
    case ERROR_SUCCESS: break
    case ERROR_DEVICE_NOT_CONNECTED: fail Swag.SystemError{"not connected"}
    default: try Win32.failWinError(status)
    }

    return RawGamepadState{rawButtons(state.Gamepad.wButtons),
                           state.Gamepad.sThumbLX,
                           state.Gamepad.sThumbLY,
                           state.Gamepad.sThumbRX,
                           state.Gamepad.sThumbRY,
                           state.Gamepad.bLeftTrigger,
                           state.Gamepad.bRightTrigger}
}
