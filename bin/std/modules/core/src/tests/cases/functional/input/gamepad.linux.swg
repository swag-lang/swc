#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

#[Swag.TestTag("input.evdev")]
#test
{
    var axis = Linux.input_absinfo{minimum: Swag.S32.Min, maximum: Swag.S32.Max}
    axis.value = Swag.S32.Min
    Swag.require(Input.normalizeEvdevAxis(axis, 65535) == 0)
    Swag.require(Input.normalizeEvdevAxis(axis, 65535, true) == 65535)
    axis.value = Swag.S32.Max
    Swag.require(Input.normalizeEvdevAxis(axis, 65535) == 65535)
    Swag.require(Input.normalizeEvdevAxis(axis, 65535, true) == 0)
    axis = {minimum: 10, maximum: 110, value: 60}
    Swag.require(Input.normalizeEvdevAxis(axis, 255) == 127)
    axis.value = -100
    Swag.require(Input.normalizeEvdevAxis(axis, 255) == 0)
    axis.value = 200
    Swag.require(Input.normalizeEvdevAxis(axis, 255) == 255)
    axis.maximum = axis.minimum
    Swag.require(Input.normalizeEvdevAxis(axis, 65535) == 0)
}

#[Swag.TestTag("integration.input")]
#test
{
    Swag.require(not Input.Gamepad.isConnected(Swag.U32.Max))
    var state:   Input.GamepadState
    var outcome: Swag.Error
    catch state.update(Swag.U32.Max) as outcome
    Swag.require(outcome.value() != null)
    var vibration: Swag.Error
    catch Input.Gamepad.setVibration(Swag.U32.Max, 0, 0) as vibration
    Swag.require(vibration.value() != null)
}
