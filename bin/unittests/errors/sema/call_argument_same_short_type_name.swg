#global private

// Two different types that share a short name are printed qualified in a call diagnostic:
// "has type '*Foo', but parameter needs '*Foo'" would read as nonsense.

namespace SameNameLeft  { struct Foo { x: u32 } }
namespace SameNameRight { struct Foo { y: u32 } }

func sameNameTake(value: *SameNameRight.Foo) { discard value }

func sameNameCall()
{
    var left: SameNameLeft.Foo
    sameNameTake(&left)     // swc-expected-error {{argument 1 for call to 'sameNameTake' has type '*SameNameLeft.Foo', but parameter 'value' needs '*SameNameRight.Foo'}}
}
