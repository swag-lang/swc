#global fileprivate

interface I
{
    func bad(); // swc-expected-error {{parser_err_interface_method_must_use_mtd}}
}
