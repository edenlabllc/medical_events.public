defmodule Core.Patients.MedicationStatements do
  @moduledoc false

  alias Core.Maybe
  alias Core.MedicationStatement
  alias Core.Mongo
  alias Core.Paging
  alias Core.Patient
  alias Core.Patients.Encounters
  alias Core.Search
  alias Core.Validators.JsonSchema
  alias Scrivener.Page
  require Logger

  @collection Patient.collection()

  def get_by_id(patient_id_hash, id) do
    with %{"medication_statements" => %{^id => medication_statement}} <-
           Mongo.find_one(
             @collection,
             %{
               "_id" => patient_id_hash,
               "medication_statements.#{id}" => %{"$exists" => true}
             },
             projection: ["medication_statements.#{id}": true]
           ) do
      {:ok, MedicationStatement.create(medication_statement)}
    else
      _ ->
        nil
    end
  end

  def get_by_id_episode_id(patient_id_hash, id, episode_id) do
    encounter_ids = get_encounter_ids(patient_id_hash, Mongo.string_to_uuid(episode_id))

    pipeline = [
      %{
        "$match" => %{
          "_id" => patient_id_hash
        }
      },
      %{"$project" => %{"medication_statements" => %{"$objectToArray" => "$medication_statements"}}},
      %{"$unwind" => "$medication_statements"},
      %{
        "$match" => %{
          "medication_statements.k" => id,
          "medication_statements.v.context.identifier.value" => %{"$in" => encounter_ids}
        }
      },
      %{
        "$project" => %{"medication_statement" => "$medication_statements.v"}
      }
    ]

    with [%{"medication_statement" => medication_statement}] <-
           @collection |> Mongo.aggregate(pipeline) |> Enum.to_list() do
      {:ok, MedicationStatement.create(medication_statement)}
    else
      _ ->
        nil
    end
  end

  def list(%{"patient_id_hash" => patient_id_hash} = params, schema \\ :medication_statement_request) do
    with :ok <- JsonSchema.validate(schema, Map.drop(params, ~w(page page_size patient_id patient_id_hash))) do
      pipeline =
        [
          %{"$match" => %{"_id" => patient_id_hash}},
          %{"$project" => %{"medication_statements" => %{"$objectToArray" => "$medication_statements"}}},
          %{"$unwind" => "$medication_statements"}
        ]
        |> add_search_pipeline(patient_id_hash, params)
        |> Enum.concat([
          %{"$project" => %{"medication_statement" => "$medication_statements.v"}},
          %{"$replaceRoot" => %{"newRoot" => "$medication_statement"}},
          %{"$sort" => %{"inserted_at" => -1}}
        ])

      with %Page{entries: medication_statements} = paging <-
             Paging.paginate(:aggregate, @collection, pipeline, Map.take(params, ~w(page page_size))) do
        {:ok, %Page{paging | entries: Enum.map(medication_statements, &MedicationStatement.create/1)}}
      end
    end
  end

  defp add_search_pipeline(pipeline, patient_id_hash, params) do
    path = "medication_statements.v"
    encounter_id = Maybe.map(params["encounter_id"], &Mongo.string_to_uuid(&1))
    asserted_date_from = Search.get_filter_date(:from, params["asserted_date_from"])
    asserted_date_to = Search.get_filter_date(:to, params["asserted_date_to"])

    episode_id = if params["episode_id"], do: Mongo.string_to_uuid(params["episode_id"])
    encounter_ids = if !is_nil(episode_id), do: get_encounter_ids(patient_id_hash, episode_id)

    search_pipeline =
      %{"$match" => %{}}
      |> Search.add_param(
        %{"code" => params["medication_code"]},
        ["$match", "#{path}.medication_code.coding"],
        "$elemMatch"
      )
      |> Search.add_param(encounter_id, ["$match", "#{path}.context.identifier.value"])
      |> add_search_param(encounter_ids, ["$match", "#{path}.context.identifier.value"], "$in")
      |> Search.add_param(asserted_date_from, ["$match", "#{path}.asserted_date"], "$gte")
      |> Search.add_param(asserted_date_to, ["$match", "#{path}.asserted_date"], "$lt")

    search_pipeline
    |> Map.get("$match", %{})
    |> Map.keys()
    |> case do
      [] -> pipeline
      _ -> pipeline ++ [search_pipeline]
    end
  end

  def get_encounter_ids(patient_id_hash, episode_id) do
    patient_id_hash
    |> Encounters.get_episode_encounters(episode_id)
    |> Enum.map(& &1["encounter_id"])
    |> Enum.uniq()
  end

  defp add_search_param(search_params, nil, _path, _operator), do: search_params

  defp add_search_param(search_params, value, path, operator) do
    if get_in(search_params, path) == nil do
      put_in(search_params, path, %{operator => value})
    else
      update_in(search_params, path, &Map.merge(&1, %{operator => value}))
    end
  end

  def get_by_encounter_id(patient_id_hash, %BSON.Binary{} = encounter_id) do
    @collection
    |> Mongo.aggregate([
      %{"$match" => %{"_id" => patient_id_hash}},
      %{"$project" => %{"medication_statements" => %{"$objectToArray" => "$medication_statements"}}},
      %{"$unwind" => "$medication_statements"},
      %{"$match" => %{"medication_statements.v.context.identifier.value" => encounter_id}},
      %{"$replaceRoot" => %{"newRoot" => "$medication_statements.v"}}
    ])
    |> Enum.map(&MedicationStatement.create/1)
  end
end
