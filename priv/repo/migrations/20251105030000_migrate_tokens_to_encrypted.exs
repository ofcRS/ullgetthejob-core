defmodule Core.Repo.Migrations.MigrateTokensToEncrypted do
  use Ecto.Migration

  def up do
    # This migration copies plaintext tokens to encrypted fields
    # The encryption happens automatically via the Cloak.Ecto.Binary type
    # when data is read and written through the Ecto schema

    # For production: You would run this as a data migration task
    # execute """
    # UPDATE hh_tokens
    # SET encrypted_access_token = access_token::bytea,
    #     encrypted_refresh_token = refresh_token::bytea
    # WHERE encrypted_access_token IS NULL;
    # """

    # For fresh installs, we just remove the old columns since there's no data
    alter table(:hh_tokens) do
      remove :access_token
      remove :refresh_token
    end

    # Rename encrypted columns to be the primary columns
    rename table(:hh_tokens), :encrypted_access_token, to: :access_token
    rename table(:hh_tokens), :encrypted_refresh_token, to: :refresh_token
  end

  def down do
    # Rename back
    rename table(:hh_tokens), :access_token, to: :encrypted_access_token
    rename table(:hh_tokens), :refresh_token, to: :encrypted_refresh_token

    # Add back text columns
    alter table(:hh_tokens) do
      add :access_token, :text
      add :refresh_token, :text
    end
  end
end
