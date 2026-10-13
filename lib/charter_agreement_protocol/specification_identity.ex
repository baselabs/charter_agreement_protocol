defmodule CharterAgreementProtocol.SpecificationIdentity do
  @moduledoc """
  CAP never authorizes.

  Canonical self-delimiting manifest over the normative specification set:
  per file, the sorted relative path, the byte length, and the raw SHA-256,
  hashed under the specification digest domain. The release check pins the
  recorded digest, so any change to the specification bytes fails it until
  the digest is recorded again.
  """

  alias CharterAgreementProtocol.Digest

  @doc """
  Build the canonical manifest bytes for a specification file set.

  Each entry is `path`, a null byte, the decimal byte length, a null byte,
  and the 32-byte raw SHA-256, so every component is self-delimiting. Paths
  containing a null byte are rejected loudly: a NUL-bearing path can forge
  another file set's manifest bytes, so ambiguity is refused at the input,
  not hashed.
  """
  @spec manifest([{binary(), binary()}]) :: binary()
  def manifest(files) do
    files
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map_join(fn {path, bytes} ->
      if String.contains?(path, <<0>>),
        do:
          raise(
            ArgumentError,
            "specification path must not contain a null byte: #{inspect(path)}"
          )

      path <>
        <<0>> <>
        Integer.to_string(byte_size(bytes)) <>
        <<0>> <>
        Map.fetch!(Digest.of(bytes), :bytes)
    end)
  end

  @doc "Hash the canonical manifest under the specification domain."
  @spec digest([{binary(), binary()}]) :: Digest.t()
  def digest(files), do: Digest.hash(:specification, manifest(files))
end
