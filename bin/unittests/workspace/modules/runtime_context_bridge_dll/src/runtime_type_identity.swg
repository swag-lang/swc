// Runtime `Swag.*` types are compiled into every module, so the descriptors this DLL emits and
// the ones the consumer emits must describe one identity: `==` and `case` compare the typeinfo
// crc, `is` and `as` compare the descriptor fullname, and both must answer the same on either
// side of the boundary.

public func ctxSharedTypeOfBaseError()->typeinfo => Swag.BaseError

public func ctxSharedTypeOfSystemError()->typeinfo => Swag.SystemError

// Classifies against descriptors this module emitted, so a consumer-provided typeinfo has to
// match across the boundary.
public func ctxSharedClassifyRuntimeError(type: typeinfo)->s32
{
    switch type
    {
    case Swag.SystemError:
        return 1
    case Swag.BaseError:
        return 2
    default:
        return 0
    }
}

// Raises this module's own view of [[Swag.SystemError]], so the consumer classifies an error
// value whose descriptor crossed the boundary.
public func ctxSharedRaiseSystemError() fail
{
    fail Swag.SystemError{"raised across the boundary"}
}

public func ctxSharedMayFailNothing() fail {}
