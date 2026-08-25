defmodule CharterAgreementProtocol.Architecture.RuntimePurityTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.ArchitectureScan

  @filesystem_modules [File, :file, :filelib, :prim_file]
  @clock_calls [
    {System, :system_time},
    {System, :monotonic_time},
    {System, :os_time},
    {Date, :utc_today},
    {DateTime, :utc_now},
    {DateTime, :utc_now!},
    {DateTime, :now},
    {DateTime, :now!},
    {NaiveDateTime, :utc_now},
    {NaiveDateTime, :local_now},
    {Time, :utc_now},
    {:erlang, :date},
    {:erlang, :localtime},
    {:erlang, :system_time},
    {:erlang, :monotonic_time},
    {:erlang, :now},
    {:erlang, :time},
    {:erlang, :timestamp},
    {:erlang, :universaltime},
    {:os, :system_time},
    {:os, :timestamp}
  ]
  @os_escape_calls [
    {Port, :open},
    {System, :cmd},
    {System, :shell},
    {:erlang, :open_port},
    {:os, :cmd}
  ]
  @dynamic_calls [{:erlang, :apply}, {:erlang, :make_fun}]

  test "production BEAMs cannot reach filesystems, clocks, calendars, or dynamic dispatch" do
    beams = ArchitectureScan.production_beams()
    assert beams != []
    assert runtime_offenders(beams) == []
  end

  test "the BEAM walk and filter observe file, clock, shell, and dynamic-dispatch calls" do
    {module, beam_path} = compile_probe()

    on_exit(fn ->
      File.rm(beam_path)
      :code.purge(module)
      :code.delete(module)
    end)

    calls = ArchitectureScan.beam_remote_calls(beam_path) |> MapSet.new()
    offenders = runtime_offenders([beam_path]) |> MapSet.new()
    beam_name = Path.basename(beam_path)

    expected =
      MapSet.new([
        {beam_name, File, :read!},
        {beam_name, Date, :utc_today},
        {beam_name, :os, :cmd},
        {beam_name, System, :cmd},
        {beam_name, :erlang, :apply},
        {beam_name, :erlang, :make_fun}
      ])

    assert MapSet.member?(calls, {:erlang, :call_fun})
    assert MapSet.subset?(expected, offenders)
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

  defp runtime_offenders(beams) do
    for beam <- beams,
        {module, function} = call <- ArchitectureScan.beam_remote_calls(beam),
        module in @filesystem_modules or module == :calendar or call in @clock_calls or
          call in @os_escape_calls or call in @dynamic_calls,
        do: {Path.basename(beam), module, function}
  end

  defp compile_probe do
    source = """
    defmodule CharterAgreementProtocol.RuntimePurityProbe do
      def inspect_path(path, module, function) do
        dynamic = apply(module, function, [path])
        captured = Function.capture(module, function, 1).(path)

        {
          File.read!(path),
          Date.utc_today(),
          :os.cmd(~c"true"),
          System.cmd("true", []),
          dynamic,
          captured
        }
      end
    end
    """

    [{module, beam}] = Code.compile_string(source)

    beam_path =
      Path.join(
        System.tmp_dir!(),
        "cap-runtime-purity-probe-#{System.unique_integer([:positive])}.beam"
      )

    File.write!(beam_path, beam)
    {module, beam_path}
  end
end
