#global private

// A block that lost its closing brace takes the one meant for its parent, so the end of the file
// reports the outer brace. The inner one is named as the likely culprit: its closing brace does
// not line up with it.

func unclosedInner(x: s32)->s32
{     // swc-expected-error {{parser_err_expected_closing}}
    if x > 0
    {     // swc-expected-note {{parser_note_unclosed_candidate}}
        return 1
    return 0
}
