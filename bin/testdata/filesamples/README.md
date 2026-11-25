# FileSamples fixtures

The corpus contains 808 distinct downloads from the [FileSamples catalogue](https://filesamples.com/).
The `samples` tree keeps the original category, format and name. Module tests can open a sample
from the common `bin/testdata/filesamples` directory. For example, the manifest path
`samples/document/pdf/sample1.pdf` is relative to this directory.

`catalogue.json` pins source URLs, relative paths, byte counts and SHA-256 digests. Four format
pages (SFW, WPG, X3F and XCF) listed no downloadable samples when the catalogue was captured on
2026-11-25.

The payload tree is populated locally. It takes about 12 GiB and includes files over 100 MiB.
Run the following command from this directory to restore the pinned corpus using Python 3.10 or
later and curl. Files that match the manifest are reused. Pass `--verify` to check the local files
without making network requests.

```powershell
python download-filesamples.py
```
