#global fileprivate
#global skip
func toto(x: rune) {}

#test
{
    toto(0xFFFFFFFF)
}
