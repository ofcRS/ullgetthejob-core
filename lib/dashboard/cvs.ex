defmodule Dashboard.CVs do
  @moduledoc """
  The CVs context for managing CV/resume files.
  """

  import Ecto.Query, warn: false
  alias Dashboard.Repo
  alias Dashboard.CVs.CV

  @doc """
  Returns the list of CVs.

  ## Examples

      iex> list_cvs()
      [%CV{}, ...]

  """
  def list_cvs do
    CV
    |> where([c], c.is_active == true)
    |> order_by([c], desc: c.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single CV.

  Raises `Ecto.NoResultsError` if the CV does not exist.

  ## Examples

      iex> get_cv!(123)
      %CV{}

      iex> get_cv!(456)
      ** (Ecto.NoResultsError)

  """
  def get_cv!(id), do: Repo.get!(CV, id)

  @doc """
  Gets a single CV by ID, returns nil if not found.
  """
  def get_cv(id), do: Repo.get(CV, id)

  @doc """
  Creates a CV.

  ## Examples

      iex> create_cv(%{field: value})
      {:ok, %CV{}}

      iex> create_cv(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_cv(attrs \\ %{}) do
    %CV{}
    |> CV.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a CV.

  ## Examples

      iex> update_cv(cv, %{field: new_value})
      {:ok, %CV{}}

      iex> update_cv(cv, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_cv(%CV{} = cv, attrs) do
    cv
    |> CV.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Soft deletes a CV by marking it as inactive.

  ## Examples

      iex> delete_cv(cv)
      {:ok, %CV{}}

      iex> delete_cv(cv)
      {:error, %Ecto.Changeset{}}

  """
  def delete_cv(%CV{} = cv) do
    update_cv(cv, %{is_active: false})
  end

  @doc """
  Permanently deletes a CV from the database and its file from disk.
  """
  def delete_cv_permanently(%CV{} = cv) do
    # Delete the file from disk
    if File.exists?(cv.file_path) do
      File.rm(cv.file_path)
    end

    Repo.delete(cv)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking CV changes.

  ## Examples

      iex> change_cv(cv)
      %Ecto.Changeset{data: %CV{}}

  """
  def change_cv(%CV{} = cv, attrs \\ %{}) do
    CV.changeset(cv, attrs)
  end

  @doc """
  Gets the active CV (the most recently created active CV).
  """
  def get_active_cv do
    CV
    |> where([c], c.is_active == true)
    |> order_by([c], desc: c.inserted_at)
    |> limit(1)
    |> Repo.one()
  end
end
