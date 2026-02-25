defmodule ZigUnitTests do
  @moduledoc """
  Zig unit tests integrated into Elixir's ExUnit test suite.

  These pure-logic tests run without BEAM and use a stub erl_nif.h with libc backing.
  They're executed as part of `mix test`, with results reported through ExUnit.
  """

  use ExUnit.Case

  @zig_test_bin "zig_src/tests.zig"
  @zig_include_dirs [
    "-I",
    "zig_src/test_stubs",
    "-I",
    "c_src"
  ]
  @zig_libs ["-lc", "c_src/sqlite3.c"]

  setup_all do
    # Verify zig is available
    case System.find_executable("zig") do
      nil -> raise "zig compiler not found in PATH"
      _path -> :ok
    end

    :ok
  end

  test "Zig unit tests pass (15 tests: allocator, helpers, nif, sqlite3, atoms)" do
    args = ["test", @zig_test_bin] ++ @zig_include_dirs ++ @zig_libs

    # Collect zig test output for display on failure
    output_lines = []

    # Run with output to stdout and also collect for failure reporting
    {_result, exit_code} =
      System.cmd("zig", args, into: output_lines)

    # Display output for visibility
    output = output_lines |> Enum.join()
    IO.write(output)

    # Assert exit code indicates all tests passed
    assert exit_code == 0,
           """
           Zig unit tests failed with exit code #{exit_code}.

           Output:
           #{output}
           """
  end
end
