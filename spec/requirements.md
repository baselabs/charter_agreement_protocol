# Requirements matrix

CAP never authorizes.

GENERATED from `CharterAgreementProtocol.RequirementMap` — do not edit by
hand. `mix conformance.verify` checks this render is fresh and that
coverage is bidirectional: every requirement carries evidence, and every
corpus cell and named source mutation is bound to at least one
requirement. Regenerate with `mix run scripts/render_requirements.exs`.

## Bound evidence

- Requirements: 40
- Corpus cells: 53
- Named mutations: 22

## Requirements

### CAP-CANONICALIZATION-ecmascript-number

- Corpus: `canonicalization.encode:valid`
- Gate: `CharterAgreementProtocol.Architecture.PublicContractCoverageTest`
- Mutation: `jcs-number-defeat`

### CAP-BASE64URL-unpadded-only

- Corpus: `base64url.decode:invalid_encoding`
- Gate: `CharterAgreementProtocol.Architecture.ConstantTimeCompareShapeTest`
- Mutation: `padding-acceptance`

### CAP-DIGEST-domain-separation

- Corpus: `digest.hash:valid`
- Gate: `CharterAgreementProtocol.Architecture.PortfolioIdentityCensusTest`
- Mutation: `separator-collapse`

### CAP-SCHEMA-closed-members

- Corpus: `schema.validate:unknown_member`
- Gate: `CharterAgreementProtocol.Architecture.PublicContractCoverageTest`
- Mutation: `unknown-member-acceptance`

### CAP-PARTY-DESCRIPTOR-signature-required

- Corpus: `party_descriptor.verify:signature_invalid`
- Gate: `CharterAgreementProtocol.Architecture.SigningBoundaryTest`
- Mutation: `chain-signature-skip`

### CAP-DIGEST-equality-required

- Corpus: `digest.hash:digest_mismatch`
- Gate: `CharterAgreementProtocol.Architecture.ConstantTimeCompareShapeTest`
- Mutation: `digest-equality-skip`

### CAP-SIGNATURE-ed25519-verification

- Corpus: `acceptance.verify:signature_invalid`
- Gate: `CharterAgreementProtocol.Architecture.SigningBoundaryTest`
- Mutation: `ed25519-defeat`

### CAP-COMPACT-JWS-type-isolation

- Corpus: `termination.verify:signature_invalid`
- Gate: `CharterAgreementProtocol.Architecture.PortfolioIdentityCensusTest`
- Mutation: `typ-confusion`

### CAP-TERMINATION-reason-closed

- Corpus: `termination.verify:invalid_constraint`
- Gate: `CharterAgreementProtocol.Architecture.PublicContractCoverageTest`
- Mutation: `reason-code-uncheck`

### CAP-CHAIN-highest-precedence

- Corpus: `governing_revision:precedence_selection`
- Gate: `CharterAgreementProtocol.Architecture.ChainRoutingShapeTest`
- Mutation: `precedence-lowest`

### CAP-FACTS-union-complete

- Corpus: `receipt.verify:valid`
- Gate: `CharterAgreementProtocol.Architecture.FactsConstructionTest`
- Mutation: `facts-union-suppression`

### CAP-CHAIN-fork-topology

- Corpus: `chain.verify:chain_fork`
- Gate: `CharterAgreementProtocol.Architecture.ChainRoutingShapeTest`
- Mutation: `fork-topology-suppressed`

### CAP-CHAIN-contested-refusal

- Corpus: `receipt.verify:chain_fork`
- Gate: `CharterAgreementProtocol.Architecture.ChainRoutingShapeTest`
- Mutation: `contested-tie-resolved`

### CAP-ACCEPTANCE-exact-claims

- Corpus: `acceptance.verify:invalid_constraint`
- Gate: `CharterAgreementProtocol.Architecture.FactsConstructionTest`
- Mutation: `acceptance-claims-mismatch-accept`

### CAP-PARTY-DESCRIPTOR-predecessor-binding

- Corpus: `descriptor_chain.verify:chain_invalid`
- Gate: `CharterAgreementProtocol.Architecture.ChainRoutingShapeTest`
- Mutation: `prev-binding-skip`

### CAP-RECEIPT-revision-number-match

- Corpus: `receipt.verify:invalid_constraint`
- Gate: `CharterAgreementProtocol.Architecture.FactsConstructionTest`
- Mutation: `receipt-number-crosscheck-skip`

### CAP-RECEIPT-conflict-visible

- Corpus: `receipt.verify:chain_fork`
- Gate: `CharterAgreementProtocol.Architecture.TermEvaluationVocabularyTest`
- Mutation: `receipt-conflict-silenced`

### CAP-ACCEPTANCE-equivocation-refusal

- Corpus: `acceptance.equivocation:equivocation`
- Gate: `CharterAgreementProtocol.Architecture.SigningBoundaryTest`
- Mutation: `equivocation-guard-removed`

### CAP-SIGNING-branch-freshness

