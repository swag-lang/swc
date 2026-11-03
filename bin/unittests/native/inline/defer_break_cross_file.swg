#global private

#test
{
    var resource = false

    for index in 10
    {
        resource = true
        defer
        {
            Swag.require(InlineRegressionBug15.isResourceCreated(resource))
            resource = false
        }

        if index == 2 do
            break
    }

    Swag.require(not InlineRegressionBug15.isResourceCreated(resource))
}
