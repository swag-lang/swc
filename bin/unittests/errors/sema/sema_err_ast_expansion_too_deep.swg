#global private

#[Swag.Compiler]
func(const Depth: s32) expandDeeper()->string
{
    let next = Depth + 1
    let source = "#ast expandDeeper'" ++ #stringof(next) ++ "()"
    if next == 64 do
        return source ++ " // swc-expected-error {{sema_err_ast_expansion_too_deep}}"
    return source
}

#ast expandDeeper'0() // swc-expected-note {{sema_note_generated_source_root}}
