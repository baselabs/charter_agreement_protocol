defmodule CharterAgreementProtocol.SpecificationIdentityTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{Digest, SpecificationIdentity}

  @files [
    {"spec/core.md", <<1, 2, 3>>},
    {"spec/schemas/README.md", "grammar notes"},
    {"spec/requirements.md", ""}
  ]

  test "the manifest is order-independent over the same file set" do
    shuffled = Enum.reverse(@files)
    assert SpecificationIdentity.manifest(@files) == SpecificationIdentity.manifest(shuffled)
  end

  test "the manifest is self-delimiting against path and length edits" do
    original = SpecificationIdentity.manifest(@files)

    edited_path =
      SpecificationIdentity.manifest([
        {"spec/core.md", <<1, 2, 3>>},
        {"spec/schemas/README.mdx", "grammar notes"},
        {"spec/requirements.md", ""}
      ])

    edited_length =
      SpecificationIdentity.manifest([
        {"spec/core.md", <<1, 2, 3>>},
        {"spec/schemas/README.md", "grammar notes"},
        {"spec/requirements.md", <<0>>}
      ])

    assert original != edited_path
    assert original != edited_length
  end

  test "a NUL-bearing path is rejected, not silently hashed" do
    forged_path = "a" <> <<0>> <> "3" <> <<0>> <> Map.fetch!(Digest.of("xxx"), :bytes) <> "b"

    assert_raise ArgumentError,
                 ~r/specification path must not contain a null byte/,
                 fn ->
                   SpecificationIdentity.manifest([
                     {forged_path, "yyy"},
                     {"b", "yyy"}
                   ])
                 end
  end

  test "any byte change moves the specification digest" do
    digest = SpecificationIdentity.digest(@files) |> Digest.to_tagged()

    edited =
      SpecificationIdentity.digest([
        {"spec/core.md", <<1, 2, 4>>},
        {"spec/schemas/README.md", "grammar notes"},
        {"spec/requirements.md", ""}
      ])
      |> Digest.to_tagged()

    assert digest =~ ~r/\Asha-256:[A-Za-z0-9_-]{43}\z/
    assert digest != edited
  end
end
