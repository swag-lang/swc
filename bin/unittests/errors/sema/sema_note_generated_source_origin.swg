#global private

#[Swag.Compiler]
func generateInvalidFunction()->string
{
    return "func generatedInvalidFunction()->s32 { return true } // swc-expected-error {{sema_err_cannot_cast}}"
}

#ast generateInvalidFunction()     // swc-expected-note {{sema_note_generated_source_origin}}
