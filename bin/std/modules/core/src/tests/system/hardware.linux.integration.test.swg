#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

#[Swag.TestTag("integration.hardware")]
#test
{
    let processors = Hardware.processorCount()
    Swag.assert(processors >= 1)

    // A machine without a six-byte network address legitimately returns zero.
    let address = Hardware.macAddress()
    Swag.assert(address >> 48 == 0)
}
