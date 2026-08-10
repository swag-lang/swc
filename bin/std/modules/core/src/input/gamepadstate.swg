#global public
#global namespace Input

using Math

#[Swag.EnumFlags]
internal enum RawGamepadButtons
{
    None = 0
    A
    B
    X
    Y
    LeftStick
    RightStick
    Start
    Back
    LeftShoulder
    RightShoulder
    DPadUp
    DPadDown
    DPadLeft
    DPadRight
}

// Target-neutral raw snapshot returned by a gamepad backend.
internal struct RawGamepadState
{
    buttons:      RawGamepadButtons
    leftStickX:   s16
    leftStickY:   s16
    rightStickX:  s16
    rightStickY:  s16
    leftTrigger:  u8
    rightTrigger: u8
}

// Captures the digital and analog state of a gamepad at one update.
struct GamepadState
{
    public readonly
    {
        pressed:  [GamepadButton] bool      // Whether each button or thresholded control is active.
        position: [GamepadButton] Point     // Normalized analog positions in the range -1 through 1.
    }
}

impl GamepadState
{
    private func normalizedStick(value: s16)->f32
    {
        return Math.max(cast(f32) value / 32767.0'f32, -1.0'f32)
    }

    private mtd activationThreshold(button: GamepadButton)->f32
    {
        return .pressed[button] ? 0.7'f32 : 0.9'f32
    }

    internal mtd update(raw: RawGamepadState)
    {
        using GamepadButton
        .pressed[A]             = raw.buttons.has(.A)
        .pressed[B]             = raw.buttons.has(.B)
        .pressed[X]             = raw.buttons.has(.X)
        .pressed[Y]             = raw.buttons.has(.Y)
        .pressed[LeftStick]     = raw.buttons.has(.LeftStick)
        .pressed[RightStick]    = raw.buttons.has(.RightStick)
        .pressed[Start]         = raw.buttons.has(.Start)
        .pressed[Back]          = raw.buttons.has(.Back)
        .pressed[LeftShoulder]  = raw.buttons.has(.LeftShoulder)
        .pressed[RightShoulder] = raw.buttons.has(.RightShoulder)
        .pressed[DPadUp]        = raw.buttons.has(.DPadUp)
        .pressed[DPadDown]      = raw.buttons.has(.DPadDown)
        .pressed[DPadLeft]      = raw.buttons.has(.DPadLeft)
        .pressed[DPadRight]     = raw.buttons.has(.DPadRight)

        .position[LeftStick]      = {normalizedStick(raw.leftStickX), normalizedStick(raw.leftStickY)}
        .position[RightStick]     = {normalizedStick(raw.rightStickX), normalizedStick(raw.rightStickY)}
        .position[LeftTrigger].y  = raw.leftTrigger / 255.0'f32
        .position[RightTrigger].y = raw.rightTrigger / 255.0'f32

        .pressed[LeftThumbstickDown]   = .position[LeftStick].y < -activationThreshold(me, LeftThumbstickDown)
        .pressed[LeftThumbstickUp]     = .position[LeftStick].y > .activationThreshold(LeftThumbstickUp)
        .pressed[LeftThumbstickLeft]   = .position[LeftStick].x < -activationThreshold(me, LeftThumbstickLeft)
        .pressed[LeftThumbstickRight]  = .position[LeftStick].x > .activationThreshold(LeftThumbstickRight)
        .pressed[RightThumbstickDown]  = .position[RightStick].y < -activationThreshold(me, RightThumbstickDown)
        .pressed[RightThumbstickUp]    = .position[RightStick].y > .activationThreshold(RightThumbstickUp)
        .pressed[RightThumbstickLeft]  = .position[RightStick].x < -activationThreshold(me, RightThumbstickLeft)
        .pressed[RightThumbstickRight] = .position[RightStick].x > .activationThreshold(RightThumbstickRight)
        .pressed[LeftTrigger]          = .position[LeftTrigger].y > .activationThreshold(LeftTrigger)
        .pressed[RightTrigger]         = .position[RightTrigger].y > .activationThreshold(RightTrigger)
    }

    // Refreshes this state from one backend snapshot.
    mtd update(padIndex: u32) fail
    {
        .update(readRawGamepadState(padIndex))
    }

    internal mtd setPressed(button: GamepadButton, pressed: bool)
    {
        .pressed[button] = pressed
    }

    internal mtd setPosition(control: GamepadButton, position: Point)
    {
        .position[control] = position
    }

    // Reset state to its default value
    mtd clear()
    {
        Memory.clear(&.pressed, #sizeof(.pressed))
        Memory.clear(&.position, #sizeof(.position))
    }
}
