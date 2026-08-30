#global private

#test
{
    var resource = false

    for 10
    {
        resource = true
        defer
        {
            Swag.assert(InlineRegressionBug15.isResourceCreated(resource))
            resource = false
        }

        if Swag.index == 2 do
            break
    }

    Swag.assert(!InlineRegressionBug15.isResourceCreated(resource))
}
