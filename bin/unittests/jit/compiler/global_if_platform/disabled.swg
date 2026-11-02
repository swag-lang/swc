#global public
#global namespace GlobalIfPlatform

#global if not Enabled

#global if true

func(T) genericAnswer(_: T)->UnknownInactiveType => unknownInactiveName
func answer()->UnknownInactiveType => unknownInactiveName
var first, second: UnknownInactiveType
struct Choice { unused: UnknownInactiveType }
alias Result = UnknownInactiveType
impl Value
{
    mtd read()->UnknownInactiveType => unknownInactiveName
}
namespace Shared
{
    func excluded()->UnknownInactiveType => unknownInactiveName
}
