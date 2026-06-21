#global fileprivate

#test
{
    var resource = false

    for 10
    {
        resource = true
        defer
        {
            @assert(InlineRegressionBug15.isResourceCreated(resource))
            resource = false
        }

        if @index == 2 do
            break
    }

    @assert(!InlineRegressionBug15.isResourceCreated(resource))
}
