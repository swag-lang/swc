#global fileprivate

// Interfaces only accept 'mtd' methods; using 'func' is reported for each occurrence.
interface I
{
    func m1();                        // swc-expected-error {{parser_err_interface_method_must_use_mtd}}
    func m2();                        // swc-expected-error {{parser_err_interface_method_must_use_mtd}}
    mtd m3();
    func m4();                        // swc-expected-error {{parser_err_interface_method_must_use_mtd}}
}
