defmodule Core.Microservices.MediaStorage do
  @moduledoc false

  use Core.Microservices
  require Logger

  @behaviour Core.Behaviours.MediaStorageBehaviour

  @media_storage_api Application.get_env(:core, :microservices)[:media_storage]

  def verify_uploaded_file(url, resource_name) do
    HTTPoison.head(url, "Content-Type": MIME.from_path(resource_name))
  end

  def create_signed_url(action, bucket, resource_name, resource_id, headers \\ []) do
    data = %{"secret" => generate_sign_url_data(action, bucket, resource_name, resource_id)}
    create_signed_url(data, headers)
  end

  defp generate_sign_url_data(action, bucket, resource_name, resource_id) do
    %{
      "action" => action,
      "bucket" => bucket,
      "resource_id" => resource_id,
      "resource_name" => resource_name
    }
    |> add_content_type(action, resource_name)
  end

  defp add_content_type(data, "GET", _resource_name), do: data

  defp add_content_type(data, _action, resource_name) do
    Map.put(data, "content_type", MIME.from_path(resource_name))
  end

  def create_signed_url(data, headers) do
    post!("/media_content_storage_secrets", Jason.encode!(data), headers)
  end

  def store_signed_content(signed_content, bucket, id, resource_name, headers) do
    store_signed_content(config()[:enabled?], bucket, signed_content, id, resource_name, headers)
  end

  def store_signed_content(true, bucket, signed_content, id, resource_name, headers) do
    with {:ok, %{"data" => %{"secret_url" => url}}} <-
           @media_storage_api.create_signed_url("PUT", config()[bucket], resource_name, id, headers) do
      headers = [{"Content-Type", "application/octet-stream"}]
      content = Base.decode64!(signed_content, ignore: :whitespace, padding: false)

      url
      |> @media_storage_api.put_signed_content(content, headers, config()[:hackney_options])
      |> check_gcs_response()
    end
  end

  def store_signed_content(false, _bucket, _signed_content, _id, _, _headers) do
    {:ok, "Media Storage is disabled in config"}
  end

  def check_gcs_response({:ok, %HTTPoison.Response{status_code: code} = response})
      when code in [200, 201] do
    check_gcs_response(response)
  end

  def check_gcs_response({_, response}), do: check_gcs_response(response)

  def check_gcs_response(%HTTPoison.Response{status_code: code, body: body}) when code in [200, 201] do
    {:ok, body}
  end

  def check_gcs_response(%HTTPoison.Response{body: body}) do
    {:error, body}
  end

  def get_signed_content(secret_url), do: HTTPoison.get(secret_url)

  def save_file(id, content, bucket, resource_name, headers \\ []) do
    with {:ok, %{"data" => %{"secret_url" => url}}} <- create_signed_url("PUT", bucket, resource_name, id, headers) do
      url
      |> put_signed_content(content, [{"Content-Type", MIME.from_path(resource_name)}], config()[:hackney_options])
      |> check_gcs_response()
    end
  end

  def delete_file(url), do: HTTPoison.delete(url)
  def put_signed_content(url, content, headers, options), do: HTTPoison.put(url, content, headers, options)
end
