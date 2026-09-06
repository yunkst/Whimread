#!/usr/bin/env python3
"""
Client log model for remote log reporting.

Stores logs uploaded from the Flutter mobile application.
"""

from datetime import UTC, datetime

from sqlalchemy import DateTime, Index, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from ..database import Base


class ClientLog(Base):
    """客户端日志表"""

    __tablename__ = "client_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    level: Mapped[str] = mapped_column(
        String(10), nullable=False, index=True
    )  # debug/info/warning/error
    message: Mapped[str] = mapped_column(Text, nullable=False)
    stack_trace: Mapped[str | None] = mapped_column(Text, nullable=True)
    category: Mapped[str] = mapped_column(
        String(20), nullable=False, default="general", index=True
    )  # database/network/ai/ui/cache/tts/character/backup/general
    tags: Mapped[str | None] = mapped_column(Text, nullable=True)  # JSON array string
    timestamp: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, index=True
    )  # client-side timestamp (UTC)
    received_at: Mapped[datetime | None] = mapped_column(
        DateTime, default=lambda: datetime.now(UTC)
    )  # server-side timestamp

    __table_args__ = (
        Index("idx_level_timestamp", "level", "timestamp"),
        Index("idx_received_at", "received_at"),
        Index("idx_category_timestamp", "category", "timestamp"),
    )

    def __repr__(self):
        return (
            f"<ClientLog(id={self.id}, level={self.level}, timestamp={self.timestamp})>"
        )
