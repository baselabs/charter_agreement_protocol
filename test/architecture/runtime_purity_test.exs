defmodule CharterAgreementProtocol.Architecture.RuntimePurityTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.ArchitectureScan

  @filesystem_modules [File, :file, :filelib, :prim_file]
  @clock_calls [
    {System, :system_time},
    {System, :monotonic_time},
    {System, :os_time},
    {DateTime, :utc_now},
    {DateTime, :now},
    {NaiveDateTime, :utc_now},
    {Time, :utc_now},
    {:erlang, :system_time},
    {:erlang, :monotonic_time},
    {:os, :system_time}
  ]

  test "production BEAMs cannot reach filesystems, clocks, calendars, or dynamic dispatch" do
    beams = ArchitectureScan.production_beams()
    assert beams != []

    offenders =
      for beam <- beams,
          {module, function} = call <- ArchitectureScan.beam_remote_calls(beam),
          module in @filesystem_modules or module == :calendar or call in @clock_calls or
            call == {:erlang, :apply},
          do: {Path.basename(beam), module, function}

    assert offenders == []
  end

  test "the package has no application callback and no production dependency" do
    application = CharterAgreementProtocol.MixProject.application()

    refute Keyword.has_key?(application, :mod)
    assert application[:extra_applications] == [:crypto]

    offenders =
      for dependency <- CharterAgreementProtocol.MixProject.project()[:deps],
          {name, options} = normalize_dependency(dependency),
          Keyword.get(options, :runtime) != false or
            Enum.sort(List.wrap(Keyword.get(options, :only))) != [:dev, :test],
          do: name

    assert offenders == []
  end

  defp normalize_dependency({name, requirement, options}) when is_binary(requirement),
    do: {name, options}

  defp normalize_dependency({name, options}) when is_list(options), do: {name, options}
  defp normalize_dependency({name, requirement}) when is_binary(requirement), do: {name, []}
end
