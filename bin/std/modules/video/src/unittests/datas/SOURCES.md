# Video fixture sources

`rav1e-c420jpeg.y4m` is an unmodified copy of
[`tests/small_input.y4m`](https://github.com/xiph/rav1e/blob/6a8dbbe966744a98090337fc642839234a315fbe/tests/small_input.y4m)
from the rav1e project. It is a five-frame, 64 by 64 pixel YUV4MPEG2 stream using
8-bit `C420jpeg` chroma and progressive scan order.

- SHA-256: `c21278d4d829764b3bb4d1b3285ce660d1b0d0abc19c6f174a6d52ef5b853a70`
- License: BSD 2-Clause; see `LICENSE.bsd-2-clause.txt`.

`bars-scroll-c420.y4m` is the long stream the streaming tests read. It is 400 frames of
128 by 72 pixels at 25 frames per second, 8-bit `C420jpeg` chroma, progressive, 5 532 042
bytes. Its content is synthetic and generated for this repository:

- Eight BT.601 limited-range colour bars, 16 pixels wide — white, yellow, cyan, green,
  magenta, red, blue, black — scrolling by exactly one bar per frame, so the bar covering a
  given column is a known function of the frame index. Bar edges fall on even coordinates,
  so 4:2:0 chroma carries them exactly.
- A 16 by 16 block in the top-left corner whose luma is `16 + index % 220` and whose chroma
  is neutral. It identifies the frame: a seek that lands on the wrong frame, or a stream
  walked from the wrong offset, cannot produce the expected value.

- SHA-256: `ee715b25c78937abe7c9b66a45260fdfbeff3b0951e5e72c224cd768a59a2570`
- License: same as this repository.
