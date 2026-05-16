const PRIVATE_VALUE = 99
public const DEP_VALUE = 7

public func depFutureExport()->s32
{
    return DEP_VALUE
}

public func(T) depGenericIdentity(value: T)->T => value
