defmodule ApiWeb.Router do
  @moduledoc false

  use ApiWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/api", Api.Web do
    pipe_through(:api)

    post("/visits", VisitController, :create)
  end
end
