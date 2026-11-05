from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    DATABASE_URL: str = "postgresql+psycopg2://postgres:postgres@localhost:5432/cashgo"
    FX_API_URL: str = "https://open.er-api.com/v6/latest"  # free mid-market rates
    FX_CACHE_TTL_SECONDS: int = 300
    QUOTE_TTL_SECONDS: int = 60
    DEFAULT_AGENT_RADIUS_M: int = 15000
    JWT_SECRET: str = "dev-secret-change-me"
    JWT_TTL_SECONDS: int = 86400
    OTP_TTL_SECONDS: int = 300
    OTP_MAX_ATTEMPTS: int = 5
    ADMIN_API_KEY: str = "dev-admin-key"
    AGENT_API_KEY: str = "dev-agent-key"
    # Provider keys — leave blank for simulator/dev mode
    PAYSTACK_SECRET_KEY: str = ""
    AT_USERNAME: str = ""       # Africa's Talking username ("sandbox" in test)
    AT_API_KEY: str = ""
    AT_SENDER_ID: str = "CASHGO"
    SMILE_PARTNER_ID: str = ""  # Smile Identity
    SMILE_API_KEY: str = ""

    class Config:
        env_file = ".env"

    @property
    def sqlalchemy_url(self) -> str:
        url = self.DATABASE_URL
        if url.startswith("postgres://"):
            url = url.replace("postgres://", "postgresql+psycopg2://", 1)
        return url


settings = Settings()
