#global private
alias Row = [8] u32

#[Swag.Optimize(true), Swag.NoInline]
func transposeRows(input: const [*] u32)->[8][8] u32
{
    var rows: [8] Row
    for index in 8 do
        rows[index] = cast(const [*] Row, input)[index]

    var result: #returntype
    for word in 8
    {
        let lanes = cast(const *[8] u32, &rows[word])[]
        for chunk in 8 do
            result[chunk][word] = lanes[chunk]
    }
    return result
}

#test
{
    var input: [64] u32
    for index in input.count do
        input[index] = cast(u32, index * 251 + 3)
    let output = transposeRows(&input[0])
    for row in 8
    {
        for col in 8 do
            Swag.require(output[row][col] == input[col * 8 + row])
    }
}
