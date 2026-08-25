defmodule CharterAgreementProtocol.DigestTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{Digest, Error}

  test "hashes the exact domain-separated preimage and emits the tagged wire form" do
    canonical = ~s({"a":1})

    expected =
      :crypto.hash(:sha256, [
        "charter-agreement-protocol/charter-revision-content",
        <<0>>,
        canonical
      ])

    assert %Digest{algorithm: :sha256, bytes: ^expected} =
             digest = Digest.hash(:charter_revision_content, canonical)

    tagged = Digest.to_tagged(digest)
    assert tagged == "sha-256:" <> Base.url_encode64(expected, padding: false)
    assert byte_size(tagged) == byte_size("sha-256:") + 43
    assert Digest.from_tagged(tagged) == {:ok, digest}
  end

  test "different registered separators cannot collapse onto one preimage" do
    bytes = ~s({"same":true})
    left = Digest.hash(:acceptance_content, bytes)
    right = Digest.hash(:receipt_content, bytes)
    refute Digest.equal?(left, right)
    refute left.bytes == right.bytes
  end

  test "tag parsing is closed and uniformly rejects malformed bodies" do
    assert_error(Digest.from_tagged("sha512:abc"), :digest_algorithm_unsupported)

    for malformed <- [
          "",
          "sha-256",
          "sha-256:",
          "sha-256:abc=",
          "sha-256:" <> String.duplicate("a", 42)
        ] do
      assert_error(Digest.from_tagged(malformed), :digest_encoding_invalid)
    end

    assert_error(Digest.from_tagged({:secret, "do-not-echo"}), :invalid_type)
  end

  test "equality and content verification distinguish shape from content" do
    digest = Digest.hash(:corpus_index, "bytes")
    assert Digest.equal?(digest, digest)
    refute Digest.equal?(digest, %Digest{algorithm: :sha256, bytes: :binary.copy(<<0>>, 32)})

    tagged = Digest.to_tagged(digest)
    assert Digest.verify_content(:corpus_index, "bytes", tagged) == :ok
    assert_error(Digest.verify_content(:corpus_index, "tampered", tagged), :digest_mismatch)
    refute Digest.equal?(digest, :not_a_digest)
    assert_error(Digest.verify_content(:corpus_index, :not_bytes, tagged), :invalid_type)
  end

  test "unknown digest domains fail loudly as internal invariants" do
    assert_raise KeyError, fn -> Digest.hash(:unknown_domain, "bytes") end
  end

  defp assert_error(result, code) do
    assert {:error, %Error{code: ^code, subject: ["digest"], detail: nil}} = result
  end
end
