"""
models.py - the shape of data the API accepts, plus the profile card builder.

Pydantic checks every request automatically: wrong or missing fields get a clear error
before our code runs. Empty text ("") is turned into "not filled in" (None).
"""

from datetime import date
from typing import Literal, Optional

from pydantic import BaseModel, Field, field_validator

from app.db import SHAREABLE_FIELDS

CONSENT_VERSION = "v1"


def _clean_url(value, must_contain=None):
    """Trim, add https:// if missing, and optionally check the site (e.g. linkedin.com)."""
    if value is None:
        return None
    value = value.strip()
    if not value:
        return None
    if not value.lower().startswith(("http://", "https://")):
        value = "https://" + value
    if must_contain and must_contain not in value.lower():
        raise ValueError(f"must be a {must_contain} link")
    return value


class ProfileFields(BaseModel):
    """Optional card fields, shared by signup and edit."""
    student_status: Optional[Literal["student", "professional"]] = None
    college: Optional[str] = Field(None, max_length=120)
    course_year: Optional[str] = Field(None, max_length=60)
    job_title: Optional[str] = Field(None, max_length=80)
    company: Optional[str] = Field(None, max_length=80)
    skills: Optional[list[str]] = Field(None, max_length=15)
    github_url: Optional[str] = Field(None, max_length=200)
    instagram_url: Optional[str] = Field(None, max_length=200)
    portfolio_url: Optional[str] = Field(None, max_length=200)

    @field_validator("college", "course_year", "job_title", "company", mode="before")
    @classmethod
    def blank_to_none(cls, v):
        return (v.strip() or None) if isinstance(v, str) else v

    @field_validator("student_status", mode="before")
    @classmethod
    def blank_status(cls, v):
        return None if v == "" else v

    @field_validator("skills")
    @classmethod
    def clean_skills(cls, v):
        if v is None:
            return None
        return [s.strip()[:40] for s in v if s and s.strip()]

    @field_validator("github_url")
    @classmethod
    def check_github(cls, v):
        return _clean_url(v, "github.com")

    @field_validator("instagram_url")
    @classmethod
    def check_instagram(cls, v):
        return _clean_url(v, "instagram.com")

    @field_validator("portfolio_url")
    @classmethod
    def check_portfolio(cls, v):
        return _clean_url(v)


class SignupIn(ProfileFields):
    username: str = Field(min_length=3, max_length=64, description="Email or a username")
    password: str = Field(min_length=8, max_length=128)
    name: str = Field(min_length=1, max_length=80)
    linkedin_url: str = Field(max_length=200)
    consent: bool = Field(description="Must be true: the user accepted the consent screen")
    borrowed: bool = Field(False, description="True on someone else's phone (short login)")

    @field_validator("username")
    @classmethod
    def lower_username(cls, v):
        return v.strip().lower()

    @field_validator("name")
    @classmethod
    def strip_name(cls, v):
        v = v.strip()
        if not v:
            raise ValueError("name is required")
        return v

    @field_validator("linkedin_url")
    @classmethod
    def check_linkedin(cls, v):
        v = _clean_url(v, "linkedin.com/")
        if not v:
            raise ValueError("LinkedIn link is required")
        return v


class LoginIn(BaseModel):
    username: str
    password: str
    borrowed: bool = False

    @field_validator("username")
    @classmethod
    def lower_username(cls, v):
        return v.strip().lower()


class ProfileUpdate(ProfileFields):
    """Edit my profile. Only the fields you send are changed."""
    name: Optional[str] = Field(None, min_length=1, max_length=80)
    linkedin_url: Optional[str] = Field(None, max_length=200)
    visible: Optional[bool] = Field(None, description="False = hide me (I show up as Unknown)")
    share: Optional[dict[str, bool]] = Field(None, description="e.g. {\"instagram_url\": false}")

    @field_validator("linkedin_url")
    @classmethod
    def check_linkedin(cls, v):
        if v is None:
            return None
        v = _clean_url(v, "linkedin.com/")
        if not v:
            raise ValueError("LinkedIn link can't be removed (it's required)")
        return v

    @field_validator("share")
    @classmethod
    def check_share(cls, v):
        if v is None:
            return None
        unknown = set(v) - set(SHAREABLE_FIELDS)
        if unknown:
            raise ValueError(f"these fields can't be switched off: {sorted(unknown)}")
        return v


class AdminLoginIn(BaseModel):
    admin_id: str
    password: str
    otp: str = Field(description="6-digit code from the authenticator app")


class AdminUserUpdate(BaseModel):
    visible: bool


class EventIn(BaseModel):
    """Start (or change) the current event. New sign-ups are tagged with it."""
    name: str = Field(min_length=2, max_length=60, description="e.g. KLE Tech Expo 2026")
    delete_after_date: Optional[date] = Field(
        None, description="YYYY-MM-DD. Everyone from this event is deleted after this day. Empty = keep")

    @field_validator("name")
    @classmethod
    def strip_name(cls, v):
        return v.strip()


def build_card(user):
    """
    The profile card others see. Name + LinkedIn are always there; every other field is
    included only if it's filled in AND the user hasn't switched it off (extra B).
    Empty fields are left out completely, never shown as "not found".
    """
    card = {"user_id": user["id"], "name": user["name"], "linkedin_url": user["linkedin_url"]}
    for field in SHAREABLE_FIELDS:
        value = user.get(field)
        if value and user["share"].get(field, True):
            card[field] = value
    return card
