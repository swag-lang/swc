#global fileprivate

interface IGroupScorer
{
    mtd score(firstMask, secondMask, thirdMask: u64)->u32;
}

struct BadgeScorer {}

impl IGroupScorer for BadgeScorer
{
    mtd impl score(firstMask, secondMask, thirdMask: u64)->u32
    {
        return 0
    }
}
