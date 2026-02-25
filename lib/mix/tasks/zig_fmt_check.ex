defmodule Mix.Tasks.ZigFmtCheck do
  @moduledoc """
  Checks if Zig source files conform to formatting standards.

  Usage:

      mix zig_fmt_check      # Check only
      mix zig_fmt            # Format in-place

  This task runs `zig fmt --check zig_src/` and fails if any files are not
  properly formatted according to Zig's conventions.
  """

  use Mix.Task

  def run(_args) do
    Mix.shell().info("Checking Zig source formatting...")

    case System.cmd("zig", ["fmt", "--check", "zig_src/"],
           into: IO.stream(:stdio, :line)
         ) do
      {_result, 0} ->
        :ok

      {_result, exit_code} ->
        Mix.raise("""
        Zig source files have formatting issues (exit code #{exit_code}).
        Run `mix zig_fmt` to format them automatically.
        """)
    end
  end
end
