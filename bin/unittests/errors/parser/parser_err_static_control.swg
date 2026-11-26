#global private

func invalidStaticControl()
{
    #static while true { break }     // swc-expected-error {{parser_err_static_control}}
}
