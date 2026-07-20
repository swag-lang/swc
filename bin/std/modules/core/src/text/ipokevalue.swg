#global public

namespace StrConv
{
    public interface IPokeValue
    {
        mtd poke(buf: #nonull string)->#nonull string throw;
    }
}
