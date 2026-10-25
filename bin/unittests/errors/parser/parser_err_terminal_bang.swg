#global private

func terminalBinding()
{
    let value = pointer! // swc-expected-error {{parser_err_terminal_bang}}
}

func terminalReturn()
{
    return pointer! // swc-expected-error {{parser_err_terminal_bang}}
}

func terminalArgument()
{
    consume(pointer!) // swc-expected-error {{parser_err_terminal_bang}}
}

func terminalComparison()
{
    let same = pointer! == other // swc-expected-error {{parser_err_terminal_bang}}
}

func terminalFallible()
{
    let value = expect load()! // swc-expected-error {{parser_err_terminal_bang}}
}

func terminalBeforeNextStatement()
{
    let value = pointer! // swc-expected-error {{parser_err_terminal_bang}}
    (call)()
}
