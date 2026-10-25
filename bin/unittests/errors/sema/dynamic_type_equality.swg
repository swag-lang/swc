#global private

func compareBoxedWithType(value: any)->bool
{
    // swc-expected-error@(+1) {{sema_err_compare_operand_type}}
    return value == s32
}

func compareTypeWithBoxed(value: any, type: typeinfo)->bool
{
    // swc-expected-error@(+1) {{sema_err_compare_operand_type}}
    return type != value
}

interface IObject { mtd value()->s32 }
struct ConcreteObject {}

func compareInterfaceWithType(value: IObject)->bool
{
    return value != ConcreteObject     // swc-expected-error {{sema_err_compare_operand_type}}
}

func compareTypeWithInterface(value: IObject)->bool
{
    return ConcreteObject == value     // swc-expected-error {{sema_err_compare_operand_type}}
}
