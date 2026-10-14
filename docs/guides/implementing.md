# Implement CAP in another language

An implementation of CAP verification must meet the requirements of the
specification, and it must reproduce every case in the
[conformance corpus](conformance.md) and write a report whose bytes equal the report
the Elixir runner writes for the same corpus. The corpus is a required check, not a
proof: it covers a finite set of inputs, so passing it does not show that every other
input gets the specified result. This page covers what you need for the corpus: the corpus layout, what each case runs, the report format, the comparison
procedure, and the exact encoding rules where byte equality is easy to miss.

The [core specification](../../spec/core.md) and the [wire schemas](../../spec/schemas/README.md)
are normative. Where this page and the specification disagree, the specification wins,
and the difference is an erratum.

## The second implementation

The TypeScript verifier is the second implementation of this procedure. Use it as a
reference when your results differ from the expected ones.

- Repository: [`baselabs/charter_agreement_protocol_typescript`](https://github.com/baselabs/charter_agreement_protocol_typescript).
- npm package: [`@charter-agreement-protocol/verifier`](https://www.npmjs.com/package/@charter-agreement-protocol/verifier),
  command `cap-verifier`. It has no runtime dependencies and needs Node 24.8 or later.
- `core.ts` holds the corpus loader, every surface and the report writer; `cli.ts` is
  the command line. `check-corpus.mjs` checks corpus integrity only; it does not
  recompute cases or write a report.
- `priv/verifier-source.json` in this package names the commit of that repository
  that CAP's own agreement check ran against.

From a checkout of that repository:

```console
$ node --experimental-strip-types --no-warnings cli.ts --corpus /path/to/priv/conformance
```

A verifier release is built for one corpus. It refuses a corpus whose index SHA-256 is
not the one it was built with, so use the release that matches the corpus you test.

## Corpus layout

```text
priv/conformance/
  index.json
  cases/
    base64url-decode.json
    json-decode.json
    ...one file per surface...
```

The index is canonical JSON (see [Canonical JSON](#canonical-json) below). Case
files use the same encoding except that a float whose canonical spelling has no
fraction or exponent carries `.0`, for example `2.0`. This preserves numeric token
types in inputs. Readers must retain those types, including inside `claims` and
profile revision bounds; converting `2.0` to an integer changes the input. No file
has a trailing newline. A loader reads the whole directory: any file the index does not
list, including a hidden file, makes the corpus invalid.

`index.json` has exactly these members:

| Member | Content |
|---|---|
| `format` | `"charter-agreement-protocol-conformance-corpus-index"` |
| `files` | One entry per case file: `path` (`cases/<name>.json`), `cases` (the count), `sha256_base64url` (the SHA-256 of the file's bytes) |
| `total_cases` | The sum of the per-file counts |
| `applicability` | For each surface, one cell per class: a case count, or `{"n_a": reason}` |
| `registry_digest` | The extension registry digest |
| `corpus_digest` | The digest of this index without its own `corpus_digest` member |

The corpus digest is
`SHA-256("charter-agreement-protocol/corpus-index" || 0x00 || canonical(index without "corpus_digest"))`,
written as `sha-256:` followed by unpadded base64url.

Each case file has exactly two members: `format`
(`"charter-agreement-protocol-conformance-cases"`) and `cases`, a list. Each case has
exactly five members:

| Member | Content |
|---|---|
| `id` | Unique across the whole corpus |
| `surface` | The operation to run (see [What each surface runs](#what-each-surface-runs)) |
| `class` | A coverage label for the applicability table |
| `input` | The surface's input, as JSON |
| `expect` | `{"status": "valid", "output": {...}}` or `{"status": "invalid", "error_code": "..."}` |

The `class` member is not part of the expected result. A case in class
`invalid_encoding` can expect the error code `duplicate_member`, for example. Compare
against `expect` only.

## Loading a corpus

Load in this order, and refuse the corpus at the first failure:

1. Read `index.json`. Its raw SHA-256 must equal the index SHA-256 in the
   [identity table](conformance.md#identities).
2. Decode it and check that it is canonical, has exactly the members above, and
   carries the extension registry digest your implementation was built with.
3. Recompute the corpus digest and compare.
4. Refuse an index with `total_cases` of 0.
5. Check that the directory holds exactly `index.json` plus the listed files, and that
   each file's SHA-256 matches its entry.
6. Decode each case file, check its encoding with float tokens retained, and check
   its shape.
7. Check each file's case count and the total.
8. Check every case's shape, its surface and class names, and that ids are unique.
9. Check the applicability table: for each surface and class, a count must equal the
   number of cases with that pair, and an `n_a` cell must have no cases.

The Elixir CLI also refuses a directory with more than 64 files or more than 32 MiB
in total, and any entry that is not a regular file or a directory.

## What each surface runs

Run the cases in index order: files in the order `files` lists them, cases in file
order. For each case, compute the result document. A failure is
`{"status": "invalid", "error_code": <code>}` with the protocol error code as a
string. A success is `{"status": "valid", "output": <output>}` with the output below.

| Surface | Input members | Output on success |
|---|---|---|
| `base64url.decode` | `text` | `bytes_base64url`: the decoded bytes, encoded again |
| `json.decode` | `text`, or `bytes_base64url` (raw bytes), or `kind` and `value` (a non-binary input); optional `limits` | The tagged value: `{"tag": "null"}`, `{"tag": t, "value": v}` for booleans, integers, floats and strings, `{"tag": "array", "items": [...]}`, `{"tag": "object", "members": [[name, value], ...]}` in received order |
| `canonicalization.encode` | `text` (check that it is canonical), or a tagged value to encode | `text`: the canonical bytes as a string |
| `digest.hash` | `domain` and `bytes_base64url`, optional `tagged`; or `kind` and `value` | `{"algorithm": "sha-256"}` without `tagged`; `{}` when `tagged` matches |
| `schema.validate` | `members`: an object | `members`, unchanged |
| `party_descriptor.verify` | `compact`; either `predecessor` (always `null`) or `predecessor_compacts` (the predecessor history, genesis first, each entry verified under the full profile against the one before it); optional `profile` (as in `chain.verify_profile`) | `descriptor_digest`, `party_id`, `descriptor_number` |
| `descriptor_chain.verify` | `compacts` | `topology`, `positions` (descriptor digest to position), `sibling_descriptors` |
| `charter_revision.decode` | `text` | `revision_digest`, `revision_number`, `precedence_declaration`, and `abp_binding` (the revision's single binding: `blueprint_id`, `release_number`, `content_digest`, `deployment_digest`) |
| `acceptance.verify` | `compact`, `revision_text`, `descriptor_compacts`; optional `profile` (as in `chain.verify_profile`) | `acceptance_digest`, `revision_digest`, `party_descriptor_digest`, `descriptor_position` |
| `acceptance.equivocation` | `descriptor_compacts`, `signed_revisions` (two `{compact, revision_text}`) | `kind`, `revision_number`, `revision_digests`, `winner` (always `null`) |
| `termination.verify` | `compact`, `revision_text`, `descriptor_compacts`; optional `profile` (as in `chain.verify_profile`) | `termination_digest`, `governing_revision_digest`, `party_descriptor_digest`, `reason_code`, `descriptor_position` |
| `chain.verify` | `revisions`, `acceptances`, `descriptors`, `terminations`; optional `limits` | `charter_id`, `topology`, `accepted_revision_digests`, `superseded_revision_digests` |
| `chain.verify_profile` | the `chain.verify` lists plus `profile`: `algorithms` (a list of `alg` names) and `revisions` (an object with `min` and `max`) | `charter_id`, `topology` |
| `governing_revision` | the `chain.verify` lists plus `queries` (each with `at`) | `governing_revisions`: per query, a revision digest, `"contested"` or `"none"` |
| `receipt.verify` | `compact`, and as context either `chain` (the four artifact lists) or `revision_text` (a bare revision); optional `profile` (as in `chain.verify_profile`) | `receipt_digest`, `revision_number`, `revision_digest`, `decision`, `outcome`, `chain_conflict`, `governing_match`, `deployment_digest_matched`, `optional_extensions_retained` |
| `signing.prepare` | `kind`, `kid`, `claims`, base64url `public_key`, optional `algorithm`, `limits` and `profile`; `context` is null or `predecessor_compacts` for a descriptor, `set` for acceptance and termination, or `chain` / `revision_text` for a receipt | `protected_segment`, `payload_segment`, `key` (`"matched"` or `"unnamed"`), or an error code |

Details that matter for byte equality:

- Atoms become strings: `"linear"`, `"head"`, `"accepted"` and so on.
- `limits` names some limit fields; every field it does not name takes its
  [default](limits-and-profiles.md), and an out-of-range value fails with
  `invalid_limits`. Cases without `limits` use the defaults.
- Limits come only from the case input's top-level `limits`. A nested chain
  view holds exactly `revisions`, `acceptances`, `descriptors` and
  `terminations`; any other member returns `invalid_type`.
- A missing `profile` uses the full profile. Within a profile object, a missing
  `algorithms` or `revisions` member uses the full axis. An explicit null profile
  or axis returns `invalid_profile` on every surface. Revision bounds must be
  integer tokens. Unknown members and other malformed profiles also return
  `invalid_profile`.
- A runner returns a typed result for every JSON input. A non-object `input` or
  malformed case scaffolding returns `invalid_type`; failures while reading a
  context retain the underlying error code. Options are checked before surface
  inputs: limits first, then profile, then the operation's input values.
- A `kind`/`value` input whose JSON value type does not match `kind` returns
  `invalid_type` on every surface.
- `digest.hash` names its domain by the names in [Digests](#digests). A `kind`/`value`
  input stands for a value that is not bytes and must fail with `invalid_type`.
- `canonicalization.encode` tagged inputs are an object with `members` of
  `[name, {"tag": "integer", "value": n}]` pairs, an integer given as decimal text in
  `text_value`, a string given as one code point in hex (`string_codepoint`), or
  `{"kind": "improper_object"}`, which stands for a malformed object and must fail with
  `invalid_type`.
- `schema.validate` checks `members` against one fixed test schema: a single required
  field `name` whose value is a string of 2 to 4 lowercase ASCII letters.
- In a `governing_revision` query, only `at` is input. Any other member is ignored.

The Elixir runner is `CharterAgreementProtocol.Conformance.Runner`; the TypeScript
one is in `core.ts`. When a case disagrees, read both.

## The report

The report is one canonical JSON object followed by a single line feed (`0x0A`). It
has exactly these members:

| Member | Content |
|---|---|
| `format` | `"charter-agreement-protocol-conformance-report"` |
| `agreement` | `true` when every case agreed and there is at least one case |
| `exit_status` | `0` when `agreement` is true, otherwise `1` |
| `total`, `agreed`, `disagreed` | Case counts |
| `corpus_digest` | From the index |
| `registry_digest` | From the index |
| `index_sha256_base64url` | The raw SHA-256 of the index bytes |
| `results` | One entry per case, in run order: `id`, `surface`, `agree`, `expected`, `actual` |

`expected` is the case's `expect` member; `actual` is the result document you
computed. A case agrees when the two documents are equal. The wire grammar is
[`corpus-report.json`](../../spec/schemas/README.md).

## Byte agreement

1. Load the corpus as above.
2. Implement every surface, including Ed25519 and ML-DSA signature verification over
   the exact compact signing-input bytes (`base64url(header) "." base64url(payload)`).
3. Compute every result document and compare whole documents, not just the status.
4. Write the report and compare its bytes with the Elixir runner's report over the
   same directory, trailing line feed included.

Run step 4 against the corpus in a source checkout and against the corpus inside the
Hex package; both must give the same bytes. A corpus whose index SHA-256 is not the
released value is not this corpus, however consistent it is, and both existing
verifiers refuse it.

## Canonical JSON

CAP signs and digests canonical JSON. The output follows RFC 8785 (JSON
Canonicalization Scheme). CAP narrows it in one important way: it does not
canonicalize what it receives. Received bytes must already be canonical, and anything
else fails with `non_canonical_bytes`.

### Where CAP follows RFC 8785

- Object members are sorted by their names as unsigned UTF-16 code units, so a name
  outside the Basic Multilingual Plane (stored as a surrogate pair) sorts before
  `U+FFFD`.
- No whitespace between tokens. Output is UTF-8.
- Strings escape `"` as `\"` and `\` as `\\`; U+0008, U+0009, U+000A, U+000C and
  U+000D as `\b`, `\t`, `\n`, `\f`, `\r`; every other byte below `0x20` as `\u00xx`
  with lowercase hex. Everything else is written as is, including `/`, `0x7F` and
  U+2028. Strings are not Unicode-normalized.
- Numbers use the ECMAScript shortest round-trip spelling: `1`, `0.1`, `100000000000000000000`
  (1e20), `1e+21`, `0.000001`, `1e-7`, `5e-324`. Negative zero is written `0`.

### Where CAP narrows it

| Input | RFC 8785 | CAP |
|---|---|---|
| `1.0`, `1e2`, ` 1`, `"\/"`, `"\u0041"`, `-0` | Rewritten to canonical form | Rejected: `non_canonical_bytes` |
| An integer token above 2^53 − 1 in magnitude, such as `9007199254740993` | Rounded to the nearest double | Rejected: `number_not_double_expressible`. Accepted only when the token is already the exact spelling of a double, such as `9007199254740992` |
| An integer value above 2^53 − 1 given to the encoder | Not applicable | Rejected: `integer_magnitude` |
| An integer token longer than 21 digits, or a fractional or exponent token longer than 32 bytes | Parsed | Rejected: `number_not_double_expressible`. Neither can be a canonical spelling |
| A number outside the double range, such as `1e999` | Error | Rejected: `invalid_number` |
| A duplicate member name | Not I-JSON | Rejected: `duplicate_member` |
| A noncharacter (U+FDD0 to U+FDEF, or any code point ending in FFFE or FFFF), raw or escaped | Not I-JSON | Rejected: `invalid_encoding` |
| A lone surrogate escape such as `"\uD800"` | Not I-JSON | Rejected: `invalid_syntax` |
| A leading byte order mark | Not part of the JSON text | Rejected: `invalid_syntax` |
| Invalid UTF-8 | Not I-JSON | Rejected: `invalid_encoding` |

### Integers and floats

The decoder keeps the token type. A token with no fraction and no exponent is an
integer when its magnitude is at most 2^53 − 1. Any other accepted number is a float.
This shows in `json.decode` output, which tags each number `integer` or `float`.

The encoder writes a whole float the way ECMAScript does, so `{:float, 1.0}` encodes
as `1`, and `1` decodes as an integer. Decoding a canonical document and encoding it
again always gives the same bytes.

You can check bytes against the Elixir encoder:

```console
$ mix run --no-start -e 'IO.inspect(CharterAgreementProtocol.Canonicalization.encode_plain(%{"b" => 1.0, "a" => [nil, true]}))'
{:ok, "{\"a\":[null,true],\"b\":1}"}
```

## Other encodings

### base64url

Unpadded, URL-safe alphabet only. Padding fails with `base64url_padded`. A character
outside the alphabet, a single trailing character, or non-zero trailing bits (`AR`)
fail with `base64url_invalid`. The decoder re-encodes what it decoded and requires the
same text.

### Digests

A digest is `SHA-256(separator || 0x00 || content)`, written `sha-256:` followed by 43
unpadded base64url characters. The domain names below are the ones `digest.hash`
cases use.

| Domain | Separator |
|---|---|
| `party_descriptor_content` | `charter-agreement-protocol/party-descriptor-content` |
| `charter_revision_content` | `charter-agreement-protocol/charter-revision-content` |
| `acceptance_content` | `charter-agreement-protocol/acceptance-content` |
| `termination_content` | `charter-agreement-protocol/termination-content` |
| `receipt_content` | `charter-agreement-protocol/receipt-content` |
| `legal_text` | `charter-agreement-protocol/legal-text` |
| `signature` | `charter-agreement-protocol/signature` |
| `extension_schema` | `charter-agreement-protocol/extension-schema` |
| `extension_registry` | `charter-agreement-protocol/extension-registry` |
| `signature_registry` | `charter-agreement-protocol/signature-registry` |
| `conformance_report` | `charter-agreement-protocol/conformance-report` |
| `corpus_index` | `charter-agreement-protocol/corpus-index` |
| `specification` | `charter-agreement-protocol/specification` |

A digest with another algorithm tag fails with `digest_algorithm_unsupported`; a
malformed one fails with `digest_encoding_invalid`. Compare digests in constant time.

### Timestamps

RFC 3339 with an uppercase `T` and a `Z` offset and optional fractional seconds:
`2026-08-25T12:00:00Z`. Second `60` is allowed only at 23:59 on June 30 or December 31,
for example `2026-12-31T23:59:60Z`; CAP checks that rule only and consults no
leap-second table. Lowercase `t` or `z`, a numeric offset, a space separator and an
empty fraction (`12:00:00.Z`) all fail. The timestamp members of the core artifacts
must also be 1 to 64 bytes long. Extension bodies apply their own schemas: the
indexed-price `observation_instant` has no such length bound.

### Signed artifacts

The four signed artifacts are attached compact JWS. The protected header and the
payload must each be canonical JSON. The header has exactly `alg`, `kid` and `typ`.
`kid` is 1 to 128 bytes of `A-Z a-z 0-9 - . _ ~`. [Artifacts](artifacts.md) lists the
`alg` names, the `typ` values and every claim.

### Schema validation order

When an object has several faults, the error code depends on which check runs first.
Validation finishes one stage for every field before it starts the next:

1. unknown member;
2. missing required member;
3. wrong type;
4. constraint;
5. cardinality;
6. nested object or list;
7. cross-field rule.

Within a stage, the schema's field order decides which field is reported, never the
order of members in the received object.

## Run the Elixir CLI

In a project that depends on `charter_agreement_protocol`:

```console
$ mix run --no-start -e 'System.halt(CharterAgreementProtocol.Conformance.Cli.run(["--corpus", Application.app_dir(:charter_agreement_protocol, "priv/conformance")]))' > report.json
```

The report goes to standard output. Exit status `0` means every case agreed, `1` means
the corpus did not load or a case disagreed (with `conformance verification failed` on
standard error), and `2` means the arguments were wrong. Pass any directory to
`--corpus` to run a copy, for example the one inside your own implementation's test
data.
