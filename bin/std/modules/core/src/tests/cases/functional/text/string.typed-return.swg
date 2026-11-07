#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func typedReturnMake()->String
{
    var result: String = "dock0"
    return result
}

func typedReturnProbe()->bool
{
    var fromCall: String = typedReturnMake()
    return fromCall == "dock0" and fromCall.toString() == "dock0"
}

func inferredReturnProbe()->bool
{
    var fromCall = typedReturnMake()
    return fromCall == "dock0" and fromCall.toString() == "dock0"
}

#test
{
    Swag.require(inferredReturnProbe())
    Swag.require(typedReturnProbe())

    let fromCall: String = typedReturnMake()
    Swag.require(fromCall == "dock0")

    var fromCopy: String = fromCall
    Swag.require(fromCopy == "dock0")

    let fromFormat: String = Format.toString("dock%", 0)
    Swag.require(fromFormat == "dock0")
    Swag.require(fromFormat.toString() == "dock0")
}
