#global public
#global namespace XInput

#foreignlib("xinput")

using Swag

const XINPUT_GAMEPAD_DPAD_UP        = 0x0001_u16
const XINPUT_GAMEPAD_DPAD_DOWN      = 0x0002_u16
const XINPUT_GAMEPAD_DPAD_LEFT      = 0x0004_u16
const XINPUT_GAMEPAD_DPAD_RIGHT     = 0x0008_u16
const XINPUT_GAMEPAD_START          = 0x0010_u16
const XINPUT_GAMEPAD_BACK           = 0x0020_u16
const XINPUT_GAMEPAD_LEFT_THUMB     = 0x0040_u16
const XINPUT_GAMEPAD_RIGHT_THUMB    = 0x0080_u16
const XINPUT_GAMEPAD_LEFT_SHOULDER  = 0x0100_u16
const XINPUT_GAMEPAD_RIGHT_SHOULDER = 0x0200_u16
const XINPUT_GAMEPAD_A              = 0x1000_u16
const XINPUT_GAMEPAD_B              = 0x2000_u16
const XINPUT_GAMEPAD_X              = 0x4000_u16
const XINPUT_GAMEPAD_Y              = 0x8000_u16

struct XINPUT_GAMEPAD
{
    public
    {
        wButtons:      WORD
        bLeftTrigger:  BYTE
        bRightTrigger: BYTE
        sThumbLX:      SHORT
        sThumbLY:      SHORT
        sThumbRX:      SHORT
        sThumbRY:      SHORT
    }
}

struct XINPUT_STATE
{
    public
    {
        dwPacketNumber: DWORD
        Gamepad:        XINPUT_GAMEPAD
    }
}

struct XINPUT_VIBRATION
{
    public
    {
        wLeftMotorSpeed:  WORD
        wRightMotorSpeed: WORD
    }
}

#assert(#sizeof(XINPUT_GAMEPAD) == 12)
#assert(#sizeof(XINPUT_STATE) == 16)
#assert(#sizeof(XINPUT_VIBRATION) == 4)

#[Foreign(module: "xinput1_4", link: "xinput", callconv: Swag.CallConv.C)]
{
    func XInputGetState(dwUserIndex: DWORD, pState: *XINPUT_STATE)->DWORD
    func XInputSetState(dwUserIndex: DWORD, pVibration: *XINPUT_VIBRATION)->DWORD
}
