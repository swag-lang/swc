#global fileprivate

interface I0 {}

interface I1
{
    mtd ok();
}

interface I2
{
    func bad(); // swc-expected-error {{parser_err_interface_method_must_use_mtd}}
    mtd stillOk();
}
