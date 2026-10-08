#global private

// '_' declares a position without a name. Several can share one declaration, since none of them
// is a name, and every binding form accepts it.
func ignoreBoth(_: s32, _: s32)->s32 => 0

#test
{
    Swag.assert(ignoreBoth(1, 2) == 0)
    var total = 0
    for _, value in [1, 2] do
        total += value
    let {_, second} = {1, 2}
    Swag.assert(total == 3 and second == 2)
}

// Nothing can read an unnamed binding back.
func readBack(_: s32)->s32 => _     // swc-expected-error {{parser_err_unnamed_read}}

// '_' is not a name a declaration can introduce.
#test
{
    let _ = 3     // swc-expected-error {{parser_err_expected_token_fam_before}}
}

// '?' only marks a nullable type: a binding without a name is written '_'.
func oldSpelling(?: s32) {}     // swc-expected-error {{parser_err_expected_token_fam_before}}
