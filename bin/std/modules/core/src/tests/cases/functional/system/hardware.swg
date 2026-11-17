#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// Hardware reports at least one usable logical processor, including its fallback path.
#test
{
    Swag.require(Hardware.processorCount() > 0)
}
