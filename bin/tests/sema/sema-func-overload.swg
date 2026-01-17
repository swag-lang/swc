#global internal

func A() {}
func A(a: s32) {}

#test
{
    A()
    A(10)
}