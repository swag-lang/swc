#global if #command == Swag.CompilerCommand.Test
#global private

using FwdProvider

#test
{
    var value = MoveOnly{9}
    storeMoveOnly(value) // swc-expected-error {{sema_err_no_overload_match}}
}
