defmodule CharterAgreementProtocol.SpecificationIdentity do
  @moduledoc """
  CAP never authorizes.

  Canonical self-delimiting manifest over the normative specification set:
  per file, the sorted relative path, the byte length, and the raw SHA-256,
  hashed under the specification digest domain. The release candidate gate
  pins the recorded digest; any spec byte change without re-recording fails
  the gate.
  """

  alias CharterAgreementProtocol.Digest

  @doc """
  Build the canonical manifest bytes for a specification file set.

  Each entry is `path`, a null byte, the decimal byte length, a null byte,
  and the 32-byte raw SHA-256 — self-delimiting in every component, so no
  file set ambiguity survives a length or boundary edit.
  """
  @spec manifest([{binary(), binary()}]) :: binary()
  def manifest(files) do
    files
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map_join(fn {path, bytes} ->
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
