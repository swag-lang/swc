#main
{
    #static if #hastag("cache.enabled")
    {
        Swag.print("cache-tag=", cacheTagValue(), "\n")
    }
    else
    {
        Swag.print("cache-tag=disabled\n")
    }
}
