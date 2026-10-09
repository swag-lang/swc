#global private

// A member that a scope does not declare is reported against that scope, with the closest name it
// does offer when the spelling is near one. A swapped pair of letters is a single typo.

struct UnknownMemberBox
{
    height: s32
}

impl UnknownMemberBox
{
    mtd get()->s32 => .height
}

enum UnknownMemberColor
{
    Red
    Green
}

namespace UnknownMemberGeometry
{
    func area()->s32 => 1
}

func unknownMemberField(box: UnknownMemberBox)->s32
{
    return box.heigth     // swc-expected-error {{struct 'UnknownMemberBox' has no member 'heigth'; [help] use 'height' instead}}
}

func unknownMemberMethod(box: UnknownMemberBox)->s32
{
    return box.gte()     // swc-expected-error {{struct 'UnknownMemberBox' has no member 'gte'; [help] use 'get' instead}}
}

func unknownMemberFar(box: UnknownMemberBox)->s32
{
    return box.z     // swc-expected-error {{struct 'UnknownMemberBox' has no member 'z'}}
}

func unknownMemberEnum()->UnknownMemberColor => UnknownMemberColor.Gren     // swc-expected-error {{enum 'UnknownMemberColor' has no member 'Gren'; [help] use 'Green' instead}}

func unknownMemberNamespace()->s32 => UnknownMemberGeometry.aera()     // swc-expected-error {{namespace 'UnknownMemberGeometry' has no member 'aera'; [help] use 'area' instead}}
