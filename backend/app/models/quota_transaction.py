#!/usr/bin/env python3
"""
QuotaTransaction model — 额度流水账本。

余额的每一次变动都必须落一条流水（发放/扣费/管理员调整），
任何时刻 quota_balance == sum(delta)，可审计可对账。
"""

from datetime import UTC, datetime

from sqlalchemy import DateTime, ForeignKey, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from ..database import Base


class QuotaTransaction(Base):
    """额度流水表"""

    __tablename__ = "quota_transactions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    device_id: Mapped[int] = mapped_column(
        ForeignKey("devices.id", ondelete="CASCADE"), nullable=False, index=True
    )
    # 正数=充值/发放，负数=消耗
    delta: Mapped[int] = mapped_column(Integer, nullable=False)
    # free_grant（新设备免费额度）/ usage（LLM 调用消耗）/ admin（人工调整）
    reason: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    # 变动后的余额快照（对账用）
    balance_after: Mapped[int] = mapped_column(Integer, nullable=False)
    # 关联引用：usage 指向 usage_logs.id，admin 记录操作者标识等
    ref: Mapped[str | None] = mapped_column(String(128), nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, default=lambda: datetime.now(UTC)
    )

    __table_args__ = (Index("idx_quota_tx_device_created", "device_id", "created_at"),)

    def __repr__(self):
        return (
            f"<QuotaTransaction(id={self.id}, device_id={self.device_id}, "
            f"delta={self.delta}, reason={self.reason}, balance_after={self.balance_after})>"
        )
