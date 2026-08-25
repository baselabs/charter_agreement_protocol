defmodule CharterAgreementProtocol.RequirementMap do
  @moduledoc """
  CAP never authorizes.

  Compiled traceability from stable public requirements to corpus cells,
  architecture gates, and red-capable source mutations. This map is evidence
  routing metadata; it is not a protocol decision surface.
  """

  @entries [
    {"CAP-CANONICALIZATION-ecmascript-number",
     [
       {:corpus, ["canonicalization.encode:valid"]},
       {:gate, CharterAgreementProtocol.Architecture.PublicContractCoverageTest},
       {:mutation, "jcs-number-defeat"}
     ]},
    {"CAP-BASE64URL-unpadded-only",
     [
       {:corpus, ["base64url.decode:invalid_encoding"]},
       {:gate, CharterAgreementProtocol.Architecture.ConstantTimeCompareShapeTest},
       {:mutation, "padding-acceptance"}
     ]},
    {"CAP-DIGEST-domain-separation",
     [
       {:corpus, ["digest.hash:valid"]},
       {:gate, CharterAgreementProtocol.Architecture.PortfolioIdentityCensusTest},
       {:mutation, "separator-collapse"}
     ]},
    {"CAP-SCHEMA-closed-members",
     [
       {:corpus, ["schema.validate:unknown_member"]},
       {:gate, CharterAgreementProtocol.Architecture.PublicContractCoverageTest},
       {:mutation, "unknown-member-acceptance"}
     ]},
    {"CAP-PARTY-DESCRIPTOR-signature-required",
     [
       {:corpus, ["party_descriptor.verify:signature_invalid"]},
       {:gate, CharterAgreementProtocol.Architecture.SigningBoundaryTest},
       {:mutation, "chain-signature-skip"}
     ]},
    {"CAP-DIGEST-equality-required",
     [
       {:corpus, ["digest.hash:digest_mismatch"]},
       {:gate, CharterAgreementProtocol.Architecture.ConstantTimeCompareShapeTest},
       {:mutation, "digest-equality-skip"}
     ]},
    {"CAP-SIGNATURE-ed25519-verification",
     [
       {:corpus, ["acceptance.verify:signature_invalid"]},
       {:gate, CharterAgreementProtocol.Architecture.SigningBoundaryTest},
       {:mutation, "ed25519-defeat"}
     ]},
    {"CAP-COMPACT-JWS-type-isolation",
     [
       {:corpus, ["termination.verify:signature_invalid"]},
       {:gate, CharterAgreementProtocol.Architecture.PortfolioIdentityCensusTest},
       {:mutation, "typ-confusion"}
     ]},
    {"CAP-TERMINATION-reason-closed",
     [
       {:corpus, ["termination.verify:invalid_constraint"]},
       {:gate, CharterAgreementProtocol.Architecture.PublicContractCoverageTest},
       {:mutation, "reason-code-uncheck"}
     ]},
    {"CAP-CHAIN-highest-precedence",
     [
       {:corpus, ["governing_revision:precedence_selection"]},
       {:gate, CharterAgreementProtocol.Architecture.ChainRoutingShapeTest},
       {:mutation, "precedence-lowest"}
     ]},
    {"CAP-FACTS-union-complete",
     [
       {:corpus, ["receipt.verify:valid"]},
       {:gate, CharterAgreementProtocol.Architecture.FactsConstructionTest},
       {:mutation, "facts-union-suppression"}
     ]},
    {"CAP-CHAIN-fork-topology",
     [
       {:corpus, ["chain.verify:chain_fork"]},
       {:gate, CharterAgreementProtocol.Architecture.ChainRoutingShapeTest},
       {:mutation, "fork-topology-suppressed"}
     ]},
    {"CAP-CHAIN-contested-refusal",
     [
       {:corpus, ["receipt.verify:chain_fork"]},
       {:gate, CharterAgreementProtocol.Architecture.ChainRoutingShapeTest},
       {:mutation, "contested-tie-resolved"}
     ]},
    {"CAP-ACCEPTANCE-exact-claims",
     [
       {:corpus, ["acceptance.verify:invalid_constraint"]},
       {:gate, CharterAgreementProtocol.Architecture.FactsConstructionTest},
       {:mutation, "acceptance-claims-mismatch-accept"}
     ]},
    {"CAP-PARTY-DESCRIPTOR-predecessor-binding",
     [
       {:corpus, ["descriptor_chain.verify:chain_invalid"]},
       {:gate, CharterAgreementProtocol.Architecture.ChainRoutingShapeTest},
       {:mutation, "prev-binding-skip"}
     ]},
    {"CAP-RECEIPT-revision-number-match",
     [
       {:corpus, ["receipt.verify:invalid_constraint"]},
       {:gate, CharterAgreementProtocol.Architecture.FactsConstructionTest},
       {:mutation, "receipt-number-crosscheck-skip"}
     ]},
    {"CAP-RECEIPT-conflict-visible",
     [
       {:corpus, ["receipt.verify:chain_fork"]},
       {:gate, CharterAgreementProtocol.Architecture.TermEvaluationVocabularyTest},
       {:mutation, "receipt-conflict-silenced"}
     ]},
    {"CAP-ACCEPTANCE-equivocation-refusal",
     [
       {:corpus, ["acceptance.equivocation:equivocation"]},
       {:gate, CharterAgreementProtocol.Architecture.SigningBoundaryTest},
       {:mutation, "equivocation-guard-removed"}
     ]},
    {"CAP-SIGNING-branch-freshness",
     [
       {:corpus, ["descriptor_chain.verify:descriptor_fork"]},
       {:gate, CharterAgreementProtocol.Architecture.SigningBoundaryTest},
       {:mutation, "stale-branch-guard-removed"}
     ]},
    {"CAP-PARTY-DESCRIPTOR-superseded-visible",
     [
       {:corpus, ["descriptor_chain.verify:descriptor_superseded"]},
       {:gate, CharterAgreementProtocol.Architecture.FactsConstructionTest},
       {:mutation, "superseded-descriptor-silent-accept"}
     ]},
    {"CAP-CHAIN-supersession-applied",
     [
       {:corpus, ["chain.verify:supersession"]},
       {:gate, CharterAgreementProtocol.Architecture.ChainRoutingShapeTest},
       {:mutation, "supersession-ignore"}
     ]},
    {"CAP-CONFORMANCE-expectations-bound",
     [
       {:corpus, ["base64url.decode:valid"]},
       {:gate, CharterAgreementProtocol.Architecture.ReleaseGateTest},
       {:mutation, "corpus-expectation-flip"}
     ]}
  ]

  @doc "Return the closed public requirement-to-evidence map."
  @spec entries() :: [
          {binary(), [{:corpus, [binary()]} | {:gate, module()} | {:mutation, binary()}]}
        ]
  def entries, do: @entries
end
