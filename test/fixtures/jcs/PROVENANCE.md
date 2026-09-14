# RFC 8785 (JCS) external test vectors

Downloaded 2026-09-14 from the reference suite maintained by the RFC 8785
co-author: https://github.com/cyberphone/json-canonicalization
(`testdata/input/*.json` paired with `testdata/output/*.json`, commit on
master at download time). Each `*.in.json` is a non-canonical input document
and the matching `*.out.json` is its canonical serialization. These anchor
the implementation to externally published answers rather than self-minted
expectations.
