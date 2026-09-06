#global if #hastag("cache.enabled")

func cacheTagValue()->u32 => #gettag("cache.value", u32, 0)
