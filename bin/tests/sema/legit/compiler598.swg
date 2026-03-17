#global fileprivate // swc-option sema-only
#global skip
struct Point {}

impl Point
{
    /*func(op: string) opAssign(me, what: s32)
	{
	}*/

    func(op: string) toto(me) {}
}

#test
{
    var pt: Point
    //pt = 0
    Point.toto'("0")(pt)
}
