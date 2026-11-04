# CashGo

Cross-border African remittance MVP — FastAPI + PostgreSQL/PostGIS backend, Flutter mobile app.

## Structure

```
backend/            FastAPI app
  app/models.py     SQLAlchemy models (incl. PostGIS geography column)
  app/services/     fx.py (rate provider + cache), fees.py (tiered fee engine), messaging.py (SMS sim + voucher)
  app/api/v1/       remittances.py, agents.py, admin.py
  migrations/001_init.sql   full schema incl. PostGIS + seed notes
  scripts/seed.py   demo data
mobile/             Flutter app (Provider state, flutter_map, qr_flutter)
docker-compose.yml  PostGIS 16 container
```

## Backend quickstart

```bash
docker compose up -d                      # start PostGIS
psql -h localhost -U postgres -d cashgo -f backend/migrations/001_init.sql
cd backend
python -m venv .venv && .venv\Scripts\activate
pip install -r requirements.txt
python -m scripts.seed                    # prints demo sender UUID
uvicorn app.main:app --reload             # http://localhost:8000/docs
```

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| POST | `/api/v1/auth/register/` | Create user (returns JWT) |
| POST | `/api/v1/auth/otp/request/` | Send login OTP (returns `dev_code` in simulator) |
| POST | `/api/v1/auth/otp/verify/` | Verify OTP → JWT |
| GET/POST | `/api/v1/wallets/`, `/wallets/topup/` | Balances + dev top-up (auth) |
| POST | `/api/v1/remittances/quote/` | FX quote: fee + spread + payout, 60s lock |
| POST | `/api/v1/remittances/transfer/` | KYC-gated: escrow funds → `CG-XXXX-XXXX` voucher + SMS sim |
| POST | `/api/v1/remittances/transactions/{id}/cancel` | Cancel → escrow released back |
| GET  | `/api/v1/agents/nearest/` | PostGIS `ST_DWithin`/`ST_Distance` nearest agents |
| POST | `/api/v1/agents/redeem/` | Agent pays out voucher → `COMPLETED`, escrow settled |
| POST/GET/PATCH/DELETE | `/api/v1/admin/fees/` | Fee tier CRUD — requires `X-Admin-Key` header |

Auth: pass `Authorization: Bearer <jwt>` on wallet/transfer/transaction routes.

### Example

```bash
curl -X POST localhost:8000/api/v1/remittances/quote/ \
  -H 'Content-Type: application/json' -d '{
    "source_country":"US","dest_country":"NG",
    "send_currency":"USD","payout_currency":"NGN","send_amount":200}'

curl "localhost:8000/api/v1/agents/nearest/?latitude=6.5244&longitude=3.3792&dest_country=NG"
```

## Deploy to Render (free tier)

`render.yaml` is a Blueprint — Render dashboard → **New → Blueprint** → connect this repo. It provisions:

- **cashgo-api** (free web service): `pip install` → at startup runs `scripts/migrate` (idempotent, no shell needed) → `gunicorn` + uvicorn workers
- **cashgo-db** (free Postgres 16): `CREATE EXTENSION postgis` runs inside migration 001 — Render supports it
- `JWT_SECRET` / `ADMIN_API_KEY` are auto-generated; `DATABASE_URL` is wired from the DB (`postgres://` → `postgresql+psycopg2://` is normalized in `config.py`)

Free-tier notes:
- Services **sleep after ~15 min idle** — first request after sleep takes ~30s (quote endpoint unaffected once warm).
- Free Postgres **expires after 30 days** — export data or upgrade before then.
- `SEED_DEMO=true` loads demo user/agents on first boot; **remove it** from the Render dashboard afterwards.
- Update the Flutter client: `CashGoApi(baseUrl: 'https://cashgo-api.onrender.com/api/v1')`.

## Flutter quickstart

```bash
cd mobile
flutter pub get
flutter run --dart-define=SENDER_ID=<uuid from seed>
```

Screens: **Send Money** (corridor picker, debounced live quote, fee breakdown, 60s lock countdown) → **Voucher/Receipt** (QR + status timeline), **Agent Map** (OSM pins, distance badges, hours, directions via Google Maps deep-link).

## Notes & next steps

- FX provider defaults to open.er-api.com with 5-min cache + offline fallback table; swap in a paid provider for prod.
- Fee semantics: fee is charged **on top** of `send_amount` (`total_debit = amount + fee`); adjust `fees.py` for fee-inclusive corridors.
- Escrow model: funds move `balance → escrowed` at transfer, `escrowed → 0` at redemption, `escrowed → balance` on cancel — all journaled in `ledger_entries`.
- Still needed for prod: real SMS provider (Twilio/Africa's Talking), KYC document upload + verification webhook, agent-app auth on redeem, RBAC instead of the static admin key, idempotency keys on POST endpoints.
