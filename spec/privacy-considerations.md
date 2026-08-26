# Privacy considerations

CAP is an evidence protocol: it binds signatures to byte-exact claims and
reports structural facts. It carries no identity-proofing, account, or
behavioral-tracking surface — but its artifacts are signed documents that
third parties can verify and correlate. This document states what
protocol-visible data exists, what never enters the protocol, and the
processing rules implementers must respect.

## Data the protocol carries

- **Public keys and key identifiers.** Party descriptors declare Ed25519
  public keys with bounded-ASCII `kid` hints. Public keys are
  pseudonymous, not identifying by themselves, but a key reused across
  contexts becomes a correlation handle. Rotating keys per relationship
  limits linkability at the cost of history continuity — a deployment
  decision, not a protocol one.
- **Digests.** Most claims reference content by domain-separated digest
  (revisions, deployments, grants, legal text). Digests are opaque to
  parties without the preimage, but they are deterministic: the same
  content under the same domain always produces the same digest, so a
  known preimage is globally recognizable. Where content confidentiality
  matters, the content itself must be exchanged out of band — the
  `uri_hint` members are optional hints, never fetch targets.
- **Timestamps.** Effective, accepted, occurred, recorded, issued, and
  termination instants are caller-declared UTC values. They enable
  timeline correlation across artifacts by the same parties.
- **Attestation hints.** Descriptor `attestation_hints` are
  non-normative, never dereferenced by CAP, and should be treated as
  potentially sensitive pointers by hosting systems that display or log
  descriptors.
- **Receipt bindings.** Receipts bind an invocation to a governing
  revision, a deployment digest, and a grant identity with
  decision/outcome claims. They are action evidence, not personal data —
  but grant identifiers and invocation IDs may be correlatable by
  whoever holds the grant registry.

## Data the protocol never carries

CAP has no name, email, address, phone, or national-identifier member
anywhere in its closed claim sets; unknown members fail closed at
decode. There is no optional identity block to populate. Organizational
identity assertions belong to attestation profiles layered as extensions
(see `registry-policy.md`), and those bodies are quarantined unless a
registry schema is bound.

## Processing rules for implementers

- **Facts records are the safe surface.** Verification results are
  redacted structural facts; retained signed artifacts are not exposed
  through them. Hosts should log facts, not raw artifacts.
- **Failures are value-free.** Error codes never echo rejected input, so
  verification failures are safe to log without scrubbing. Hosts must
  not wrap verification with logging that re-introduces the rejected
  bytes.
- **Artifacts are third-party verifiable by design.** Any holder of a
  descriptor plus a receipt can verify both offline. Persistence,
  retention periods, and disclosure of artifacts are host policy; the
  protocol's contribution is that nothing in an artifact is hidden from
  anyone who obtains it — privacy therefore depends on distribution
  control, which is explicitly out of CAP's scope.
- **No clock, no telemetry.** CAP reads no clock, performs no network
  I/O, and emits no telemetry. Any such behavior is host-added.
