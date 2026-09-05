#global private

#test
{
    #assert(s32 is s32)     // swc-expected-error {{sema_err_type_is_needs_interface}}
}
