#global public
#global #[Swag.ExplicitNullability]

namespace StrConv
{
    public interface IPokeValue
    {
        mtd poke(buf: #nonull string)->#nonull string throw;
    }
}
