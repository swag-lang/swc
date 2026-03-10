// swc-option suite-test

#global fileprivate
#global skip
func toto(x: ...) {}

func toto1(x: u32...) {}

#test
{
    toto()
    toto1()
}