- Corpus: `descriptor_chain.verify:descriptor_fork`
- Gate: `CharterAgreementProtocol.Architecture.SigningBoundaryTest`
- Mutation: `stale-branch-guard-removed`

### CAP-PARTY-DESCRIPTOR-superseded-visible

- Corpus: `descriptor_chain.verify:descriptor_superseded`
- Gate: `CharterAgreementProtocol.Architecture.FactsConstructionTest`
- Mutation: `superseded-descriptor-silent-accept`

### CAP-CHAIN-supersession-applied

- Corpus: `chain.verify:supersession`
- Gate: `CharterAgreementProtocol.Architecture.ChainRoutingShapeTest`
- Mutation: `supersession-ignore`

### CAP-CONFORMANCE-expectations-bound

- Corpus: `base64url.decode:valid`
- Gate: `CharterAgreementProtocol.Architecture.ReleaseGateTest`
- Mutation: `corpus-expectation-flip`

### CAP-ACCEPTANCE-valid-pairing

- Corpus: `acceptance.verify:valid`
- Gate: `CharterAgreementProtocol.Architecture.FactsConstructionTest`

### CAP-BASE64URL-exact-boundary

- Corpus: `base64url.decode:exact_bound`
- Gate: `CharterAgreementProtocol.Architecture.PublicContractCoverageTest`

### CAP-CANONICALIZATION-noncanonical-rejected

- Corpus: `canonicalization.encode:non_canonical_bytes`, `canonicalization.encode:invalid_encoding`, `canonicalization.encode:invalid_type`
- Gate: `CharterAgreementProtocol.Architecture.PublicContractCoverageTest`

### CAP-CHAIN-valid-topology

- Corpus: `chain.verify:valid`
- Gate: `CharterAgreementProtocol.Architecture.ChainRoutingShapeTest`

### CAP-CHARTER-REVISION-valid-genesis

- Corpus: `charter_revision.decode:valid`
- Gate: `CharterAgreementProtocol.Architecture.FactsConstructionTest`

### CAP-CHARTER-REVISION-closed-members

- Corpus: `charter_revision.decode:unknown_member`, `charter_revision.decode:extension_unknown_critical`
- Gate: `CharterAgreementProtocol.Architecture.PublicContractCoverageTest`

### CAP-CHARTER-REVISION-claim-constraints

- Corpus: `charter_revision.decode:invalid_constraint`, `charter_revision.decode:invalid_type`, `charter_revision.decode:missing_required`, `charter_revision.decode:invalid_cardinality`
- Gate: `CharterAgreementProtocol.Architecture.PublicContractCoverageTest`

### CAP-DESCRIPTOR-CHAIN-signature-required

- Corpus: `descriptor_chain.verify:signature_invalid`
- Gate: `CharterAgreementProtocol.Architecture.SigningBoundaryTest`

### CAP-DIGEST-bytes-only

- Corpus: `digest.hash:invalid_type`
- Gate: `CharterAgreementProtocol.Architecture.PublicContractCoverageTest`

### CAP-JSON-decoder-closed-grammar

- Corpus: `json.decode:valid`, `json.decode:invalid_type`, `json.decode:invalid_encoding`
- Gate: `CharterAgreementProtocol.Architecture.PublicContractCoverageTest`

### CAP-JSON-number-boundaries

- Corpus: `json.decode:exact_bound`, `json.decode:boundary_near`, `json.decode:maximum_plus_one`
- Gate: `CharterAgreementProtocol.Architecture.PublicContractCoverageTest`

### CAP-PARTY-DESCRIPTOR-valid-genesis

- Corpus: `party_descriptor.verify:valid`
- Gate: `CharterAgreementProtocol.Architecture.FactsConstructionTest`

### CAP-RECEIPT-signature-required

- Corpus: `receipt.verify:signature_invalid`
- Gate: `CharterAgreementProtocol.Architecture.SigningBoundaryTest`

### CAP-RECEIPT-outcome-indeterminate

- Corpus: `receipt.verify:outcome_indeterminate`
- Gate: `CharterAgreementProtocol.Architecture.TermEvaluationVocabularyTest`

### CAP-RECEIPT-extension-roundtrip

- Corpus: `receipt.verify:extension_optional_roundtrip`
- Gate: `CharterAgreementProtocol.Architecture.FactsConstructionTest`

### CAP-SCHEMA-valid-decode

- Corpus: `schema.validate:valid`
- Gate: `CharterAgreementProtocol.Architecture.PublicContractCoverageTest`

### CAP-SCHEMA-constraint-closed

- Corpus: `schema.validate:invalid_constraint`, `schema.validate:invalid_type`, `schema.validate:invalid_cardinality`, `schema.validate:missing_required`, `schema.validate:maximum_plus_one`
- Gate: `CharterAgreementProtocol.Architecture.PublicContractCoverageTest`

### CAP-TERMINATION-valid-notice

- Corpus: `termination.verify:valid`
- Gate: `CharterAgreementProtocol.Architecture.FactsConstructionTest`
