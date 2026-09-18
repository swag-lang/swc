#global if WINDOWS
#global namespace Input

using XInput, Win32

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
    // Speeds range from 0 to 1 and are clamped to that range. Fails when no gamepad is
    // connected at `padIndex`.
    func setVibration(padIndex: u32, left, right: f32) fail
    {
        var vibration: XINPUT_VIBRATION
        vibration.wLeftMotorSpeed  = cast(WORD) (0xFFFF * Math.saturate(left))
        vibration.wRightMotorSpeed = cast(WORD) (0xFFFF * Math.saturate(right))
        let res = XInputSetState(padIndex, &vibration)
        switch res
        {
        case ERROR_SUCCESS: return
        case ERROR_DEVICE_NOT_CONNECTED: fail Swag.SystemError{"not connected"}
        default: try Win32.failWinError(res)
        }
    }
}
