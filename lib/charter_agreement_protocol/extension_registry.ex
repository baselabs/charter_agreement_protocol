defmodule CharterAgreementProtocol.ExtensionRegistry do
  @moduledoc """
  CAP never authorizes.

  Compiled extension-profile registry. Registry changes are code releases;
  entries carry exactly the seven protocol fields and never read runtime files.
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

  @doc "Return the compiled registry in its stable publication order."
  @spec entries() :: [t()]
  def entries do
    [
      entry_data("com.example/pricing-indexed", :critical, :active, price_terms_schema()),
      entry_data(
        "com.example/pricing-indexed-observation",
        :optional,
        :active,
        price_observation_schema()
      ),
      entry_data("com.example.charter/default", :optional, :active, nil),
      entry_data("com.example/identity-vlei", :optional, :reserved, nil),
      entry_data("com.example/identity-eidas-qeaa", :optional, :reserved, nil),
      entry_data("com.example/retired-profile", :critical, :retired, nil, 1)
    ]
  end

  @doc "Resolve one compiled namespace."
  @spec entry(binary()) :: {:ok, t()} | :error
  def entry(namespace) when is_binary(namespace) do
    case Enum.find(entries(), &(&1.namespace == namespace)) do
      nil -> :error
      entry -> {:ok, entry}
    end
  end

  @doc "Return the compiled schema definitions keyed by the namespace their digest binds."
  @spec schemas() :: %{binary() => Schema.Definition.t()}
  def schemas do
    %{
      "com.example/pricing-indexed" => price_terms_schema(),
      "com.example/pricing-indexed-observation" => price_observation_schema()
    }
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

  defp entry_data(namespace, criticality, state, schema, promoted_at_revision \\ nil) do
    %__MODULE__{
      namespace: namespace,
      owner: "Example Charter Profiles",
      criticality: criticality,
      state: state,
      schema_digest: schema_digest(schema),
      a2a_uri:
        "https://example.com/charter-profiles/" <>
          String.replace_prefix(namespace, "com.example/", ""),
      promoted_at_revision: promoted_at_revision
    }
  end

  defp schema_digest(nil), do: nil

  defp schema_digest(definition) do
    {:ok, bytes} = definition |> Schema.document() |> Canonicalization.encode()
    :extension_schema |> Digest.hash(bytes) |> Digest.to_tagged()
  end

  defp price_terms_schema do
    index =
      Schema.definition("pricing_index", [
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

    Schema.definition(
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
        Schema.field("index", required?: true, types: [:object], nested: {:object, index}),
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
  end

  defp price_observation_schema do
    Schema.definition("pricing_indexed_observation", [
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
  end

  defp nullable(nil), do: :null
  defp nullable(value), do: {:string, value}
  defp nullable_integer(nil), do: :null
  defp nullable_integer(value), do: {:integer, value}
end
