# SVG Web Platform Test fixtures

These files are unmodified snapshots from public
[web-platform-tests revision 54f8f933629e7c010ae98a246729af01f8abcda5](https://github.com/web-platform-tests/wpt/tree/54f8f933629e7c010ae98a246729af01f8abcda5)
and remain under its BSD 3-Clause license:

- `line-dasharray.svg` from `svg/shapes/line-dasharray.svg`
- `radialgradient-basic-002.svg` from `svg/pservers/reftests/radialgradient-basic-002.svg`
- `circle-01.svg` from `svg/shapes/circle-01.svg`
- `render-until-error.svg` from `svg/path/error-handling/render-until-error.svg`

The Pixel tests use them as a small real-world parsing corpus. They intentionally
retain WPT metadata and unsupported elements so the parser also exercises safe
subtree skipping.
