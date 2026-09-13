#global private

func runtimeString(buffer: [*] u8, text: string)->string
{
    for index in text.count do
        buffer[index] = text[index]
    return Swag.makeString(buffer, text.count)
}

// Twenty distinct first chunks, repeated before and after the small-set limit.
// The second chunk must still distinguish both cases sharing each first chunk.
func manyChunks(value: string)->s32
{
    switch value
    {
    case "group-00suffix-a": return 1
    case "group-00suffix-b": return 2
    case "group-01suffix-a": return 3
    case "group-01suffix-b": return 4
    case "group-02suffix-a": return 5
    case "group-02suffix-b": return 6
    case "group-03suffix-a": return 7
    case "group-03suffix-b": return 8
    case "group-04suffix-a": return 9
    case "group-04suffix-b": return 10
    case "group-05suffix-a": return 11
    case "group-05suffix-b": return 12
    case "group-06suffix-a": return 13
    case "group-06suffix-b": return 14
    case "group-07suffix-a": return 15
    case "group-07suffix-b": return 16
    case "group-08suffix-a": return 17
    case "group-08suffix-b": return 18
    case "group-09suffix-a": return 19
    case "group-09suffix-b": return 20
    case "group-10suffix-a": return 21
    case "group-10suffix-b": return 22
    case "group-11suffix-a": return 23
    case "group-11suffix-b": return 24
    case "group-12suffix-a": return 25
    case "group-12suffix-b": return 26
    case "group-13suffix-a": return 27
    case "group-13suffix-b": return 28
    case "group-14suffix-a": return 29
    case "group-14suffix-b": return 30
    case "group-15suffix-a": return 31
    case "group-15suffix-b": return 32
    case "group-16suffix-a": return 33
    case "group-16suffix-b": return 34
    case "group-17suffix-a": return 35
    case "group-17suffix-b": return 36
    case "group-18suffix-a": return 37
    case "group-18suffix-b": return 38
    case "group-19suffix-a": return 39
    case "group-19suffix-b": return 40
    }
    return 0
}

#test
{
    var buffer: [32] u8
    let names: [40] string = [
        "group-00suffix-a", "group-00suffix-b", "group-01suffix-a", "group-01suffix-b",
        "group-02suffix-a", "group-02suffix-b", "group-03suffix-a", "group-03suffix-b",
        "group-04suffix-a", "group-04suffix-b", "group-05suffix-a", "group-05suffix-b",
        "group-06suffix-a", "group-06suffix-b", "group-07suffix-a", "group-07suffix-b",
        "group-08suffix-a", "group-08suffix-b", "group-09suffix-a", "group-09suffix-b",
        "group-10suffix-a", "group-10suffix-b", "group-11suffix-a", "group-11suffix-b",
        "group-12suffix-a", "group-12suffix-b", "group-13suffix-a", "group-13suffix-b",
        "group-14suffix-a", "group-14suffix-b", "group-15suffix-a", "group-15suffix-b",
        "group-16suffix-a", "group-16suffix-b", "group-17suffix-a", "group-17suffix-b",
        "group-18suffix-a", "group-18suffix-b", "group-19suffix-a", "group-19suffix-b"]
    for text, index in names do
        Swag.assert(manyChunks(runtimeString(&buffer[0], text)) == cast(s32) index + 1)

    let others: [5] string = [
        "group-00suffix-c", "group-19suffix-c", "group-20suffix-a",
        "group-00suffix-", "group-00suffix-aa"]
    for text in others do
        Swag.assert(not manyChunks(runtimeString(&buffer[0], text)))
}
