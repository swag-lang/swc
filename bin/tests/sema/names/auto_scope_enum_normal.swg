#global fileprivate

enum A { R, G, B }

#test
{
    let x: A = .G
    let y = x != .R
}

#test
{
    let x: A = .B
    let y = x == .B
}

#test
{
    let values: [3] A = [.R, .G, .B]
    let matrix: [2, 2] A = [[.R, .G], [.B, .R]]
    let same = values[1] == .G and matrix[1][0] == .B
}
