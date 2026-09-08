from typing import Optional

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, EmailStr

app = FastAPI(
    title="accounts-api",
    version="0.1.0",
)


class Account(BaseModel):
    account_id: str
    name: str
    email: EmailStr
    phone: str
    iban: str
    balance: float
    card_last4: str


DEMO_ACCOUNT = Account(
    account_id="acct-001",
    name="Ahmed Example",
    email="ahmed@example.com",
    phone="+97450000000",
    iban="QA00BANK0000000000000001",
    balance=12500.50,
    card_last4="4242",
)


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.get("/v1/accounts/{account_id}", response_model=Account)
def get_account(
    account_id: str,
    x_user_id: Optional[str] = Header(default=None),
) -> Account:
    # Simplified authentication/authorization boundary for the lab.
    # Production identity would be supplied by the real edge/IdP.
    if not x_user_id:
        raise HTTPException(status_code=401, detail="authentication required")

    if account_id != DEMO_ACCOUNT.account_id:
        raise HTTPException(status_code=404, detail="account not found")

    # In production this would enforce ownership/entitlement.
    if x_user_id != "customer-001":
        raise HTTPException(status_code=403, detail="forbidden")

    return DEMO_ACCOUNT


@app.get("/v1/accounts")
def list_accounts(
    x_user_id: Optional[str] = Header(default=None),
) -> dict:
    if not x_user_id:
        raise HTTPException(status_code=401, detail="authentication required")

    if x_user_id != "customer-001":
        raise HTTPException(status_code=403, detail="forbidden")

    return {"accounts": [DEMO_ACCOUNT]}


@app.post("/v1/events/audit")
def audit_event(event: dict) -> dict:
    # Deliberately keep the example endpoint simple.
    # Security work later will ensure sensitive request data is not logged.
    return {"accepted": True, "event_type": event.get("type", "unknown")}