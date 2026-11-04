#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

// Message-locale precedence is independent of which locales are installed on the host.
#test
{
    Swag.require(Env.localeNameFromEnvironment("fr_FR.UTF-8", "de_DE", "en_US") == "fr-FR")
    Swag.require(Env.localeNameFromEnvironment("", "de_DE.UTF-8", "en_US") == "de-DE")
    Swag.require(Env.localeNameFromEnvironment("", "", "es_419.UTF-8") == "es-419")
    Swag.require(Env.localeNameFromEnvironment("C.UTF-8", "fr_FR", "en_US").isEmpty())
    Swag.require(Env.localeNameFromEnvironment("", "POSIX", "en_US").isEmpty())
    Swag.require(Env.localeNameFromEnvironment("", "", "").isEmpty())
}

#test
{
    Swag.require(Env.localeNameFromEnvironment("FR_fr.UTF-8@euro", "", "") == "fr-fr")
    Swag.require(Env.localeNameFromEnvironment("sr_RS@latin", "", "") == "sr-RS")
    Swag.require(Env.localeNameFromEnvironment("zh-Hant-TW", "", "") == "zh-Hant-TW")
    Swag.require(Env.localeNameFromEnvironment("en", "", "") == "en")
    for invalid in ["_FR", "fr_", "fr__FR", "fr--FR", "fr FR", "fr/FR", "fr:de", "fr\0FR", ".UTF-8"] do
        Swag.require(Env.localeNameFromEnvironment(invalid, "en_US", "en_US").isEmpty())
}
