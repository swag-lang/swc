#global private

// '.kind' names a field of the receiver, never the parameter 'kind': a missing field is reported
// as such instead of waiting for the parameter.
struct LeadingDotGroup
{
    count: u32
}

impl LeadingDotGroup
{
    mtd addTrack(kind: u32)->u32
    {
        if .kind == 1 do     // swc-expected-error {{sema_err_auto_scope_missing_struct_member}}
            return kind
        return .count
    }
}
