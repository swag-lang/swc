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
            if encodingID == 10 do
                score += 20
            elif encodingID == 1 do
                score += 15
            if languageID == 0x0409 do
                score += 10
        }
        elif platformID == 0
        {
            score += 30
        }
        elif platformID == 1
        {
            score += 10
        }

        return score
    }
}
