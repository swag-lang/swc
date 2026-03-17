#global fileprivate // swc-option sema-only
#global skip
//#global testerror "Err0194"
func toto(x: s32) {}
//func toto(x: s64) {}
#[Swag.Strict]
alias titi = toto
