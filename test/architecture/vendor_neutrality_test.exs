defmodule CharterAgreementProtocol.Architecture.VendorNeutralityTest do
  @moduledoc false
  use ExUnit.Case, async: true

  # The protocol surface is published for third-party adoption, so no tracked
  # path or tracked file content may carry a card-network brand name. This
  # guard file is the one exclusion: naming the forbidden token is what makes
  # the check enforceable. The token is assembled from codepoints so the
  # tracked tree itself satisfies the acceptance grep.
  forbidden_source = List.to_string([?v, ?i, ?s, ?a])
  @forbidden Regex.compile!(forbidden_source, "i")
  @guard_path "test/architecture/vendor_neutrality_test.exs"

  test "no tracked path or tracked file content carries a brand name" do
    {listing, 0} = System.cmd("git", ["ls-files"])
    tracked = String.split(listing, "\n", trim: true)

    path_offenders = for path <- tracked, Regex.match?(@forbidden, path), do: path

    content_offenders =
      for path <- tracked,
          path != @guard_path,
          contents = File.read!(path),
          Regex.match?(@forbidden, contents),
          do: path

    assert path_offenders == []
    assert content_offenders == []
  end
end
