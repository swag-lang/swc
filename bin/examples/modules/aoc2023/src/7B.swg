/*
--- Part Two ---
To make things a little more interesting, the Elf introduces one additional rule. Now, J cards are jokers - wildcards that can act like whatever card would make the hand the strongest type possible.

To balance this, J cards are now the weakest individual cards, weaker even than 2. The other cards stay in the same order: A, K, Q, T, 9, 8, 7, 6, 5, 4, 3, 2, J.

J cards can pretend to be whatever card is best for the purpose of determining hand type; for example, QJJQ2 is now considered four of a kind. However, for the purpose of breaking ties between two hands of the same type, J is always treated as J, not the card it's pretending to be: JKKK2 is weaker than QQQQ2 because J is weaker than Q.

Now, the above example goes very differently:

32T3K 765
T55J5 684
KK677 28
KTJJT 220
QQQJA 483
32T3K is still the only one pair; it doesn't contain any jokers, so its strength doesn't increase.
KK677 is now the only two pair, making it the second-weakest hand.
T55J5, KTJJT, and QQQJA are now all four of a kind! T55J5 gets rank 3, QQQJA gets rank 4, and KTJJT gets rank 5.
With the new joker rule, the total winnings in this example are 5905.

Using the new joker rule, find the rank of every hand in your set. What are the new total winnings?
*/

using Core

private struct Card
{
    labels:              string = ""
    bid:                 u64
    countByRank:         [13] s32
    ranksByMultiplicity: [6] s32
    handType:            s32
}

private var strengthByLabel: [256] u8
private var hands: Array'Card

private func sort()
{
    hands.sort(func(leftHand, rightHand)
    {
        if leftHand.handType != rightHand.handType do
            return leftHand.handType <=> rightHand.handType

        for i in leftHand.labels.count
        {
            let leftStrength  = strengthByLabel[leftHand.labels[i]]
            let rightStrength = strengthByLabel[rightHand.labels[i]]
            if leftStrength != rightStrength do
                return leftStrength <=> rightStrength
        }

        return 0
    })
}

func day7B()
{
    let dataPath = Path.combine(Path.directoryName(#curlocation.fileName), "7.txt")
    let lines    = expect File.readAllLines(dataPath)

    strengthByLabel['A'u8] = 12
    strengthByLabel['K'u8] = 11
    strengthByLabel['Q'u8] = 10
    strengthByLabel['T'u8] = 9
    strengthByLabel['9'u8] = 8
    strengthByLabel['8'u8] = 7
    strengthByLabel['7'u8] = 6
    strengthByLabel['6'u8] = 5
    strengthByLabel['5'u8] = 4
    strengthByLabel['4'u8] = 3
    strengthByLabel['3'u8] = 2
    strengthByLabel['2'u8] = 1
    strengthByLabel['J'u8] = 0

    for line in lines
    {
        let handAndBid = Tokenize.split(line[], ' 'u8)

        var hand: Card
        var mostFrequentRankCount = 0
        for label in handAndBid[0]
        {
            let rank = strengthByLabel[label]
            hand.countByRank[rank] += 1
            if rank do
                mostFrequentRankCount = Math.max(mostFrequentRankCount, hand.countByRank[rank])
        }

        for rankCount, rank in hand.countByRank
        {
            if rankCount and rank do
                hand.ranksByMultiplicity[rankCount] += 1
        }

        // Add all jokers to the most frequent non-joker rank to maximize this hand type.
        let jokerCount = hand.countByRank[0]
        hand.ranksByMultiplicity[mostFrequentRankCount + jokerCount] += 1
        hand.ranksByMultiplicity[mostFrequentRankCount] -= 1

        switch
        {
        case hand.ranksByMultiplicity[5]:      hand.handType = 6
        case hand.ranksByMultiplicity[4]:      hand.handType = 5
        case hand.ranksByMultiplicity[3] and hand.ranksByMultiplicity[2]: hand.handType = 4
        case hand.ranksByMultiplicity[3]:      hand.handType = 3
        case hand.ranksByMultiplicity[2] == 2: hand.handType = 2
        case hand.ranksByMultiplicity[2]:      hand.handType = 1
        }

        hand.labels = handAndBid[0]
        hand.bid    = expect StrConv.toU64(handAndBid[1])
        hands.add(hand)
    }

    sort()

    var total: u64
    for hand, rank in hands do
        total += (rank + 1) * hand.bid

    Swag.assert(total == 248029057)
}
