defmodule Core.Headers do
  @moduledoc false

  @consumer_id "x-consumer-id"
  @consumer_metadata "x-consumer-metadata"

  def consumer_id, do: @consumer_id
  def consumer_metadata, do: @consumer_metadata

  def get_consumer_id(headers) do
    get_header(headers, @consumer_id)
  end

  def get_header(headers, header) when is_list(headers) do
    Enum.reduce_while(headers, nil, fn {k, v}, acc ->
      if String.downcase(k) == String.downcase(header) do
        {:halt, v}
      else
        {:cont, acc}
      end
    end)
  end
end
