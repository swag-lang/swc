using Core

namespace SCrypt
{
    struct Error
    {
        using base: Swag.BaseError
    }

    func failWith(message: string) fail
    {
        fail Error{Errors.mkString(message)}
    }
}

