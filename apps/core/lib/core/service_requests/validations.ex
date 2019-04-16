defmodule Core.ServiceRequests.Validations do
  @moduledoc false

  import Core.Schema, only: [add_validations: 3]

  alias Core.Episode
  alias Core.Microservices.DigitalSignature
  alias Core.ServiceRequest
  alias Core.ServiceRequests.Occurrence

  def validate_signatures(%ServiceRequest{} = service_request, %{"drfo" => drfo}, user_id, client_id) do
    if DigitalSignature.config()[:enabled] do
      requester_employee = service_request.requester_employee

      identifier =
        add_validations(
          requester_employee.identifier,
          :value,
          drfo: [drfo: drfo, client_id: client_id, user_id: user_id]
        )

      %{service_request | requester_employee: %{requester_employee | identifier: identifier}}
    else
      service_request
    end
  end

  def validate_context(%ServiceRequest{} = service_request, patient_id_hash) do
    context = service_request.context

    identifier =
      add_validations(
        context.identifier,
        :value,
        encounter_reference: [patient_id_hash: patient_id_hash]
      )

    %{service_request | context: %{context | identifier: identifier}}
  end

  def validate_occurrence(%ServiceRequest{occurrence: %Occurrence{type: "date_time"} = occurrence} = service_request) do
    now = DateTime.utc_now()

    occurrence =
      add_validations(
        occurrence,
        :value,
        datetime: [greater_than: now, message: "Occurrence date must be in the future"]
      )

    %{service_request | occurrence: occurrence}
  end

  def validate_occurrence(%ServiceRequest{occurrence: %Occurrence{type: "period"} = occurrence} = service_request) do
    now = DateTime.utc_now()

    occurrence =
      occurrence.value
      |> add_validations(
        :start,
        datetime: [greater_than: now, message: "Occurrence start date must be in the future"]
      )
      |> add_validations(
        :end,
        datetime: [
          greater_than: occurrence.value.start,
          message: "Occurrence end date must be greater than the start date"
        ]
      )

    %{service_request | occurrence: occurrence}
  end

  def validate_occurrence(service_request), do: service_request

  def validate_authored_on(%ServiceRequest{} = service_request) do
    add_validations(service_request, :authored_on, datetime: [less_than: DateTime.utc_now()])
  end

  def validate_supporting_info(%ServiceRequest{supporting_info: nil} = service_request, _), do: service_request

  def validate_supporting_info(%ServiceRequest{} = service_request, patient_id_hash) do
    supporting_info =
      Enum.map(service_request.supporting_info, fn info ->
        reference_type = info.identifier.type.coding |> List.first() |> Map.get(:code)

        identifier =
          case reference_type do
            "episode_of_care" ->
              add_validations(info.identifier, :value,
                episode_reference: [patient_id_hash: patient_id_hash, status: Episode.status(:active)]
              )

            "diagnostic_report" ->
              add_validations(info.identifier, :value, diagnostic_report_reference: [patient_id_hash: patient_id_hash])
          end

        %{info | identifier: identifier}
      end)

    %{service_request | supporting_info: supporting_info}
  end

  def validate_reason_reference(%ServiceRequest{} = service_request, patient_id_hash) do
    reason_references = service_request.reason_reference || []

    references =
      Enum.map(reason_references, fn reference ->
        identifier = reference.identifier
        reference_type = identifier.type.coding |> List.first() |> Map.get(:code)

        case reference_type do
          "observation" ->
            add_validations(identifier, :value, observation_reference: [patient_id_hash: patient_id_hash])

          "condition" ->
            add_validations(identifier, :value, condition_reference: [patient_id_hash: patient_id_hash])
        end
      end)

    %{service_request | reason_reference: references}
  end

  def validate_permitted_resources(%ServiceRequest{permitted_resources: nil} = service_request, _), do: service_request

  def validate_permitted_resources(%ServiceRequest{} = service_request, patient_id_hash) do
    permitted_resources = service_request.permitted_resources || []

    category_value =
      if is_nil(service_request.category) do
        service_request.category
      else
        service_request.category.coding |> List.first() |> Map.get(:code)
      end

    service_request =
      if category_value == ServiceRequest.category(:laboratory_procedure) do
        add_validations(service_request, :permitted_resources,
          value: [
            equals: [],
            message: "Permitted resources are not allowed for laboratory category of service request"
          ]
        )
      else
        service_request
      end

    permitted_resources =
      if category_value == ServiceRequest.category(:laboratory_procedure) do
        permitted_resources
      else
        Enum.map(permitted_resources, fn permitted_resource ->
          reference_type = permitted_resource.identifier.type.coding |> List.first() |> Map.get(:code)

          identifier =
            case reference_type do
              "episode_of_care" ->
                add_validations(permitted_resource.identifier, :value,
                  episode_reference: [patient_id_hash: patient_id_hash, status: Episode.status(:active)]
                )

              "diagnostic_report" ->
                add_validations(permitted_resource.identifier, :value,
                  diagnostic_report_reference: [patient_id_hash: patient_id_hash]
                )
            end

          %{permitted_resource | identifier: identifier}
        end)
      end

    %{service_request | permitted_resources: permitted_resources}
  end

  def validate_used_by_employee(%ServiceRequest{used_by_employee: nil} = service_request, _), do: service_request

  def validate_used_by_employee(%ServiceRequest{used_by_employee: used_by_employee} = service_request, client_id) do
    identifier =
      add_validations(used_by_employee.identifier, :value,
        employee: [
          type: "DOCTOR",
          status: "APPROVED",
          legal_entity_id: client_id,
          messages: [
            type: "Employee is not an active doctor",
            status: "Employee is not approved",
            legal_entity_id: "Employee #{used_by_employee.identifier.value} doesn't belong to your legal entity"
          ]
        ]
      )

    %{service_request | used_by_employee: %{used_by_employee | identifier: identifier}}
  end

  def validate_used_by_legal_entity(
        %ServiceRequest{used_by_legal_entity: used_by_legal_entity} = service_request,
        client_id
      ) do
    identifier =
      add_validations(used_by_legal_entity.identifier, :value,
        value: [equals: client_id, message: "You can assign service request only to your legal entity"]
      )

    %{service_request | used_by_legal_entity: %{used_by_legal_entity | identifier: identifier}}
  end

  def validate_expiration_date(%ServiceRequest{} = service_request) do
    add_validations(service_request, :expiration_date, datetime: [greater_than_or_equal_to: DateTime.utc_now()])
  end

  def validate_completed_with(%ServiceRequest{} = service_request, patient_id_hash) do
    completed_with = service_request.completed_with
    reference_type = completed_with.identifier.type.coding |> List.first() |> Map.get(:code)

    identifier =
      case reference_type do
        "encounter" ->
          add_validations(completed_with.identifier, :value, encounter_reference: [patient_id_hash: patient_id_hash])

        "diagnostic_report" ->
          add_validations(completed_with.identifier, :value,
            diagnostic_report_reference: [patient_id_hash: patient_id_hash]
          )
      end

    %{service_request | completed_with: %{completed_with | identifier: identifier}}
  end

  def validate_requester_legal_entity(
        %ServiceRequest{requester_legal_entity: requester_legal_entity} = service_request,
        client_id
      ) do
    identifier =
      add_validations(requester_legal_entity.identifier, :value,
        value: [equals: client_id, message: "Must be current legal enity"]
      )

    %{service_request | requester_legal_entity: %{requester_legal_entity | identifier: identifier}}
  end

  def validate_code(%ServiceRequest{code: nil} = service_request), do: service_request

  def validate_code(%ServiceRequest{code: code} = service_request) do
    reference_type = code.identifier.type.coding |> List.first() |> Map.get(:code)

    category =
      if service_request.category do
        service_request.category.coding |> List.first() |> Map.get(:code)
      end

    identifier =
      case reference_type do
        "service" ->
          add_validations(code.identifier, :value, service_reference: [category: category])

        "service_group" ->
          add_validations(code.identifier, :value, service_group_reference: [])
      end

    %{service_request | code: %{code | identifier: identifier}}
  end
end
