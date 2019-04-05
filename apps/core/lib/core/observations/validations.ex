defmodule Core.Observations.Validations do
  @moduledoc false

  import Core.Schema, only: [add_validations: 3]

  alias Core.EffectiveAt
  alias Core.Observation
  alias Core.Observations.Component
  alias Core.Observations.Value
  alias Core.Period
  alias Core.Reference
  alias Core.Source

  def validate_issued(%Observation{} = observation) do
    now = DateTime.utc_now()
    max_days_passed = Confex.fetch_env!(:core, :encounter_package)[:observation_max_days_passed]

    add_validations(
      observation,
      :issued,
      datetime: [less_than_or_equal_to: now, message: "Issued datetime must be in past"],
      max_days_passed: [max_days_passed: max_days_passed]
    )
  end

  def validate_context(%Observation{context: context} = observation, encounter_id) do
    identifier =
      add_validations(
        context.identifier,
        :value,
        value: [equals: encounter_id, message: "Submitted context is not allowed for the observation"]
      )

    %{observation | context: %{context | identifier: identifier}}
  end

  def validate_source(%Observation{source: %Source{type: "performer"}} = observation, client_id) do
    observation =
      add_validations(
        observation,
        :source,
        source: [primary_source: observation.primary_source, primary_required: "performer"]
      )

    source = observation.source
    source = %{source | value: validate_performer(source.value, client_id)}
    %{observation | source: source}
  end

  def validate_source(%Observation{} = observation, _) do
    add_validations(observation, :source, source: [primary_source: observation.primary_source])
  end

  def validate_components(%Observation{components: nil} = observation), do: observation

  def validate_components(%Observation{} = observation) do
    %{observation | components: Enum.map(observation.components, &validate_component_value/1)}
  end

  def validate_performer(%Reference{} = performer, client_id) do
    identifier =
      add_validations(
        performer.identifier,
        :value,
        employee: [
          type: "DOCTOR",
          status: "APPROVED",
          legal_entity_id: client_id,
          messages: [
            type: "Employee is not an active doctor",
            status: "Employee is not an active doctor",
            legal_entity_id: "Employee #{performer.identifier.value} doesn't belong to your legal entity"
          ]
        ]
      )

    %{performer | identifier: identifier}
  end

  def validate_value(%Observation{value: %Value{type: type, value: %Period{}} = value} = observation) do
    add_validations(
      %{observation | value: %{value | value: validate_period(value.value)}},
      :value,
      reference: [path: type]
    )
  end

  def validate_value(%Observation{value: %Value{type: type}} = observation) do
    add_validations(observation, :value, reference: [path: type])
  end

  def validate_value(%Observation{} = observation), do: observation

  def validate_component_value(%Component{value: %Value{type: type, value: %Period{}} = value} = component) do
    add_validations(
      %{component | value: %{value | value: validate_period(value.value)}},
      :value,
      reference: [path: type]
    )
  end

  def validate_component_value(%Component{value: %Value{type: type}} = component) do
    add_validations(component, :value, reference: [path: type])
  end

  def validate_component_value(%Component{} = component), do: component

  def validate_effective_at(%Observation{effective_at: %EffectiveAt{type: "effective_period"}} = observation) do
    effective_at = %{observation.effective_at | value: validate_period(observation.effective_at.value)}
    %{observation | effective_at: effective_at}
  end

  def validate_effective_at(%Observation{} = observation), do: observation

  defp validate_period(%Period{} = period) do
    now = DateTime.utc_now()

    period =
      add_validations(
        period,
        :start,
        datetime: [less_than_or_equal_to: now, message: "Start date must be in past"]
      )

    if period.end do
      add_validations(
        period,
        :end,
        datetime: [greater_than: period.start, message: "End date must be greater than the start date"]
      )
    else
      period
    end
  end

  def validate_diagnostic_report(%Observation{diagnostic_report: nil} = observation, _, _), do: observation

  def validate_diagnostic_report(
        %Observation{diagnostic_report: diagnostic_report} = observation,
        patient_id_hash,
        diagnostic_reports
      ) do
    identifier =
      add_validations(
        diagnostic_report.identifier,
        :value,
        diagnostic_report_context: [
          patient_id_hash: patient_id_hash,
          diagnostic_reports: diagnostic_reports,
          payload_only: true
        ]
      )

    %{observation | diagnostic_report: %{diagnostic_report | identifier: identifier}}
  end

  def validate_diagnostic_report(%Observation{diagnostic_report: diagnostic_report} = observation, diagnostic_report_id) do
    identifier =
      add_validations(
        diagnostic_report.identifier,
        :value,
        value: [equals: diagnostic_report_id, message: "Submitted diagnostic report is not allowed for the observation"]
      )

    %{observation | diagnostic_report: %{diagnostic_report | identifier: identifier}}
  end
end
