#global fileprivate // swc-option sema-only
#global skip
interface IIncrementable
{
    func decr(me);
    func done(me)->bool;
}

//#[Swag.PrintBc]
#test
{
    var x: IIncrementable
    @assert(x == null)
}
