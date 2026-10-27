#global private

interface IItfScalar is s32     // swc-expected-error {{sema_err_interface_base_not_struct}}
{
    mtd value()->s32
}
