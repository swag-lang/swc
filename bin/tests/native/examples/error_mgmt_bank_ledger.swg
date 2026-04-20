#global fileprivate

// Real-world error management scenario: a mini bank ledger with atomic
// transfers. Exercises the whole toolbox: typed throw errors carrying
// context, try-propagation, catch/trycatch at call sites, @err inspection
// after catch, defer #err to roll back on failure, defer #noerr to commit
// on success.

const MaxAccounts = 8

enum BankErrorKind
{
    None
    UnknownAccount
    InsufficientFunds
    InvalidAmount
    FrozenAccount
}

struct BankError
{
    using base:  Swag.BaseError
    kind:        BankErrorKind = BankErrorKind.None
    account:     s32           = -1
    amount:      s64           = 0
}

struct Account
{
    id:       s32
    balance:  s64
    frozen:   bool
}

struct Transfer
{
    from:    s32
    dest:    s32
    amount:  s64
}

struct Ledger
{
    accounts:    [MaxAccounts] Account
    committed:   s32
    rolledBack:  s32
    totalOps:    s32
}

impl Ledger
{
    mtd reset()
    {
        foreach &a, idx in .accounts
        {
            a.id      = cast(s32) idx
            a.balance = 0
            a.frozen  = false
        }
        .committed  = 0
        .rolledBack = 0
        .totalOps   = 0
    }

    mtd findAccount(id: s32)->*Account throw
    {
        if id < 0 or id >= cast(s32) MaxAccounts
        {
            var err: BankError
            err.message = "unknown account"
            err.kind    = .UnknownAccount
            err.account = id
            throw err
        }

        return &.accounts[id]
    }

    mtd deposit(id: s32, amount: s64) throw
    {
        if amount <= 0
        {
            var err: BankError
            err.message = "invalid amount"
            err.kind    = .InvalidAmount
            err.account = id
            err.amount  = amount
            throw err
        }

        let acc = try .findAccount(id)
        if acc.frozen
        {
            var err: BankError
            err.message = "frozen account"
            err.kind    = .FrozenAccount
            err.account = id
            throw err
        }

        acc.balance += amount
        .totalOps   += 1
    }

    mtd withdraw(id: s32, amount: s64) throw
    {
        if amount <= 0
        {
            var err: BankError
            err.message = "invalid amount"
            err.kind    = .InvalidAmount
            err.account = id
            err.amount  = amount
            throw err
        }

        let acc = try .findAccount(id)
        if acc.frozen
        {
            var err: BankError
            err.message = "frozen account"
            err.kind    = .FrozenAccount
            err.account = id
            throw err
        }

        if acc.balance < amount
        {
            var err: BankError
            err.message = "insufficient funds"
            err.kind    = .InsufficientFunds
            err.account = id
            err.amount  = amount
            throw err
        }

        acc.balance -= amount
        .totalOps   += 1
    }

    mtd transfer(from: s32, dest: s32, amount: s64) throw
    {
        try .withdraw(from, amount)

        // Once the withdrawal succeeded, the rollback is registered so any
        // later throw restores the source balance.
        defer #err
        {
            .accounts[from].balance += amount
            .rolledBack             += 1
        }

        // Commit counter only moves when the whole transfer runs to the end.
        defer #noerr .committed += 1

        try .deposit(dest, amount)
    }

    mtd runBatch(ops: const [..] Transfer)->s32
    {
        var successes: s32 = 0
        foreach op in ops
        {
            catch .transfer(op.from, op.dest, op.amount)
            if @err == null do
                successes += 1
        }
        return successes
    }
}

// --- tests ---

#test
{
    var ledger: Ledger
    ledger.reset()
    catch ledger.deposit(0, 1000)
    @assert(@err == null)
    @assert(ledger.accounts[0].balance == 1000)
    @assert(ledger.totalOps == 1)
}

#test
{
    var ledger: Ledger
    ledger.reset()
    catch ledger.deposit(99, 10)
    @assert(@err != null)
    let err = cast(BankError) @err
    @assert(err.kind == .UnknownAccount)
    @assert(err.account == 99)
    @assert(err.message == "unknown account")
}

#test
{
    var ledger: Ledger
    ledger.reset()
    catch ledger.deposit(0, 0)
    @assert(@err != null)
    let err = cast(BankError) @err
    @assert(err.kind == .InvalidAmount)
}

#test
{
    var ledger: Ledger
    ledger.reset()
    catch ledger.withdraw(0, 50)
    @assert(@err != null)
    let err = cast(BankError) @err
    @assert(err.kind == .InsufficientFunds)
    @assert(err.amount == 50)
}

