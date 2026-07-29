#global public

namespace StrConv
{
    // Defines the operations supported by i poke value.
    public interface IPokeValue
    {
        // Performs the poke operation.
        mtd poke(buf: string)->string fail
    }
}
