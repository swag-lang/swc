#global private

func accept(value: u32) {}

func invalidIndex()
{
    var values: [2] u32
    accept(values[.Missing]) // swc-expected-error {{sema_err_not_value_expr}}
}

func invalidSecondIndex()
{
    var values: [2, 2] u32
    accept(values[0, .Missing]) // swc-expected-error {{sema_err_not_value_expr}}
}
