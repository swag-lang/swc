#global if WINDOWS
#global namespace Input

using XInput, Win32, Core.Errors

private func rawButtons(buttons: u16)->RawGamepadButtons
{
    var result: retval
    if buttons & XINPUT_GAMEPAD_A do
        result |= .A
    if buttons & XINPUT_GAMEPAD_B do
        result |= .B
    if buttons & XINPUT_GAMEPAD_X do
        result |= .X
    if buttons & XINPUT_GAMEPAD_Y do
        result |= .Y
    if buttons & XINPUT_GAMEPAD_LEFT_THUMB do
        result |= .LeftStick
    if buttons & XINPUT_GAMEPAD_RIGHT_THUMB do
        result |= .RightStick
    if buttons & XINPUT_GAMEPAD_START do
        result |= .Start
    if buttons & XINPUT_GAMEPAD_BACK do
        result |= .Back
    if buttons & XINPUT_GAMEPAD_LEFT_SHOULDER do
        result |= .LeftShoulder
    if buttons & XINPUT_GAMEPAD_RIGHT_SHOULDER do
        result |= .RightShoulder
    if buttons & XINPUT_GAMEPAD_DPAD_UP do
        result |= .DPadUp
    if buttons & XINPUT_GAMEPAD_DPAD_DOWN do
        result |= .DPadDown
    if buttons & XINPUT_GAMEPAD_DPAD_LEFT do
        result |= .DPadLeft
    if buttons & XINPUT_GAMEPAD_DPAD_RIGHT do
        result |= .DPadRight
    return result
}

func readRawGamepadState(padIndex: u32)->RawGamepadState fail
{
    var state: XINPUT_STATE
    let status = XInputGetState(padIndex, &state)
    switch status
    {
    case ERROR_SUCCESS:              break
    case ERROR_DEVICE_NOT_CONNECTED: fail Swag.SystemError{"not connected"}
    default:                         Win32.failWinError(status)
    }

    return {rawButtons(state.Gamepad.wButtons),
            state.Gamepad.sThumbLX,
            state.Gamepad.sThumbLY,
            state.Gamepad.sThumbRX,
            state.Gamepad.sThumbRY,
            state.Gamepad.bLeftTrigger,
            state.Gamepad.bRightTrigger}
}
