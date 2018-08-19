defmodule Api.Web.VisitController do
  @moduledoc false

  use ApiWeb, :controller
  alias Api.Web.JobView
  alias Core.Patients

  action_fallback(Api.Web.FallbackController)

  def create(conn, params) do
    with {:ok, job} <- Patients.produce_create_visit(params) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("create.json", job: job)
    end
  end
end
