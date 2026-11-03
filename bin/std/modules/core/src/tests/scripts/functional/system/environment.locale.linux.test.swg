#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

// Message-locale precedence is independent of which locales are installed on the host.
#test
{
    Swag.assert(Env.localeNameFromEnvironment("fr_FR.UTF-8", "de_DE", "en_US") == "fr-FR")
    Swag.assert(Env.localeNameFromEnvironment("", "de_DE.UTF-8", "en_US") == "de-DE")
    Swag.assert(Env.localeNameFromEnvironment("", "", "es_419.UTF-8") == "es-419")
    Swag.assert(Env.localeNameFromEnvironment("C.UTF-8", "fr_FR", "en_US").isEmpty())
    Swag.assert(Env.localeNameFromEnvironment("", "POSIX", "en_US").isEmpty())
    Swag.assert(Env.localeNameFromEnvironment("", "", "").isEmpty())
}

#test
{
    Swag.assert(Env.localeNameFromEnvironment("FR_fr.UTF-8@euro", "", "") == "fr-fr")
    Swag.assert(Env.localeNameFromEnvironment("sr_RS@latin", "", "") == "sr-RS")
    Swag.assert(Env.localeNameFromEnvironment("zh-Hant-TW", "", "") == "zh-Hant-TW")
    Swag.assert(Env.localeNameFromEnvironment("en", "", "") == "en")
    for invalid in ["_FR", "fr_", "fr__FR", "fr--FR", "fr FR", "fr/FR", "fr:de", "fr\0FR", ".UTF-8"] do
        Swag.assert(Env.localeNameFromEnvironment(invalid, "en_US", "en_US").isEmpty())
}
