#global private

func fallibleValue()->s32 fail
{
    return 1
}

func fallibleVoid() fail {}

func bareReturn()->s32 fail
{
    return fallibleValue()     // swc-expected-error {{sema_err_fallible_call_requires_handler}}
}

func bareStatement() fail
{
    fallibleVoid()     // swc-expected-error {{sema_err_fallible_call_requires_handler}}
}

func bareTryBlock() fail
{
    try
    {
        fallibleVoid()     // swc-expected-error {{sema_err_fallible_call_requires_handler}}
    }
}

func bareCatchBlock()
{
    catch
    {
        fallibleVoid()     // swc-expected-error {{sema_err_fallible_call_requires_handler}}
    }
}

func bareExpectBlock()
{
    expect
    {
        fallibleVoid()     // swc-expected-error {{sema_err_fallible_call_requires_handler}}
    }
}

func bareParallelBlock() fail
{
    try parallel for || index in 1
    {
        fallibleVoid()     // swc-expected-error {{sema_err_fallible_call_requires_handler}}
    }
}

struct Reader {}

impl Reader
{
    mtd read()->s32 fail { return 1 }
}

func bareMethod()->s32 fail
{
    var reader: Reader
    return reader.read()     // swc-expected-error {{sema_err_fallible_call_requires_handler}}
}

func bareCallback(callback: func()->s32 fail)->s32 fail
{
    return callback()     // swc-expected-error {{sema_err_fallible_call_requires_handler}}
}

func(T) bareGeneric(value: T)->s32 fail
{
    return fallibleValue()     // swc-expected-error {{sema_err_fallible_call_requires_handler}}
}

func instantiateBareGeneric()->s32 fail
{
    return try bareGeneric(1)
}

interface FallibleReader
{
    mtd read()->s32 fail
}

func bareInterface(reader: FallibleReader)->s32 fail
{
    return reader.read()     // swc-expected-error {{sema_err_fallible_call_requires_handler}}
}

#init
{
    fallibleVoid()     // swc-expected-error {{sema_err_fallible_call_requires_handler}}
}

#premain
{
    fallibleVoid()     // swc-expected-error {{sema_err_fallible_call_requires_handler}}
}

#drop
{
    fallibleVoid()     // swc-expected-error {{sema_err_fallible_call_requires_handler}}
}

// A differently shaped overload must not hide an error in the selected generic body.
#[Swag.Optimize(false)]
func(T) overloadedDefer(value: T) fail
{
    defer #nofail fallibleVoid()     // swc-expected-error {{sema_err_fallible_call_requires_handler}}
}

func(T) overloadedDefer(value, other: T) fail {}

func instantiateOverloadedDefer() fail
{
    try overloadedDefer(1)
}
