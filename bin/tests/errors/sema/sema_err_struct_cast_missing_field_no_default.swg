#global fileprivate

struct RequiredDefaults {x: s32 = undefined, y: s32 = 5, z: s32 = undefined}

#test { const REQUIRED_DEFAULTS: RequiredDefaults = {y: 2} } // swc-expected-error {{sema_err_struct_cast_missing_field_no_default}}
#test { const REQUIRED_DEFAULTS: RequiredDefaults = {x: 1} } // swc-expected-error {{sema_err_struct_cast_missing_field_no_default}}
