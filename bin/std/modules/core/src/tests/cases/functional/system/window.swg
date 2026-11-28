#global if #command == Swag.CompilerCommand.Test
#global private

#test
{
    var window:  Env.Window
    var outcome: Swag.Error
    catch window.setPosition(10, 20) as outcome
    Swag.require(outcome.value() is Errors.BadParameterError)
    catch window.hide() as outcome
    Swag.require(outcome.value() is Errors.BadParameterError)
    catch window.requestFocus() as outcome
    Swag.require(outcome.value() is Errors.BadParameterError)
    Swag.require(not window.isOpen())
}
