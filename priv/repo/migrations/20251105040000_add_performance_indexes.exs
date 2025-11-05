defmodule Core.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  def change do
    # Index for faster token lookups by user_id and expiration
    create_if_not_exists index(:hh_tokens, [:user_id, :expires_at],
      name: :idx_hh_tokens_user_expires
    )

    # Index for job lookups by external_id (HH.ru job ID)
    create_if_not_exists index(:jobs, [:external_id],
      name: :idx_jobs_external_id
    )

    # Composite index for application lookups
    create_if_not_exists index(:applications, [:user_id, :job_id],
      name: :idx_applications_user_job
    )

    # Index for application status filtering
    create_if_not_exists index(:applications, [:status],
      name: :idx_applications_status
    )

    # Index for jobs by source and fetched timestamp
    create_if_not_exists index(:jobs, [:source, :fetched_at],
      name: :idx_jobs_source_fetched
    )
  end
end
