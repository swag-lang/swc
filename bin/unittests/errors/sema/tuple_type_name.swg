#global private

func tupleTypeName()->{value: s32, eat: u32, ovf: bool} => {1, 2, false}
func tupleTypeTake(_: s32) {}

func tupleTypeMismatch()
{
    tupleTypeTake(tupleTypeName())     // swc-expected-error {{argument 1 for call to 'tupleTypeTake' has type '{value: s32, eat: u32, ovf: bool}', but the parameter needs 's32'}}
}
