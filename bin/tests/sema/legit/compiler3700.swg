#global fileprivate // swc-option sema-only
#global skip
#if true
{
    using namespace Toto
    {
        const A = 10
    }
}

const B = A

#if true
{
    using namespace Toto
    {
        const AA = 10
    }

    const BB = AA
}
