locals {
  db_host          = ""
  metabase_version = "v0.50.22"
  public_subnets   = [""]
  private_subnets  = [""]
  redash_db_pass   = ""
  redash_version   = "10.0.0.b50363"
  sg_alb           = ""
  sg_ecs           = ""
  vpc_id           = ""

  metabase_secrets = {
    MB_DB_DBNAME = "metabase"
    MB_DB_PASS   = ""
    MB_DB_USER   = "metabase"
    MB_DB_HOST   = local.db_host
  }

  redash_secrets = {
    # refs:) https://redash.io/help/open-source/admin-guide/secrets/
    REDASH_COOKIE_SECRET = ""
    REDASH_DATABASE_URL  = "postgresql://redash:${local.redash_db_pass}@${local.db_host}:5432/redash"
    REDASH_SECRET_KEY    = ""
  }
}
