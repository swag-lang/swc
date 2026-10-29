// A shared artifact with its own emitted runtime participates in the caller's borrow registry.
#global #[Swag.Safety(.ValueBorrow, true)]
public struct Value
{
    public { first, second, third: u64 }
}
#[Swag.NoInline]
public func write(target: *Value) { target.first = 0 }
#[Swag.NoInline]
public func read(value: Value)->u64 => value.first
#[Swag.NoInline]
public func readAfterCallback(value: Value, callback: func(*Value), target: *Value)->u64
{
    callback(target)
    return value.first
}
