#global internal

namespace InlineLocalForwardCall
{
    // The shape of a partitioning macro: a local function calling a sibling declared after it.
    // Under automatic inlining the call is met before the sibling's body has been analyzed, and
    // the job meeting it is the very one that will analyze that body.
    #[Swag.Macro]
    func visitTwice(count: u32, contextData: *void? = null, stmt: #code(index: u32, data))
    {
        func first(visitStart, visitCount: u32, visitContextData: *void?)
        {
            second(visitStart, visitCount, visitContextData)
        }

        func second(visitStart, visitCount: u32, visitContextData: *void?)
        {
            var index = visitStart
            for visitCount
            {
                #inject(stmt, index = index, data = visitContextData)
                index += 1
            }
        }

        first(0, count, contextData)
        first(count, count, contextData)
    }
}
