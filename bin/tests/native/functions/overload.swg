#global fileprivate // swc-option suite-test

func A() {}
func A(a: s32) {}

#test
{
    A()
    A(10)
}


struct S {}
impl S
{
    mtd foo() {}
    mtd foo(a: s32) {}
}
#test
{
    var s: S
    s.foo()
    s.foo(10)
}

#test
{
    var s: S
    S.foo(&s)
    S.foo(&s, 10)
}


