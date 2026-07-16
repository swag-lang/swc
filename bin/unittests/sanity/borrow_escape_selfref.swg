#global public
// Storing a local's address into an object that itself lives inside that local (a pointer
// handed out by one of the local's own containers) is a self-reference: it dies together
// with the local, so nothing escapes.
#global #[Swag.Sanity(.Lifecycle, true)]
using Swag

struct SelfRefPool
{
    items: [*] SelfRefNode
    count: u64
}

struct SelfRefNode
{
    parent: *SelfRefNode
    pool:   SelfRefPool
}

impl SelfRefPool
{
    #[Swag.NoInline]
    mtd newPtr()->*SelfRefNode
    {
        let p = me.items + me.count
        me.count += 1
        return p
    }
}

// 'child' is handed out by 'root.pool' (part of 'root'); storing '&root' into it is a
// self-reference that dies with 'root'.
func selfRefStore()
{
    var root: SelfRefNode
    let child = root.pool.newPtr()
    child.parent = &root
}
