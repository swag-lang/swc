#global private

enum TaggedErrKind
{
    None
    Number
    Text
}

#[Swag.EnumFlags]
enum TaggedErrFlags
{
    A
    B
}

struct TaggedErrHolder
{
    using value: union(TaggedErrKind)
    {
        case .Number: number: s32
        case .Text:   text:   string
    } = .None
}

// A payload access needs a proof of its case.
func taggedErrRead(holder: TaggedErrHolder)->s32
{
    return holder.number     // swc-expected-error {{sema_err_tagged_payload_unproven}}
}

// A proof of another case does not cover it.
func taggedErrOtherCase(holder: TaggedErrHolder)->s32
{
    if holder.value is .Text do
        return holder.number     // swc-expected-error {{sema_err_tagged_payload_unproven}}
    return 0
}

// '!' over a proven access is redundant.
func taggedErrAlreadyProven(holder: TaggedErrHolder)->s32
{
    switch holder.value
    {
    case .Number:
        return holder.number!     // swc-expected-error {{sema_err_tagged_case_already_proven}}
    default:
        return 0
    }
}

// An assignment forgets the case proven before it.
func taggedErrReassigned(holder: TaggedErrHolder, other: TaggedErrHolder)->s32
{
    var copy = holder
    copy.value = .Number{1}
    copy       = other
    return copy.number     // swc-expected-error {{sema_err_tagged_payload_unproven}}
}

#test
{
    var holder: TaggedErrHolder
    holder.value = .None{1}     // swc-expected-error {{sema_err_tagged_case_no_payload}}
}

#test
{
    var holder: TaggedErrHolder
    discard holder is .Text     // swc-expected-error {{sema_err_tagged_is_subject}}
}

struct TaggedErrNotEnum
{
    value: union(s32)     // swc-expected-error {{sema_err_tagged_union_tag_not_enum}}
    {
        case 0: number: s32
    }
}

struct TaggedErrFlagsTag
{
    value: union(TaggedErrFlags)     // swc-expected-error {{sema_err_tagged_union_tag_flags}}
    {
        case .A: number: s32
    }
}

struct TaggedErrDuplicate
{
    value: union(TaggedErrKind)
    {
        case .Number: number: s32
        case .Number: other:  s32     // swc-expected-error {{sema_err_tagged_case_duplicate}}
    }
}

struct TaggedErrMissingCase
{
    value: union(TaggedErrKind)
    {
        case .Number: number: s32
        other: s32     // swc-expected-error {{sema_err_tagged_member_without_case}}
    }
}

union TaggedErrPlain
{
    case 0: number: s32     // swc-expected-error {{sema_err_tagged_case_outside_tagged_union}}
}

union TaggedErrNamed(TaggedErrKind)
{
    case .Number: number: s32
}

#test
{
    discard TaggedErrNamed{number: 1}     // swc-expected-error {{sema_err_tagged_union_literal}}
}
