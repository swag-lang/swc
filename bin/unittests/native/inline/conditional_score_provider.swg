#global internal

namespace InlineRegressionBug8
{
    #[Swag.Inline]
    func scoreNameRecord(platformID, encodingID, languageID: u16)->s32
    {
        var score = 0
        if platformID == 3
        {
            score += 40
            if encodingID == 10
            {
                score += 20
            }
            else if encodingID == 1
            {
                score += 15
            }
            if languageID == 0x0409
            {
                score += 10
            }
        }
        else if platformID == 0
        {
            score += 30
        }
        else if platformID == 1
        {
            score += 10
        }

        return score
    }
}
