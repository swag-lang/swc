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

func probe()->u32
{
    var badgeScorer: BadgeScorer
    let iBadge = cast(IGroupScorer) badgeScorer
    return iBadge.score(1'u64, 2'u64) // swc-expected-error {{sema_err_too_few_arguments}}
}
