#[A]
enum B {}

#[A()]
enum B {}

#[A, B, A.C()]
enum B {}

#[A, B, A.C("0", 1, 2, 3)]
#[A, B, A.C("0", 1, 2, 3)]
#[A, B, A.C("0", 1, 2, 3)]
enum B {}
