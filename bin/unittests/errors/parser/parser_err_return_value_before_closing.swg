#global private

func bareWithSemicolon() { return; }

func bareWithLineBreak()
{
    return
}

func missingValue() { return }     // swc-expected-error {{parser_err_return_value_before_closing}}

func catchHandler()
{
    let info = catch File.info(path) { return }     // swc-expected-error {{parser_err_return_value_before_closing}}
}
