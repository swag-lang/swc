#global if #os == Swag.TargetOs.Linux
#global namespace Env

internal func localeNameFromEnvironment(lcAll, lcMessages, lang: string)->String
{
    let locale = lcAll.count ? lcAll : lcMessages.count ? lcMessages : lang
    let withoutEncoding = Tokenize.sliceToDelimiter(locale, '.', includeDelimiter: false)
    let name = Tokenize.sliceToDelimiter(withoutEncoding, '@', includeDelimiter: false)
    if not name.count or name == "C" or name == "POSIX" do
        return ""

    var result:    String
    var primary   = true
    var separator = true
    for byte in name
    {
        if byte == '_' or byte == '-'
        {
            if separator do
                return ""
            result += '-'
            separator = true
            primary   = false
        }
        else
        {
            if not ((byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or Latin1.isDigit(byte)) do
                return ""
            result += primary ? Latin1.toLower(byte) : byte
            separator = false
        }
    }
    return separator ? String{} : result
}

// Returns the process's configured message locale as a hyphenated name, such as `"fr-FR"`.
//
// Uses the first nonempty value among LC_ALL, LC_MESSAGES and LANG. Encoding and POSIX modifier
// suffixes are omitted; underscores become hyphens and the primary language is lowercased.
// C, POSIX, malformed and unconfigured locales return an empty string. This does not change the
// process C locale or require the selected locale to be installed. Synchronize with environment
// mutation as for [[Core.Env.variable]].
public func userLocaleName()->String
{
    let all      = variable("LC_ALL")
    let messages = variable("LC_MESSAGES")
    let lang     = variable("LANG")
    return localeNameFromEnvironment(all.toString(), messages.toString(), lang.toString())
}
