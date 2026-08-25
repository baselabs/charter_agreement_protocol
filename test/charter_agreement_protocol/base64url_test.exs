defmodule CharterAgreementProtocol.Base64UrlTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{Base64Url, Error}

  test "encodes and decodes the strict unpadded alphabet" do
    assert Base64Url.encode(<<>>) == ""
    assert Base64Url.encode("f") == "Zg"
    assert Base64Url.decode("") == {:ok, <<>>}
    assert Base64Url.decode("Zg") == {:ok, "f"}
  end

  test "rejects padding, alphabet violations, impossible lengths, and noncanonical pad bits" do
    assert {:error, %Error{code: :base64url_padded, subject: ["base64url"]}} =
             Base64Url.decode("Zg==")

    for malformed <- ["Z+", "Zg/", "A", "Zh"] do
      assert {:error, %Error{code: :base64url_invalid, subject: ["base64url"]}} =
               Base64Url.decode(malformed)
    end
  end

  test "decode rejects non-binary input without echoing it" do
    assert {:error, %Error{code: :invalid_type, subject: ["base64url"]}} =
             Base64Url.decode({:secret, "do-not-echo"})
  end
end
