defmodule CharterAgreementProtocol.PlainEncodingTest do
  @moduledoc """
  Canonical JSON from plain Elixir terms, and charter revision bytes built from
  a plain claims map: the same bytes the tagged encoder produces, and the same
  errors the revision decoder reports.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias CharterAgreementProtocol, as: CAP
  alias CharterAgreementProtocol.{Canonicalization, CharterRevisionFixture, Error, Json, Limits}

  @safe_integer 9_007_199_254_740_991

  defp plain_leaf do
    one_of([
      constant(nil),
      boolean(),
      integer(-@safe_integer..@safe_integer),
      float(min: -1.0e12, max: 1.0e12),
      string(:alphanumeric, max_length: 24)
    ])
  end

  defp plain(max_depth) do
    inner = if max_depth > 1, do: plain(max_depth - 1), else: plain_leaf()

    frequency([
      {6, plain_leaf()},
      {2, list_of(inner, max_length: 5)},
      {2, map_of(string(:alphanumeric, min_length: 1, max_length: 10), inner, max_length: 5)}
    ])
  end

  # The plain term a decoded tagged value stands for.
  defp to_plain(:null), do: nil
  defp to_plain({:boolean, value}), do: value
  defp to_plain({:integer, value}), do: value
  defp to_plain({:float, value}), do: value
  defp to_plain({:string, value}), do: value
  defp to_plain({:array, items}), do: Enum.map(items, &to_plain/1)
  defp to_plain({:object, members}), do: Map.new(members, fn {k, v} -> {k, to_plain(v)} end)

  property "plain encoding gives the tagged encoder's bytes and decodes back to the term" do
    check all(term <- plain(3)) do
      assert {:ok, tagged} = Canonicalization.from_plain(term)
      assert {:ok, bytes} = Canonicalization.encode_plain(term)
      assert {:ok, ^bytes} = Canonicalization.encode(tagged)
      assert {:ok, decoded} = Json.decode(bytes, Limits.default())
      assert to_plain(decoded) == term
    end
  end

  test "floats stay floats and integers stay integers" do
    assert {:ok, {:float, 2.0}} = Canonicalization.from_plain(2.0)
    assert {:ok, {:integer, 2}} = Canonicalization.from_plain(2)
  end

  test "terms with no JSON meaning are typed errors, never raised" do
    for term <- [%{atom_key: 1}, {:tuple}, :atom, [1, self()], %{"k" => make_ref()}] do
      assert {:error, %Error{code: :invalid_type}} = Canonicalization.from_plain(term)
      assert {:error, %Error{code: :invalid_type}} = Canonicalization.encode_plain(term)
    end
  end

  test "a plain claims map becomes the revision's canonical bytes" do
    fixture = CharterRevisionFixture.genesis()
    claims = CharterRevisionFixture.base_claims(fixture.legal_text)

    assert {:ok, bytes} = CAP.encode_charter_revision(claims)
    assert bytes == fixture.bytes
    assert {:ok, revision} = CAP.decode_charter_revision(bytes, Limits.default())
    assert CAP.revision_digest(revision) == fixture.digest
  end

  test "invalid claims report the decoder's own error" do
    claims =
      CharterRevisionFixture.base_claims("Example charter terms\n")
      |> Map.put("protocol_revision", 99)

    {:ok, canonical} = Canonicalization.encode_plain(claims)

    assert {:error, %Error{code: code}} = CAP.encode_charter_revision(claims)

    assert {:error, %Error{code: ^code}} =
             CAP.decode_charter_revision(canonical, Limits.default())

    assert code == :constraint_violation
  end

  test "a claims value that is not plain JSON is a typed error" do
    assert {:error, %Error{code: :invalid_type}} = CAP.encode_charter_revision(%{key: "atom"})
    assert {:error, %Error{code: :invalid_type}} = CAP.encode_charter_revision("not a map")
  end
end
