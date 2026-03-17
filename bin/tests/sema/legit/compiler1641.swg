#global fileprivate
#global skip
interface ITOTO
{
    func ptr(me);
}

var val: ITOTO

func fc(x: ITOTO)
{
    val = x
}
