#global if WINDOWS
#global namespace Input

using Win32, Win32.XInput

public impl Gamepad
{
    // Returns whether a gamepad is connected at `padIndex`.
    func isConnected(padIndex: u32)->bool
    {
        var state: XINPUT_STATE
        return XInputGetState(padIndex, &state) == ERROR_SUCCESS
    }

    // Sets the speeds of the left and right vibration motors of the gamepad at `padIndex`.
    //
    // Speeds must be finite and are clamped to 0 through 1. Fails when no gamepad is connected
    // at `padIndex`.
    func setVibration(padIndex: u32, left, right: f32) fail
    {
        try validateGamepadVibrationSpeeds(left, right)
        var vibration: XINPUT_VIBRATION
        vibration.wLeftMotorSpeed  = cast(WORD, (0xFFFF * Math.saturate(left)))
        vibration.wRightMotorSpeed = cast(WORD, (0xFFFF * Math.saturate(right)))
        let res = XInputSetState(padIndex, &vibration)
        switch res
        {
        case ERROR_SUCCESS: return
        case ERROR_DEVICE_NOT_CONNECTED: fail Swag.SystemError{"not connected"}
        default: try Win32.failWinError(res)
        }
    }
}
