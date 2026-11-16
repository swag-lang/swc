#global public
#global namespace Viewer

using Core

// Returns the standard spelling of a text encoding, as a reader chooses or reads it.
//
// It is the name of a format rather than prose, so it reads the same in every language.
func encodingName(encoding: Text.Encoding)->string
{
    switch #complete encoding
    {
    case .Utf8:        return "UTF-8"
    case .Utf16Le:     return "UTF-16 LE"
    case .Utf16Be:     return "UTF-16 BE"
    case .Utf32Le:     return "UTF-32 LE"
    case .Utf32Be:     return "UTF-32 BE"
    case .Windows1252: return "Windows-1252"
    }
}
