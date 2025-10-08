defmodule Dashboard.Applications do
  @moduledoc """
  The Applications context for managing job applications.
  """

  import Ecto.Query, warn: false
  alias Dashboard.Repo
  alias Dashboard.Applications.Application

  @doc """
  Returns the list of applications.

  ## Examples

      iex> list_applications()
      [%Application{}, ...]

  """
  def list_applications(filters \\ %{}) do
    Application
    |> apply_filters(filters)
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single application.

  Raises `Ecto.NoResultsError` if the Application does not exist.

  ## Examples

      iex> get_application!(123)
      %Application{}

      iex> get_application!(456)
      ** (Ecto.NoResultsError)

  """
  def get_application!(id) do
    Application
    |> preload([:job, :custom_cv])
    |> Repo.get!(id)
  end

  @doc """
  Gets a single application, returns nil if not found.
  """
  def get_application(id) do
    Application
    |> preload([:job, :custom_cv])
    |> Repo.get(id)
  end

  @doc """
  Creates an application.

  ## Examples

      iex> create_application(%{field: value})
      {:ok, %Application{}}

      iex> create_application(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_application(attrs \\ %{}) do
    %Application{}
    |> Application.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an application.

  ## Examples

      iex> update_application(application, %{field: new_value})
      {:ok, %Application{}}

      iex> update_application(application, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_application(%Application{} = application, attrs) do
    application
    |> Application.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an application.

  ## Examples

      iex> delete_application(application)
      {:ok, %Application{}}

      iex> delete_application(application)
      {:error, %Ecto.Changeset{}}

  """
  def delete_application(%Application{} = application) do
    Repo.delete(application)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking application changes.

  ## Examples

      iex> change_application(application)
      %Ecto.Changeset{data: %Application{}}

  """
  def change_application(%Application{} = application, attrs \\ %{}) do
    Application.changeset(application, attrs)
  end

  @doc """
  Checks if an application already exists for a job.
  """
  def application_exists?(job_external_id) do
    from(a in Application, where: a.job_external_id == ^job_external_id)
    |> Repo.exists?()
  end

  @doc """
  Counts applications submitted today.
  """
  def count_applications_today do
    today_start = DateTime.utc_now() |> DateTime.to_date() |> DateTime.new!(~T[00:00:00])

    from(a in Application,
      where: a.submitted_at >= ^today_start,
      select: count(a.id)
    )
    |> Repo.one()
  end

  @doc """
  Gets application statistics.
  """
  def get_statistics do
    total = Repo.aggregate(Application, :count, :id)

    pending =
      from(a in Application, where: a.status == "pending")
      |> Repo.aggregate(:count, :id)

    submitted =
      from(a in Application, where: a.status == "submitted")
      |> Repo.aggregate(:count, :id)

    failed =
      from(a in Application, where: a.status == "failed")
      |> Repo.aggregate(:count, :id)

    %{
      total: total,
      pending: pending,
      submitted: submitted,
      failed: failed,
      today: count_applications_today()
    }
  end

  # Private functions

  defp apply_filters(query, filters) when filters == %{}, do: query

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:status, value}, query when is_binary(value) and value != "" ->
        from(a in query, where: a.status == ^value)

      _filter, query ->
        query
    end)
  end
end
