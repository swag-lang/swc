#global fileprivate // swc-option sema-only

enum A { R, G, B }

#test
{
    let x: A = .C // swc-expected-error {{sema_err_auto_scope_missing_enum_value}}
}

#test
{
    let x: A = .R
    let y = x == .C // swc-expected-error {{sema_err_auto_scope_missing_enum_value}}
}

#test
{
    let y = .C // swc-expected-error {{sema_err_cannot_compute_auto_scope}}
}

#test
{
    let x: A = .G
    let y = x != .R
}

#test
{
    let x: A = .B
    let y = x == .B
}

#test
{
    let values: [3] A = [.R, .G, .B]
    let matrix: [2, 2] A = [[.R, .G], [.B, .R]]
    let same = values[1] == .G and matrix[1][0] == .B
}
