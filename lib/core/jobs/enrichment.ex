defmodule Core.Jobs.Enrichment do
  @moduledoc """
  Job enrichment service - adds additional details to job listings.
  Currently a passthrough; enrichment logic to be implemented.
  """

  @doc """
  Enrich a list of jobs with additional details.
  Currently passes through jobs unchanged.
  """
  def enrich_jobs(jobs) when is_list(jobs) do
    # TODO: Implement actual enrichment (fetch full job details, etc.)
    jobs
  end

  def enrich_jobs(job) do
    [job]
  end
end
