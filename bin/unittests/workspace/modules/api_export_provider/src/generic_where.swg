// Keep the failed constraint in the exported API so its caller uses a different AST.
public func(T) rejectWhere(value: T)->T
    where
    {
        return false
    }
{
    return value
}
