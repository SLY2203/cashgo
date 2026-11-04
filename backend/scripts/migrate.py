"""Idempotent SQL migration runner — runs migrations/*.sql in order, tracking
applied files in a schema_migrations table. Needed because Render's free tier
has no shell access, so this runs in the release/build phase.

Usage:  python -m scripts.migrate
"""
import pathlib

import psycopg2

from app.core.config import settings

MIGRATIONS_DIR = pathlib.Path(__file__).resolve().parent.parent / "migrations"


def main() -> None:
    url = settings.DATABASE_URL
    if url.startswith("postgres://"):
        url = "postgresql://" + url[len("postgres://"):]
    conn = psycopg2.connect(url)
    conn.autocommit = True
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS schema_migrations (
            filename   TEXT PRIMARY KEY,
            applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
        )""")
    cur.execute("SELECT filename FROM schema_migrations")
    applied = {r[0] for r in cur.fetchall()}

    for path in sorted(MIGRATIONS_DIR.glob("*.sql")):
        if path.name in applied:
            print(f"skip  {path.name}")
            continue
        print(f"apply {path.name} ...")
        cur.execute(path.read_text(encoding="utf-8"))
        cur.execute("INSERT INTO schema_migrations (filename) VALUES (%s)",
                    (path.name,))
    conn.close()
    print("migrations done")


if __name__ == "__main__":
    main()
