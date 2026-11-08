#global if #command == Swag.CompilerCommand.Test
#global private

using ExportApi

#test
{
    discard rejectWhere'u64(1)     // swc-expected-error {{sema_err_function_where_failed}}
}
