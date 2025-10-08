defmodule Dashboard.HH.CookieParser do
  @moduledoc """
  Parses Netscape HTTP Cookie File format.

  Format:
  domain  flag  path  secure  expiration  name  value
  """

  @doc """
  Parses cookie file content and returns a map of cookie name => value.

  ## Examples

      iex> parse("# Comment\\n.hh.ru\\tTRUE\\t/\\tFALSE\\t123456\\thhtoken\\tABC123")
      %{"hhtoken" => "ABC123"}
  """
  def parse(content) when is_binary(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.reject(&comment?/1)
    |> Enum.reduce(%{}, fn line, acc ->
      case parse_line(line) do
        {:ok, name, value} -> Map.put(acc, name, value)
        :error -> acc
      end
    end)
  end

  defp comment?(line) do
    String.starts_with?(String.trim(line), "#")
  end

  defp parse_line(line) do
    # Netscape cookie format has 7 fields separated by tabs
    parts = String.split(line, "\t")

    case parts do
      [_domain, _flag, _path, _secure, _expiration, name, value] ->
        {:ok, name, value}

      _ ->
        :error
    end
  end
end
