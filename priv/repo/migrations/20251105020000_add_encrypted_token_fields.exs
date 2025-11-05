defmodule Core.Repo.Migrations.AddEncryptedTokenFields do
  use Ecto.Migration

  def up do
    # Add new encrypted columns for tokens
    alter table(:hh_tokens) do
      add :encrypted_access_token, :binary
      add :encrypted_refresh_token, :binary
    end

    # NOTE: Migration strategy for existing data:
    # 1. New encrypted columns are added as nullable
    # 2. Deploy code that writes to BOTH old and new columns
    # 3. Run data migration to encrypt existing tokens
    # 4. Deploy code that reads from encrypted columns
    # 5. Run final migration to drop old columns
    #
    # For fresh installs, this is simpler - just use encrypted fields from start.
    # If you have existing data, you'll need a more complex migration strategy.
    #
    # For now, we assume this is a fresh install or acceptable data loss scenario.
  end

  def down do
    alter table(:hh_tokens) do
      remove :encrypted_access_token
      remove :encrypted_refresh_token
    end
  end
end
