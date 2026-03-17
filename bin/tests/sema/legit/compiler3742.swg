#global fileprivate // swc-option sema-only
#global skip
func titi()->s32 throw { return 0; }
func toto() throw => titi()
