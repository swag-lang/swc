/*
--- Part Two ---
While the Elves get to work printing the correctly-ordered updates, you have a little time to fix the rest of them.

For each of the incorrectly-ordered updates, use the page ordering rules to put the page numbers in the right order. For the above example, here are the three incorrectly-ordered updates and their correct orderings:

75,97,47,61,53 becomes 97,75,47,61,53.
61,13,29 becomes 61,29,13.
97,13,75,29,47 becomes 97,75,47,29,13.
After taking only the incorrectly-ordered updates and ordering them correctly, their middle page numbers are 47, 29, and 47. Adding these together produces 123.

Find the updates which are not in the correct order. What do you get if you add up the middle page numbers after correctly ordering just those updates?
*/

using Core

func day5B()
{
    let dataPath = Path.combine(Path.getDirectoryName(#curlocation.fileName), "5.txt")
    let lines    = assume File.readAllLines(dataPath)

    var order: HashTable'(s32, Array's32)
    var first = true
    var total = 0

    for f in lines
    {
        if @countof(f) == 0
        {
            first = false
            continue
        }

        if first
        {
            let split = Tokenize.split(f, '|''u8)
            @assert(split.count == 2)
            order.findOrAdd(assume StrConv.toS32(split[0])).value.add(assume StrConv.toS32(split[1]))
        }
        else
        {
            var update = Slice.map(Tokenize.split(f, ',''u8).toSlice(), func(x) => assume StrConv.toS32(x))
            @assert(update.count != 0)

            var isOrdered = true
            for beforeIndex in update.count
            {
                let beforePage = update[beforeIndex]
                if beforeIndex + 1 >= update.count do
                    continue

                for afterIndex in beforeIndex + 1 to update.count - 1
                {
                    let afterPage = update[afterIndex]
                    if let nextPages = order.tryFind(afterPage) where nextPages.value.contains(beforePage)
                    {
                        isOrdered = false
                        break
                    }
                }
            }

            if !isOrdered
            {
                var repaired: Array's32
                repaired.resize(update.count)

                var used: Array'bool
                used.resize(update.count)

                var writeIndex = 0'u64
                while writeIndex < update.count
                {
                    var found = false

                    for candidateIndex in update.count
                    {
                        if used[candidateIndex] do
                            continue

                        let candidatePage = update[candidateIndex]
                        var hasIncoming = false

                        for otherIndex in update.count
                        {
                            if used[otherIndex] or otherIndex == candidateIndex do
                                continue
                            if let nextPages = order.tryFind(update[otherIndex]) where nextPages.value.contains(candidatePage)
                            {
                                hasIncoming = true
                                break
                            }
                        }

                        if hasIncoming do
                            continue

                        repaired[writeIndex] = candidatePage
                        used[candidateIndex] = true
                        writeIndex           += 1
                        found                = true
                        break
                    }

                    @assert(found)
                }

                @assert(repaired.count & 1 == 1)
                total += repaired[repaired.count / 2]
            }
        }
    }

    @assert(total == 6767)
}
