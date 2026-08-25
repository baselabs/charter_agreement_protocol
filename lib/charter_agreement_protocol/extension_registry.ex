defmodule CharterAgreementProtocol.ExtensionRegistry do
  @moduledoc """
  CAP never authorizes.

  Compiled extension-profile registry. Registry changes are code releases;
  entries carry exactly the seven protocol fields and never read runtime files.
  `promoted_at_revision` records registry-release governance; artifact validators
  enforce the protocol revision declared by each artifact schema rather than
  reinterpreting that historical record as a runtime feature gate.
  """

  alias CharterAgreementProtocol.{Canonicalization, Digest, Schema}

  defstruct [
    :namespace,
    :owner,
    :criticality,
    :state,
    :schema_digest,
    :a2a_uri,
    :promoted_at_revision
  ]

  @type criticality :: :critical | :optional
  @type state :: :reserved | :active | :deprecated | :retired
  @type t :: %__MODULE__{
          namespace: binary(),
          owner: binary(),
          criticality: criticality(),
          state: state(),
          schema_digest: nil | binary(),
          a2a_uri: binary(),
          promoted_at_revision: nil | pos_integer()
        }

  @safe_integer 9_007_199_254_740_991
  @tagged_digest ~r/\Asha-256:[A-Za-z0-9_-]{43}\z/
  @currencies ~w(AED AFN ALL AMD AOA ARS AUD AWG AZN BAM BBD BDT BHD BIF BMD BND BOB BOV BRL BSD BTN BWP BYN BZD CAD CDF CHE CHF CHW CLF CLP CNY COP COU CRC CUP CVE CZK DJF DKK DOP DZD EGP ERN ETB EUR FJD FKP GBP GEL GHS GIP GMD GNF GTQ GYD HKD HNL HTG HUF IDR ILS INR IQD IRR ISK JMD JOD JPY KES KGS KHR KMF KPW KRW KWD KYD KZT LAK LBP LKR LRD LSL LYD MAD MDL MGA MKD MMK MNT MOP MRU MUR MVR MWK MXN MXV MYR MZN NAD NGN NIO NOK NPR NZD OMR PAB PEN PGK PHP PKR PLN PYG QAR RON RSD RUB RWF SAR SBD SCR SDG SEK SGD SHP SLE SOS SRD SSP STN SVC SYP SZL THB TJS TMT TND TOP TRY TTD TWD TZS UAH UGX USD USN UYI UYU UYW UZS VED VES VND VUV WST XAD XAF XAG XAU XBA XBB XBC XBD XCD XCG XDR XOF XPD XPF XPT XSU XTS XUA XXX YER ZAR ZMW ZWG)

  @price_index_schema Schema.definition("pricing_index", [
                        Schema.field("series_document_digest",
                          required?: true,
                          types: [:string],
                          constraint: {:matches, @tagged_digest}
                        ),
                        Schema.field("series_id",
                          required?: true,
                          types: [:string],
                          constraint: {:string_bytes, 1, 128}
                        ),
                        Schema.field("observation_lag_days",
                          required?: true,
                          types: [:integer],
                          constraint: {:integer_range, 0, 90}
                        )
                      ])

  @price_terms_schema Schema.definition(
                        "pricing_indexed_terms",
                        [
                          Schema.field("currency",
                            required?: true,
                            types: [:string],
                            constraint: {:one_of, Enum.map(@currencies, &{:string, &1})}
                          ),
                          Schema.field("base_amount_minor",
                            required?: true,
                            types: [:integer],
                            constraint: {:integer_range, 0, @safe_integer}
                          ),
                          Schema.field("index",
                            required?: true,
                            types: [:object],
                            nested: {:object, @price_index_schema}
                          ),
                          Schema.field("formula",
                            required?: true,
                            types: [:string],
                            constraint: {:one_of, [{:string, "index_plus_spread"}]}
                          ),
                          Schema.field("spread_bps",
                            required?: true,
                            types: [:integer],
                            constraint: {:integer_range, -10_000, 10_000}
                          ),
                          Schema.field("floor_amount_minor",
                            types: [:integer],
                            constraint: {:integer_range, 0, @safe_integer}
                          ),
                          Schema.field("cap_amount_minor",
                            types: [:integer],
                            constraint: {:integer_range, 0, @safe_integer}
                          ),
                          Schema.field("tolerance_bps",
                            required?: true,
                            types: [:integer],
                            constraint: {:integer_range, 0, 10_000}
                          )
                        ],
                        cross_field: [
                          {:ordered_if_present, "floor_amount_minor", :lte, "cap_amount_minor"}
                        ]
                      )

  @price_observation_schema Schema.definition("pricing_indexed_observation", [
                              Schema.field("observed_index_digest",
                                required?: true,
                                types: [:string],
                                constraint: {:matches, @tagged_digest}
                              ),
                              Schema.field("observation_instant",
                                required?: true,
                                types: [:string],
                                constraint: :utc_timestamp
                              ),
                              Schema.field("computed_amount_minor",
                                required?: true,
                                types: [:integer],
                                constraint: {:integer_range, 0, @safe_integer}
                              )
                            ])

  @price_terms_schema_digest (case Canonicalization.encode(Schema.document(@price_terms_schema)) do
                                {:ok, bytes} ->
                                  :extension_schema |> Digest.hash(bytes) |> Digest.to_tagged()
                              end)

  @price_observation_schema_digest (case Canonicalization.encode(
                                           Schema.document(@price_observation_schema)
                                         ) do
                                      {:ok, bytes} ->
                                        :extension_schema
                                        |> Digest.hash(bytes)
                                        |> Digest.to_tagged()
                                    end)

  @profiles [
    %{
      namespace: "com.example/pricing-indexed",
      owner: "Example Charter Profiles",
      criticality: :critical,
      state: :active,
      schema_digest: @price_terms_schema_digest,
      a2a_uri: "https://example.com/charter-profiles/pricing-indexed",
      promoted_at_revision: nil,
      schema: @price_terms_schema,
      surface: :charter_revision,
      receipt_profile?: false
    },
    %{
      namespace: "com.example/pricing-indexed-observation",
      owner: "Example Charter Profiles",
      criticality: :optional,
      state: :active,
      schema_digest: @price_observation_schema_digest,
      a2a_uri: "https://example.com/charter-profiles/pricing-indexed-observation",
      promoted_at_revision: nil,
      schema: @price_observation_schema,
      surface: :receipt,
      receipt_profile?: true
    },
    %{
      namespace: "com.example.charter/default",
      owner: "Example Charter Profiles",
      criticality: :optional,
      state: :active,
      schema_digest: nil,
      a2a_uri: "https://example.com/charter-profiles/charter/default",
      promoted_at_revision: nil,
      schema: nil,
      surface: :receipt,
      receipt_profile?: true
    },
    %{
      namespace: "com.example/identity-vlei",
      owner: "Example Charter Profiles",
      criticality: :optional,
      state: :reserved,
      schema_digest: nil,
      a2a_uri: "https://example.com/charter-profiles/identity-vlei",
      promoted_at_revision: nil,
      schema: nil,
      surface: :party_descriptor,
      receipt_profile?: false
    },
    %{
      namespace: "com.example/identity-eidas-qeaa",
      owner: "Example Charter Profiles",
      criticality: :optional,
      state: :reserved,
      schema_digest: nil,
      a2a_uri: "https://example.com/charter-profiles/identity-eidas-qeaa",
      promoted_at_revision: nil,
      schema: nil,
      surface: :party_descriptor,
      receipt_profile?: false
    },
    %{
      namespace: "com.example/retired-profile",
      owner: "Example Charter Profiles",
      criticality: :critical,
      state: :retired,
      schema_digest: nil,
      a2a_uri: "https://example.com/charter-profiles/retired-profile",
      promoted_at_revision: 1,
      schema: nil,
      surface: :charter_revision,
      receipt_profile?: false
    }
  ]

  @entry_fields [
    :namespace,
    :owner,
    :criticality,
    :state,
    :schema_digest,
    :a2a_uri,
    :promoted_at_revision
  ]

  @doc "Return the compiled registry in its stable publication order."
  @spec entries() :: [t()]
  def entries, do: Enum.map(@profiles, &to_entry/1)

  @doc "Resolve one compiled namespace."
  @spec entry(binary()) :: {:ok, t()} | :error
  def entry(namespace) when is_binary(namespace) do
    case Enum.find(@profiles, &(&1.namespace == namespace)) do
      nil -> :error
      profile -> {:ok, to_entry(profile)}
    end
  end

  @doc "Return the compiled schema definitions keyed by the namespace their digest binds."
  @spec schemas() :: %{binary() => Schema.Definition.t()}
  def schemas do
    @profiles
    |> Enum.reject(&is_nil(&1.schema))
    |> Map.new(&{&1.namespace, &1.schema})
  end

  @doc "Resolve the sole artifact surface assigned to one compiled namespace."
  @spec placement(binary()) :: {:ok, :party_descriptor | :charter_revision | :receipt} | :error
  def placement(namespace) when is_binary(namespace) do
    case Enum.find(@profiles, &(&1.namespace == namespace)) do
      nil -> :error
      profile -> {:ok, profile.surface}
    end
  end

  @doc "Return whether an active optional registry entry is a selectable receipt profile."
  @spec receipt_profile?(binary()) :: boolean()
  def receipt_profile?(namespace) when is_binary(namespace) do
    Enum.any?(@profiles, fn profile ->
      profile.namespace == namespace and profile.state == :active and
        profile.criticality == :optional and profile.surface == :receipt and
        profile.receipt_profile?
    end)
  end

  @doc "Return the domain-separated digest of all seven fields of every compiled entry."
  @spec digest() :: Digest.t()
  def digest do
    value =
      {:object,
       Enum.map(entries(), fn entry ->
         {entry.namespace,
          {:object,
           [
             {"namespace", {:string, entry.namespace}},
             {"owner", {:string, entry.owner}},
             {"criticality", {:string, Atom.to_string(entry.criticality)}},
             {"state", {:string, Atom.to_string(entry.state)}},
             {"schema_digest", nullable(entry.schema_digest)},
             {"a2a_uri", {:string, entry.a2a_uri}},
             {"promoted_at_revision", nullable_integer(entry.promoted_at_revision)}
           ]}}
       end)}

    {:ok, bytes} = Canonicalization.encode(value)
    Digest.hash(:extension_registry, bytes)
  end

  defp to_entry(profile), do: struct!(__MODULE__, Map.take(profile, @entry_fields))

  defp nullable(nil), do: :null
  defp nullable(value), do: {:string, value}
  defp nullable_integer(nil), do: :null
  defp nullable_integer(value), do: {:integer, value}
end
