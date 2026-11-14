#global internal
#global namespace Viewers.Package

using Core

// Appends package text as HTML without allowing source content to introduce markup.
func appendHtmlEscaped(result: *String, source: string)
{
    for value in source
    {
        switch value
        {
        case '&':  result[] += "&amp;"
        case '<':  result[] += "&lt;"
        case '>':  result[] += "&gt;"
        case '"': result[] += "&quot;"
        default:   result[] += value
        }
    }
}
