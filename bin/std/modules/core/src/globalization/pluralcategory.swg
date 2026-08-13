#global namespace Globalization

// Identifies a CLDR-compatible grammatical plural category.
public enum PluralCategory
{
    Zero      // Category used for zero in locales that distinguish it.
    One       // Singular category.
    Two       // Dual category.
    Few       // Locale-specific small-number category.
    Many      // Locale-specific large-number category.
    Other     // General fallback category.
}
