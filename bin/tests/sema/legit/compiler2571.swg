#global fileprivate
#global skip
#[Swag.Overload]
func fatal(x: string, args: ...) {}
#[Swag.Overload]
func fatal() {}

#test
{
    fatal()
}
