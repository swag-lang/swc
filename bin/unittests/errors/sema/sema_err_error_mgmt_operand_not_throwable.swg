#global private

func invalidTryOperand() throw
{
    try 1 // swc-expected-error {{sema_err_error_mgmt_operand_not_throwable}}
}
