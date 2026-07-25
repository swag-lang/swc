#global private

func invalidTryOperand() fail
{
    try 1     // swc-expected-error {{sema_err_error_mgmt_operand_not_fallible}}
}
