#global public
#global namespace Viewer

using Core

// The text a reader sees when a file could not be shown because of `err`: a plain statement of
// what went wrong, then the technical detail the decoder or the system gave, for whoever reports it.
//
// The statement depends only on the kind of error, so it reads the same in every viewer and in
// every language; the detail stays a separate paragraph and never replaces it. No error gives
// no text, as [[Core.Errors.message]] does.
func failureText(err: any?)->String
{
    var result: retval
    if err == null do
        return result

    let texts = appStrings()
    switch err
    {
    case Errors.FileNotFoundError: result = texts.ui_FailureNotFound
    case Errors.InvalidFormatError, Errors.UnsupportedFormatError, Errors.InvalidVersion, Errors.SerializationError, Errors.SyntaxError, Errors.ParseIncompleteError: result = texts.ui_FailureFormat
    default: result = texts.ui_FailureUnreadable
    }

    // An error that carries no sentence of its own adds nothing under the statement: its type name
    // is what Errors.message answers then, and that is no help to a reader.
    let detail = Errors.message(err)
    if detail.count and detail != (Swag.kindOf(err).name orelse "")
    {
        result += "\n\n"
        result += detail
    }

    return result
}
