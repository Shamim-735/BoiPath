from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

Status = Literal["draft", "pending", "unavailable", "archived", "verified"]


class BookInput(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")
    official_title: str = Field(min_length=1, max_length=240)
    alternative_title: str | None = Field(default=None, max_length=240)
    subject_id: str = Field(min_length=1, max_length=64)
    class_id: int = Field(ge=1, le=12)
    class_end_id: int | None = Field(default=None, ge=2, le=12)
    academic_year: int = Field(ge=2000, le=2100)
    language_version: Literal["bn", "en"]
    curriculum_track: str = Field(min_length=1, max_length=100)
    edition: str = Field(default="", max_length=100)
    source_url: str = Field(min_length=10, max_length=2000)
    pdf_url: str | None = Field(default=None, max_length=2000)
    cover_url: str | None = Field(default=None, max_length=2000)
    verification_status: Status = "draft"

    @model_validator(mode="after")
    def check_class_range(self):
        if self.class_end_id is not None and self.class_end_id <= self.class_id:
            raise ValueError("Ending class must be greater than starting class")
        return self


class Credentials(BaseModel):
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=1, max_length=256, repr=False)

    @field_validator("email")
    @classmethod
    def email_address(cls, value):
        value = value.strip().casefold()
        if value.count("@") != 1 or not all(value.split("@")) or any(ch.isspace() for ch in value):
            raise ValueError("Enter a valid email address")
        return value


class Refresh(BaseModel):
    refresh_token: str = Field(min_length=40, max_length=128, repr=False)


class Report(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    textbook_id: str = Field(min_length=1, max_length=36)
    issue_type: Literal["broken_link", "metadata", "other"]
    description: str = Field(min_length=1, max_length=1000)
