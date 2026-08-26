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
       {:corpus,
        ["termination.verify:signature_invalid", "party_descriptor.verify:unknown_member"]},
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
     ]},
    {"CAP-ACCEPTANCE-valid-pairing",
     [
       {:corpus, ["acceptance.verify:valid"]},
       {:gate, CharterAgreementProtocol.Architecture.FactsConstructionTest}
     ]},
    {"CAP-BASE64URL-exact-boundary",
     [
       {:corpus, ["base64url.decode:exact_bound"]},
       {:gate, CharterAgreementProtocol.Architecture.PublicContractCoverageTest}
     ]},
    {"CAP-CANONICALIZATION-noncanonical-rejected",
     [
       {:corpus,
        [
          "canonicalization.encode:non_canonical_bytes",
          "canonicalization.encode:invalid_encoding",
          "canonicalization.encode:invalid_type"
        ]},
       {:gate, CharterAgreementProtocol.Architecture.PublicContractCoverageTest}
     ]},
    {"CAP-CHAIN-valid-topology",
     [
       {:corpus, ["chain.verify:valid"]},
       {:gate, CharterAgreementProtocol.Architecture.ChainRoutingShapeTest}
     ]},
    {"CAP-CHARTER-REVISION-valid-genesis",
     [
       {:corpus, ["charter_revision.decode:valid"]},
       {:gate, CharterAgreementProtocol.Architecture.FactsConstructionTest}
     ]},
    {"CAP-CHARTER-REVISION-closed-members",
     [
       {:corpus,
        [
          "charter_revision.decode:unknown_member",
          "charter_revision.decode:extension_unknown_critical"
        ]},
       {:gate, CharterAgreementProtocol.Architecture.PublicContractCoverageTest}
     ]},
    {"CAP-CHARTER-REVISION-claim-constraints",
     [
       {:corpus,
        [
          "charter_revision.decode:invalid_constraint",
          "charter_revision.decode:invalid_type",
          "charter_revision.decode:missing_required",
          "charter_revision.decode:invalid_cardinality"
        ]},
       {:gate, CharterAgreementProtocol.Architecture.PublicContractCoverageTest}
     ]},
    {"CAP-DESCRIPTOR-CHAIN-signature-required",
     [
       {:corpus, ["descriptor_chain.verify:signature_invalid"]},
       {:gate, CharterAgreementProtocol.Architecture.SigningBoundaryTest}
     ]},
    {"CAP-DIGEST-bytes-only",
     [
       {:corpus, ["digest.hash:invalid_type"]},
       {:gate, CharterAgreementProtocol.Architecture.PublicContractCoverageTest}
     ]},
    {"CAP-JSON-decoder-closed-grammar",
     [
       {:corpus,
        ["json.decode:valid", "json.decode:invalid_type", "json.decode:invalid_encoding"]},
       {:gate, CharterAgreementProtocol.Architecture.PublicContractCoverageTest}
     ]},
    {"CAP-JSON-number-boundaries",
     [
       {:corpus,
        ["json.decode:exact_bound", "json.decode:boundary_near", "json.decode:maximum_plus_one"]},
       {:gate, CharterAgreementProtocol.Architecture.PublicContractCoverageTest}
     ]},
    {"CAP-PARTY-DESCRIPTOR-valid-genesis",
     [
       {:corpus, ["party_descriptor.verify:valid"]},
       {:gate, CharterAgreementProtocol.Architecture.FactsConstructionTest}
     ]},
    {"CAP-RECEIPT-signature-required",
     [
       {:corpus, ["receipt.verify:signature_invalid"]},
       {:gate, CharterAgreementProtocol.Architecture.SigningBoundaryTest}
     ]},
    {"CAP-RECEIPT-outcome-indeterminate",
     [
       {:corpus, ["receipt.verify:outcome_indeterminate"]},
       {:gate, CharterAgreementProtocol.Architecture.TermEvaluationVocabularyTest}
     ]},
    {"CAP-RECEIPT-extension-roundtrip",
     [
       {:corpus, ["receipt.verify:extension_optional_roundtrip"]},
       {:gate, CharterAgreementProtocol.Architecture.FactsConstructionTest}
     ]},
    {"CAP-SCHEMA-valid-decode",
     [
       {:corpus, ["schema.validate:valid"]},
       {:gate, CharterAgreementProtocol.Architecture.PublicContractCoverageTest}
     ]},
    {"CAP-SCHEMA-constraint-closed",
     [
       {:corpus,
        [
          "schema.validate:invalid_constraint",
          "schema.validate:invalid_type",
          "schema.validate:invalid_cardinality",
          "schema.validate:missing_required",
          "schema.validate:maximum_plus_one"
        ]},
       {:gate, CharterAgreementProtocol.Architecture.PublicContractCoverageTest}
     ]},
    {"CAP-TERMINATION-valid-notice",
     [
       {:corpus, ["termination.verify:valid"]},
       {:gate, CharterAgreementProtocol.Architecture.FactsConstructionTest}
     ]},
    {"CAP-ACCEPTANCE-EQUIVOCATION-pairing-required",
     [
       {:corpus, ["acceptance.equivocation:invalid_constraint"]},
       {:gate, CharterAgreementProtocol.Architecture.SigningBoundaryTest}
     ]},
    {"CAP-CHAIN-input-nonempty",
     [
       {:corpus, ["chain.verify:chain_invalid"]},
       {:gate, CharterAgreementProtocol.Architecture.ChainRoutingShapeTest}
     ]},
    {"CAP-EXTENSION-envelope-closed",
     [
       {:corpus,
        ["charter_revision.decode:extension_invalid", "receipt.verify:extension_invalid"]},
       {:gate, CharterAgreementProtocol.Architecture.PublicContractCoverageTest}
     ]},
    {"CAP-PARTY-DESCRIPTOR-decode-shape",
     [
       {:corpus, ["party_descriptor.verify:invalid_constraint"]},
       {:gate, CharterAgreementProtocol.Architecture.PublicContractCoverageTest}
     ]},
    {"CAP-COMPACT-JWS-envelope-well-formed",
     [
       {:corpus, ["party_descriptor.verify:invalid_encoding", "receipt.verify:invalid_encoding"]},
       {:gate, CharterAgreementProtocol.Architecture.PublicContractCoverageTest}
     ]}
  ]

  @doc "Return the closed public requirement-to-evidence map."
  @spec entries() :: [
          {binary(), [{:corpus, [binary()]} | {:gate, module()} | {:mutation, binary()}]}
        ]
  def entries, do: @entries

  @doc """
  Extract declared mutation names, in declaration order, from the conformance
  mutation gate script source.

  Parsed from the AST, so a commented-out entry cannot masquerade as a
  declared mutation and names outside kebab-case are still observed.
  """
  @spec source_mutation_names(binary()) :: [binary()]
  def source_mutation_names(source) when is_binary(source) do
    {_ast, names} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {:name, name} = node, acc when is_binary(name) -> {node, [name | acc]}
        node, acc -> {node, acc}
      end)

    Enum.reverse(names)
  end

  @doc """
  Render the generated requirements matrix served at `spec/requirements.md`.

  The render is a pure projection of `entries/0`; `mix conformance.verify`
  rejects a stale or missing copy.
  """
  @spec render_markdown() :: binary()
  def render_markdown do
    evidence = Enum.flat_map(@entries, &elem(&1, 1))

    corpus_cells =
      evidence
      |> Enum.flat_map(fn
        {:corpus, cells} -> cells
        _other -> []
      end)
      |> Enum.uniq()
      |> length()

    mutations =
      evidence
      |> Enum.flat_map(fn
        {:mutation, name} -> [name]
        _other -> []
      end)
      |> Enum.uniq()
      |> length()

    requirements =
      for {requirement, items} <- @entries do
        lines = for item <- items, line = evidence_line(item), do: line
        Enum.join(["### #{requirement}", "" | lines], "\n")
      end
      |> Enum.join("\n\n")

    """
    # Requirements matrix

    CAP never authorizes.

    GENERATED from `CharterAgreementProtocol.RequirementMap` — do not edit by
    hand. `mix conformance.verify` checks this render is fresh and that
    coverage is bidirectional: every requirement carries evidence, and every
    corpus cell and named source mutation is bound to at least one
    requirement. Regenerate with `mix run scripts/render_requirements.exs`.

    ## Bound evidence

    - Requirements: #{length(@entries)}
    - Corpus cells: #{corpus_cells}
    - Named mutations: #{mutations}

    ## Requirements

    #{requirements}
    """
  end

  defp evidence_line({:corpus, cells}),
    do: "- Corpus: " <> Enum.map_join(cells, ", ", &"`#{&1}`")

  defp evidence_line({:gate, module}), do: "- Gate: `#{inspect(module)}`"
  defp evidence_line({:mutation, name}), do: "- Mutation: `#{name}`"
end
