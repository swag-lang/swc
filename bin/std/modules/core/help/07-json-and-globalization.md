# JSON and globalization

The reflection-driven JSON codec reads and writes ordinary Swag structs without a schema or
annotations. Fields marked [[Core.Serialization.NoSerialize]] stay out of the document. The
reader accepts properties in any order, retains initialized values for missing properties, and
ignores properties the current declaration does not know, which lets configuration files evolve.

```swag
using Core

struct Settings
{
    title:   String
    retries: u32 = 3
}

let source: String = #raw """{"futureOption":true,"title":"Workbench"}"""
var decoder: Serialization.Decoder'Serialization.Read.Json
let settings = try decoder.readAll'Settings(source.toSlice())!
defer Memory.delete(settings)

var encoder: Serialization.Encoder'Serialization.Write.Json
encoder.serializer.options.saveBlanks = true
var output: ConcatBuffer
try encoder.writeAll(&output, settings[])
```

Malformed UTF-8, invalid escapes and numbers, duplicate properties, trailing commas, excessive
nesting, and data after the root value fail with a [[Core.Errors.SyntaxError]]. The decoder owns
the returned struct; release it with [[Core.Memory.delete]]. Because JSON has no representation for
NaN or infinity, the writer emits `null` for non-finite floating-point values.

## Culture-aware presentation

[[Core.Globalization.CultureInfo]] groups number, currency, date/time, collation, plural, and case
rules for one BCP 47 locale name. Pass a culture explicitly through application code when output
must be deterministic. [[Core.Globalization.currentCulture]] remains available for process-wide
defaults used by the existing numeric conversion routines.

```swag
using Core

let culture = Globalization.CultureInfo.fromName("fr-FR")
let amount  = culture.currencyFormat.format(12345.5, culture.numberFormat)
let when    = culture.dateTimeFormat.formatDateTime(Time.DateTime{2026, 8, 13, 18, 30})
let form    = culture.cardinalPlural(2)
```

The built-in profiles cover common conventions for English, French, German, Hindi, Turkish,
Russian, Arabic, Japanese, Swedish, Polish, and Czech. Unknown locale names use invariant English
display data and general plural rules; applications that need exhaustive CLDR tailoring can keep
that policy above this compact core layer.
