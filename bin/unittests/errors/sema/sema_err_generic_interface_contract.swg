#global private

interface IValue
{
    mtd value()->s32
}

func(T) readValue(value: *T)->s32
    where T is IValue     // swc-expected-note {{the constraint 'where T is IValue' is declared here}}
{
    let view: IValue = value
    return view.value()
}

struct Missing {}

struct Present {}

impl IValue for Present
{
    mtd value()->s32 => 42
}

#test
{
    var value: Missing
    discard readValue(&value)     // swc-expected-error {{sema_err_function_where_failed}}
}

#test
{
    var value: Present
    discard readValue(&value)
    discard readValue'Present(&value)
}

struct(T) ValueHolder
    where T is IValue     // swc-expected-note {{the constraint 'where T is IValue' is declared here}}
{
    value: T
}

#test
{
    var holder: ValueHolder'Missing     // swc-expected-error {{sema_err_generic_struct_where_failed}}
}

func(T) overloaded(value: *T)->s32
    where T is IValue     // swc-expected-note {{the constraint 'where T is IValue' is declared here}}
{
    let view: IValue = value
    return view.value()
}

func overloaded(value: bool)->s32 => 0

#test
{
    var value: Missing
    discard overloaded(&value)     // swc-expected-error {{sema_err_generic_function_instantiation_failed}}
}

func(T) rejectedCall(value: T)
    where accepts(T)     // swc-expected-note {{the constraint 'where accepts(T)' is declared here}}
{}

#[Swag.ConstExpr]
func accepts(type: typeinfo)->bool => false

#test
{
    rejectedCall(1)     // swc-expected-error {{sema_err_function_where_failed}}
}

func(T) rejectedBlock(value: T)
    where { return false }     // swc-expected-note {{the constraint 'where { return false }' is declared here}}
{}

#test
{
    rejectedBlock(1)     // swc-expected-error {{sema_err_function_where_failed}}
}

// swc-expected-note@+2 {{accepts(T))' is declared here}}
func(T) rejectedMultiline(value: T)
    where (T is IValue and
           accepts(T)) {}

#test
{
    rejectedMultiline(Present{})     // swc-expected-error {{sema_err_function_where_failed}}
}
