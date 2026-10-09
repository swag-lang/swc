#global private

// A '#run' block is compiled as a generated function: returning a value from it is reported
// against the block, never under the generated name.

func runBlockReturn()->s32
{
    #run
    {
        return 1     // swc-expected-error {{sema_err_return_value_in_run_block}}
    }

    return 0
}
