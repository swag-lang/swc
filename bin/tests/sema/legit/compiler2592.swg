#global fileprivate
#global skip
#test
{
    for 5
    {
        #if false
        {
            #assert(false)
        }
        #else
        {
            #assert(true)
        }
    }
}
