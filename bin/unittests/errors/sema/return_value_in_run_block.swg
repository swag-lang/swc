#global private

// A '#run' block is compiled as a generated function: returning a value from it is reported
// against the block, never under the generated name.

func runBlockReturn()->s32
{
    #run
    {
        return 1     // swc-expected-error {{a '#run' block cannot return a value; [help] remove the value, or compute it with a '#run' expression instead}}
    }

    return 0
}
