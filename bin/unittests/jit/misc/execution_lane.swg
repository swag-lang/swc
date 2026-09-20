#global private

var executionCount: s32
var executionDelay: s32

func incrementExecutionCount()->s32
{
    let previous = executionCount
    // Concurrent #run calls would all observe the same value during this window.
    var remaining = 100_000
    while remaining != 0
    {
        executionDelay += 1
        remaining -= 1
    }
    executionCount = previous + 1
    return executionCount
}

func readExecutionCount(_0, _1, _2, _3, _4, _5, _6, _7: s32)->s32 => executionCount

const execution0 = #run incrementExecutionCount()
const execution1 = #run incrementExecutionCount()
const execution2 = #run incrementExecutionCount()
const execution3 = #run incrementExecutionCount()
const execution4 = #run incrementExecutionCount()
const execution5 = #run incrementExecutionCount()
const execution6 = #run incrementExecutionCount()
const execution7 = #run incrementExecutionCount()

// Each argument makes this final #run wait for every independent increment above.
const finalExecutionCount = #run readExecutionCount(execution0, execution1, execution2, execution3, execution4, execution5, execution6, execution7)

#test
{
    #assert(finalExecutionCount == 8)
}
