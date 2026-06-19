#global fileprivate
#global #if #os == Swag.TargetOs.Windows

#[Swag.Foreign("kernel32", "GetCurrentProcessId")]
func GetPidWithBody()->u32 { return 0; } // swc-expected-error {{sema_err_foreign_cannot_have_body}}
