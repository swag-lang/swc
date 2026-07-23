/*
    :LICENCE
    By Bob Jenkins, public domain.
*/

#global namespace Hash
using Swag

#[Safety(.All, false)]
public func jenkins(h: u64)->u64
{
    var key = (h ^ (h >> 30)) * 0xBF58476D1CE4E5B9
    key = (key ^ (key >> 27)) * 0x94D049BB133111EB
    key = key ^ (key >> 31)
    return key
}

#[Safety(.All, false)]
public func jenkins(h: u32)->u32
{
    var key = (h + 0x7ED55D16) + (h << 12)
    key = (key ^ 0xC761C23C) ^ (key >> 19)
    key = (key + 0x165667B1) + (key << 5)
    key = (key + 0xD3A2646C) ^ (key << 9)
    key = (key + 0xFD7046C5) + (key << 3)
    key = (key ^ 0xB55A4F09) ^ (key >> 16)
    return key
}
