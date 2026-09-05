#global namespace GenericCallChain

func(T) leaf(value: T)->T
{
    return value + value     // swc-expected-error {{sema_err_binary_operand_type}}
}
