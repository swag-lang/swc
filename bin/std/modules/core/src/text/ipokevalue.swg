#global public

namespace StrConv
{
    // Lets a type parse its own value from text when [[Core.StrConv.parseValue]] reads it.
    interface IPokeValue
    {
        // Parses the value from the start of `buf` into the receiver and returns the rest of `buf`.
        mtd poke(buf: string)->string fail
    }
}
