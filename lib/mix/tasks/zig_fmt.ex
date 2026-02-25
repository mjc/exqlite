defmodule Mix.Tasks.ZigFmt do
  @moduledoc """
  Formats Zig source files according to Zig conventions.

  Usage:

      mix zig_fmt

  This task runs `zig fmt zig_src/` to format all Zig source files in-place.
  """

  use Mix.Task

  def run(_args) do
    Mix.shell().info("Formatting Zig source files...")

    case System.cmd("zig", ["fmt", "zig_src/"], into: IO.stream(:stdio, :line)) do
      {_result, 0} ->
        Mix.shell().info("✓ Zig source files formatted")
        :ok

      {_result, exit_code} ->
        Mix.raise("Zig formatting failed with exit code #{exit_code}")
    end
  end
end
