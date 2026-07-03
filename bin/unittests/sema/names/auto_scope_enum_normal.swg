#global private

enum A { R, G, B }

func semaTest001()
{
    let x: A = .G
    let y = x != .R
}

func semaTest002()
{
    let x: A = .B
    let y = x == .B
}

func semaTest003()
{
    let values: [3] A = [.R, .G, .B]
    let matrix: [2, 2] A = [[.R, .G], [.B, .R]]
    let same = values[1] == .G and matrix[1][0] == .B
}
