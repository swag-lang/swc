# `if x.count` crashes code generation when `x` resolves `opCount`

- Area: compiler
- Found while: testing an image codec name, where the condition was `.count` over a
  `Core.String`.
- Observation: an `if` whose whole condition is `value.count`, and whose type resolves the
  count through a user `opCount` method, dereferences a null payload in code generation and takes
  the process down. The same intrinsic compiles in neighbouring positions, so the defect is in
  how the statement matches its condition child, not in `.count` itself.
- Evidence: the failure reads a null state after the condition callback never created its payload.
  This standalone file reproduces it:

  ```swag
  struct Box { length: u64 }

  impl Box
  {
      mtd const opCount()->u64 { return .length }
  }

  func classify(box: Box)->s32
  {
      if box.count do
          return 1
      return 0
  }
  ```

  The neighbouring forms compile and run, so the trigger is the specialized count path.
- Next step: trace both condition callbacks and compare the walked references.
