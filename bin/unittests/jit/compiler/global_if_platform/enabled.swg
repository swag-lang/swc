#global public
#global namespace GlobalIfPlatform
#global if Enabled

func(T) genericAnswer(_: T)->s32 => 42
func answer()->s32 => 42
var first:  s32 = 11
var second: s32 = 22
struct Choice { value: s32 }
alias Result = s32
impl Value
{
    mtd read()->s32 => .data
}
namespace Shared
{
    func selected()->s32 => 19
}
