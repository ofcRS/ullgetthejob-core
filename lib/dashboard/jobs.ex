defmodule Dashboard.Jobs do
  @moduledoc """
  The Jobs context for managing job postings.
  """

  import Ecto.Query, warn: false
  alias Dashboard.Repo
  alias Dashboard.Jobs.Job

  @doc """
  Returns the list of jobs with optional filters.

  ## Examples

      iex> list_jobs()
      [%Job{}, ...]

      iex> list_jobs(%{title: "Elixir"})
      [%Job{}, ...]

  """
  def list_jobs(filters \\ %{}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    order = Keyword.get(opts, :order_by, desc: :fetched_at)

    Job
    |> apply_filters(filters)
    |> order_by(^order)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets a single job by external_id.

  Returns nil if the Job does not exist.

  ## Examples

      iex> get_job_by_external_id("123")
      %Job{}

      iex> get_job_by_external_id("456")
      nil

  """
  def get_job_by_external_id(external_id) do
    Repo.get_by(Job, external_id: external_id)
  end

  @doc """
  Creates or updates a job.

  ## Examples

      iex> upsert_job(%{field: value})
      {:ok, %Job{}}

      iex> upsert_job(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def upsert_job(attrs \\ %{}) do
    external_id = attrs[:external_id] || attrs["external_id"]

    case get_job_by_external_id(external_id) do
      nil ->
        %Job{}
        |> Job.changeset(attrs)
        |> Repo.insert()

      existing_job ->
        existing_job
        |> Job.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Bulk upserts jobs. Returns {:ok, count} on success.
  """
  def bulk_upsert_jobs(jobs_list) when is_list(jobs_list) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      Enum.map(jobs_list, fn job ->
        %{
          external_id: job.external_id || job[:external_id] || job["external_id"],
          title: job.title || job[:title] || job["title"],
          company: job.company || job[:company] || job["company"],
          salary: job.salary || job[:salary] || job["salary"],
          area: job.area || job[:area] || job["area"],
          url: job.url || job[:url] || job["url"],
          source: job[:source] || job["source"] || "hh.ru",
          search_query: job[:search_query] || job["search_query"],
          fetched_at: job[:fetched_at] || job["fetched_at"] || now,
          inserted_at: now,
          updated_at: now
        }
      end)

    {count, _} =
      Repo.insert_all(
        Job,
        entries,
        on_conflict:
          {:replace, [:title, :company, :salary, :area, :url, :fetched_at, :updated_at]},
        conflict_target: :external_id
      )

    {:ok, count}
  end

  @doc """
  Deletes old jobs. Keeps jobs from the last N days.

  ## Examples

      iex> delete_old_jobs(7)
      {5, nil}

  """
  def delete_old_jobs(keep_days \\ 7) do
    cutoff_date = DateTime.utc_now() |> DateTime.add(-keep_days, :day)

    from(j in Job, where: j.fetched_at < ^cutoff_date)
    |> Repo.delete_all()
  end

  @doc """
  Returns job statistics.
  """
  def get_statistics do
    total_jobs = Repo.aggregate(Job, :count, :id)

    recent_jobs =
      from(j in Job,
        where: j.fetched_at > ago(1, "day")
      )
      |> Repo.aggregate(:count, :id)

    top_companies =
      from(j in Job,
        where: not is_nil(j.company),
        group_by: j.company,
        select: {j.company, count(j.id)},
        order_by: [desc: count(j.id)],
        limit: 5
      )
      |> Repo.all()

    top_areas =
      from(j in Job,
        where: not is_nil(j.area),
        group_by: j.area,
        select: {j.area, count(j.id)},
        order_by: [desc: count(j.id)],
        limit: 5
      )
      |> Repo.all()

    %{
      total_jobs: total_jobs,
      recent_jobs: recent_jobs,
      top_companies: top_companies,
      top_areas: top_areas
    }
  end

  # Private functions

  defp apply_filters(query, filters) when filters == %{}, do: query

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:title, value}, query when is_binary(value) and value != "" ->
        from(j in query, where: ilike(j.title, ^"%#{value}%"))

      {:company, value}, query when is_binary(value) and value != "" ->
        from(j in query, where: ilike(j.company, ^"%#{value}%"))

      {:area, value}, query when is_binary(value) and value != "" ->
        from(j in query, where: ilike(j.area, ^"%#{value}%"))

      {:search_query, value}, query when is_binary(value) and value != "" ->
        from(j in query, where: j.search_query == ^value)

      _filter, query ->
        query
    end)
  end
end