#test
{
    var ledger: Ledger
    ledger.reset()
    ledger.accounts[0].frozen = true
    catch ledger.deposit(0, 100)
    @assert(@err != null)
    let err = cast(BankError) @err
    @assert(err.kind == .FrozenAccount)
    @assert(err.account == 0)
}

// Successful transfer: balances move, commit counter increments, no rollback.
#test
{
    var ledger: Ledger
    ledger.reset()
    catch ledger.deposit(0, 1000)
    catch ledger.transfer(0, 1, 300)
    @assert(@err == null)
    @assert(ledger.accounts[0].balance == 700)
    @assert(ledger.accounts[1].balance == 300)
    @assert(ledger.committed == 1)
    @assert(ledger.rolledBack == 0)
}

// Deposit leg fails: defer #err fires, source balance restored, rolledBack bumps.
#test
{
    var ledger: Ledger
    ledger.reset()
    catch ledger.deposit(0, 1000)
    ledger.accounts[1].frozen = true
    catch ledger.transfer(0, 1, 300)
    @assert(@err != null)
    let err = cast(BankError) @err
    @assert(err.kind == .FrozenAccount)
    @assert(err.account == 1)
    @assert(ledger.accounts[0].balance == 1000)
    @assert(ledger.accounts[1].balance == 0)
    @assert(ledger.committed == 0)
    @assert(ledger.rolledBack == 1)
}

// Withdraw leg fails before either defer is registered, so no rollback fires.
#test
{
    var ledger: Ledger
    ledger.reset()
    catch ledger.deposit(0, 100)
    catch ledger.transfer(0, 1, 500)
    @assert(@err != null)
    let err = cast(BankError) @err
    @assert(err.kind == .InsufficientFunds)
    @assert(ledger.accounts[0].balance == 100)
    @assert(ledger.accounts[1].balance == 0)
    @assert(ledger.committed == 0)
    @assert(ledger.rolledBack == 0)
}

// Two back-to-back successful transfers without the batch helper.
#test
{
    var ledger: Ledger
    ledger.reset()
    catch ledger.deposit(0, 1000)
    catch ledger.transfer(0, 1, 100)
    @assert(@err == null)
    @assert(ledger.committed == 1)
    catch ledger.transfer(0, 1, 200)
    @assert(@err == null)
    @assert(ledger.committed == 2)
}

// Two back-to-back successful transfers via runBatch.
#test
{
    var ledger: Ledger
    ledger.reset()
    catch ledger.deposit(0, 1000)
    catch ledger.deposit(2, 500)

    var simple: [2] Transfer
    simple[0] = Transfer{0, 1, 100}
    simple[1] = Transfer{2, 3, 200}
    let n0 = ledger.runBatch(simple)
    @assert(n0 == 2)
    @assert(ledger.committed == 2)
}

// Mixed batch: successes commit, failures roll back (when past the withdraw).
#test
{
    var ledger: Ledger
    ledger.reset()
    catch ledger.deposit(0, 1000)
    catch ledger.deposit(2, 500)

    var ops: [4] Transfer
    ops[0] = Transfer{0, 1, 100}
    ops[1] = Transfer{0, 99, 50}
    ops[2] = Transfer{2, 3, 200}
    ops[3] = Transfer{0, 1, 10000}

    let n = ledger.runBatch(ops)
    @assert(n == 2)
    @assert(ledger.committed == 2)
    @assert(ledger.rolledBack == 1)
    @assert(ledger.accounts[0].balance == 900)
    @assert(ledger.accounts[1].balance == 100)
    @assert(ledger.accounts[2].balance == 300)
    @assert(ledger.accounts[3].balance == 200)
}

// trycatch silently dismisses the error; @err stays null.
#test
{
    var ledger: Ledger
    ledger.reset()
    catch ledger.deposit(0, 100)
    trycatch ledger.transfer(0, 1, 500)
    @assert(@err == null)
    @assert(ledger.accounts[0].balance == 100)
    @assert(ledger.rolledBack == 0)
}

// Block-level catch: multiple throwing calls under a single boundary.
// The block aborts on the first failure; later statements are skipped.
#test
{
    var ledger: Ledger
    ledger.reset()

    catch
    {
        ledger.deposit(0, 200)
        ledger.deposit(1, 300)
        ledger.withdraw(0, 50)
    }

    @assert(@err == null)
    @assert(ledger.accounts[0].balance == 150)
    @assert(ledger.accounts[1].balance == 300)

    catch
    {
        ledger.deposit(0, 100)
        ledger.withdraw(5, 999)
        ledger.deposit(1, 100)
    }

    @assert(@err != null)
    let err = cast(BankError) @err
    @assert(err.kind == .InsufficientFunds)
    @assert(ledger.accounts[0].balance == 250)
    @assert(ledger.accounts[1].balance == 300)
}
