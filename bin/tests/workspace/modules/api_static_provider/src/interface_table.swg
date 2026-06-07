#global public

interface IDepTableScore
{
    mtd score()->s32;
}

struct DepTableScore
{
    value: s32
}

struct DepTableBonusScore
{
    value: s32
}

impl IDepTableScore for DepTableScore
{
    mtd impl score()->s32 => .value
}

impl IDepTableScore for DepTableBonusScore
{
    mtd impl score()->s32 => .value + 10
}
