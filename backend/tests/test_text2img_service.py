#!/usr/bin/env python3
"""
文生图与图生视频服务单元测试.

覆盖 Text2ImgService 和 ImageToVideoService 的核心状态机:
- 提交任务落库
- pending 查 ComfyUI history 的三态(空=202 / completed=200 / error=404 / 其它=202)
- completed 直接拉取二进制
- failed 返 404
- task_id 不存在 返 404
- filename 提取与视频文件获取的拆分逻辑

策略: 用 SQLite 内存数据库作为测试 session, monkeypatch ComfyUIClient 的实例化工厂,
不依赖真实 ComfyUI 服务。
"""

import asyncio
from datetime import datetime
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.config import settings
from app.models.text2img import ImageToVideoTask, Text2ImgTask
from app.services.image_to_video_service import ImageToVideoService
from app.services.text2img_service import Text2ImgService


# ==================== Fixtures ====================


@pytest.fixture
def engine():
    """创建 SQLite 内存数据库引擎,只建本测试需要的两张任务表.

    不用 Base.metadata.create_all(),否则会因其他表(如 chapter_list_cache)
    使用 PostgreSQL 专有的 JSONB 类型而在 SQLite 上编译失败。
    """
    eng = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Text2ImgTask.__table__.create(bind=eng, checkfirst=True)
    ImageToVideoTask.__table__.create(bind=eng, checkfirst=True)
    yield eng
    eng.dispose()


@pytest.fixture
def db(engine):
    """创建数据库 session,每个测试独立."""
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


@pytest.fixture
def mock_comfyui_client():
    """Mock 出 ComfyUIClient 实例的工厂."""
    return AsyncMock()


@pytest.fixture
def patched_t2i_service(mock_comfyui_client):
    """构造 Text2ImgService 并注入 mock 客户端,跳过真实 create_comfyui_client 调用."""
    with patch(
        "app.services.text2img_service.create_comfyui_client",
        return_value=mock_comfyui_client,
    ):
        service = Text2ImgService()
        yield service


@pytest.fixture
def patched_i2v_service(mock_comfyui_client):
    """构造 ImageToVideoService 并注入 mock 客户端."""
    with patch(
        "app.services.image_to_video_service.create_comfyui_client",
        return_value=mock_comfyui_client,
    ):
        service = ImageToVideoService()
        yield service


# ==================== Text2ImgService 测试 ====================


class TestText2ImgGenerate:
    """提交文生图任务."""

    def test_returns_prompt_id(self, patched_t2i_service, mock_comfyui_client, db):
        """ComfyUI 返回 prompt_id,服务返回该 id 并落库."""
        mock_comfyui_client.generate_image.return_value = "abc123"

        result = asyncio.run(
            patched_t2i_service.generate("a cat", "动漫风17.5", db)
        )

        assert result == "abc123"
        # 未传 negative_prompt 时,ComfyUI 客户端收到 (prompt, None)
        mock_comfyui_client.generate_image.assert_called_once_with("a cat", None)

        task = db.query(Text2ImgTask).filter_by(prompt_id="abc123").first()
        assert task is not None
        assert task.prompt == "a cat"
        assert task.model_name == "动漫风17.5"
        assert task.status == "pending"
        assert task.filename is None

    def test_passes_negative_prompt(self, patched_t2i_service, mock_comfyui_client, db):
        """negative_prompt 透传给 ComfyUI 客户端并落库(1.9.21)."""
        mock_comfyui_client.generate_image.return_value = "neg456"

        result = asyncio.run(
            patched_t2i_service.generate(
                "a cat", "动漫风17.5", db, negative_prompt="blurry, lowres"
            )
        )

        assert result == "neg456"
        mock_comfyui_client.generate_image.assert_called_once_with(
            "a cat", "blurry, lowres"
        )

        task = db.query(Text2ImgTask).filter_by(prompt_id="neg456").first()
        assert task is not None
        assert task.negative_prompt == "blurry, lowres"

    def test_comfyui_submit_failure_raises(self, patched_t2i_service, mock_comfyui_client, db):
        """ComfyUI 提交失败(None)时抛 RuntimeError,不落库."""
        mock_comfyui_client.generate_image.return_value = None

        with pytest.raises(RuntimeError, match="ComfyUI 提交失败"):
            asyncio.run(
                patched_t2i_service.generate("a cat", "动漫风17.5", db)
            )

        assert db.query(Text2ImgTask).count() == 0


class TestText2ImgGetImage:
    """查询文生图状态."""

    def test_task_not_found_returns_404(self, patched_t2i_service, db):
        """task_id 不在 DB 中 → 404."""
        data, status = asyncio.run(
            patched_t2i_service.get_image("nonexistent_id", db)
        )
        assert data is None
        assert status == 404

    def test_pending_and_history_empty_returns_202(self, patched_t2i_service, mock_comfyui_client, db):
        """pending 状态且 ComfyUI history 为空(还在排队) → 202."""
        db.add(Text2ImgTask(prompt_id="p1", prompt="x", model_name="动漫风17.5", status="pending"))
        db.commit()
        mock_comfyui_client.check_task_status.return_value = {}

        data, status = asyncio.run(patched_t2i_service.get_image("p1", db))

        assert data is None
        assert status == 202

    def test_pending_and_history_completed_pulls_and_backfills(
        self, patched_t2i_service, mock_comfyui_client, db
    ):
        """pending 且 ComfyUI 已完成 → 提取 filename、拉二进制、回填 DB、返 200."""
        db.add(Text2ImgTask(prompt_id="p2", prompt="x", model_name="动漫风17.5", status="pending"))
        db.commit()

        # mock ComfyUI: history 报完成 + outputs 含图片
        mock_comfyui_client.check_task_status.return_value = {
            "status": {"status_str": "completed"},
            "outputs": {
                "9": {
                    "images": [
                        {"filename": "ComfyUI_00001_.png", "type": "output"}
                    ]
                }
            },
        }
        # mock _fetch_media 直接返字节
        with patch.object(
            patched_t2i_service, "_fetch_media", return_value=b"PNG-BYTES"
        ):
            data, status = asyncio.run(patched_t2i_service.get_image("p2", db))

        assert status == 200
        assert data == b"PNG-BYTES"

        task = db.query(Text2ImgTask).filter_by(prompt_id="p2").first()
        assert task.status == "completed"
        assert task.filename == "ComfyUI_00001_.png"
        assert task.completed_at is not None

    def test_pending_and_history_completed_but_no_output_marks_failed(
        self, patched_t2i_service, mock_comfyui_client, db
    ):
        """completed 但 outputs 无图片 → 标记 failed + 404."""
        db.add(Text2ImgTask(prompt_id="p3", prompt="x", model_name="动漫风17.5", status="pending"))
        db.commit()

        mock_comfyui_client.check_task_status.return_value = {
            "status": {"status_str": "completed"},
            "outputs": {},
        }

        data, status = asyncio.run(patched_t2i_service.get_image("p3", db))

        assert status == 404
        task = db.query(Text2ImgTask).filter_by(prompt_id="p3").first()
        assert task.status == "failed"

    def test_pending_and_history_error_marks_failed(
        self, patched_t2i_service, mock_comfyui_client, db
    ):
        """ComfyUI 报 error → 标记 failed + 404."""
        db.add(Text2ImgTask(prompt_id="p4", prompt="x", model_name="动漫风17.5", status="pending"))
        db.commit()

        mock_comfyui_client.check_task_status.return_value = {
            "status": {"status_str": "error", "messages": ["nope"]},
            "outputs": {},
        }

        data, status = asyncio.run(patched_t2i_service.get_image("p4", db))

        assert status == 404
        task = db.query(Text2ImgTask).filter_by(prompt_id="p4").first()
        assert task.status == "failed"
        assert "nope" in (task.error_message or "")

    def test_pending_and_history_still_running_returns_202(
        self, patched_t2i_service, mock_comfyui_client, db
    ):
        """history 返回但 status_str 既非 completed 也非 error → 仍在跑 → 202."""
        db.add(Text2ImgTask(prompt_id="p5", prompt="x", model_name="动漫风17.5", status="pending"))
        db.commit()

        mock_comfyui_client.check_task_status.return_value = {
            "status": {"status_str": "in_progress"},
            "outputs": {},
        }

        data, status = asyncio.run(patched_t2i_service.get_image("p5", db))

        assert status == 202

    def test_completed_status_serves_from_db(
        self, patched_t2i_service, db
    ):
        """DB 已有 completed + filename → 直接拉,不再查 history."""
        db.add(
            Text2ImgTask(
                prompt_id="p6",
                prompt="x",
                model_name="动漫风17.5",
                status="completed",
                filename="cached.png",
                completed_at=datetime.now(),
            )
        )
        db.commit()

        with patch.object(
            patched_t2i_service, "_fetch_media", return_value=b"CACHED"
        ):
            data, status = asyncio.run(patched_t2i_service.get_image("p6", db))

        assert status == 200
        assert data == b"CACHED"

    def test_failed_status_returns_404(self, patched_t2i_service, db):
        """DB 已是 failed → 404."""
        db.add(
            Text2ImgTask(
                prompt_id="p7",
                prompt="x",
                model_name="动漫风17.5",
                status="failed",
                error_message="oops",
            )
        )
        db.commit()

        data, status = asyncio.run(patched_t2i_service.get_image("p7", db))

        assert status == 404


class TestExtractImageFilename:
    """_extract_image_filename 的解析逻辑."""

    def test_picks_first_non_temp_image(self, patched_t2i_service):
        """遍历所有节点,跳过 type==temp,取第一个 filename."""
        outputs = {
            "10": {
                "images": [
                    {"filename": "temp_x.png", "type": "temp"},
                    {"filename": "good.png", "type": "output"},
                ]
            }
        }
        assert patched_t2i_service._extract_image_filename(outputs) == "good.png"

    def test_skips_nodes_without_images(self, patched_t2i_service):
        """无 images 字段的节点不影响结果."""
        outputs = {
            "1": {"text": "hello"},
            "2": {"images": [{"filename": "found.png", "type": "output"}]},
        }
        assert patched_t2i_service._extract_image_filename(outputs) == "found.png"

    def test_returns_none_when_empty(self, patched_t2i_service):
        """完全无图片输出 → None."""
        assert patched_t2i_service._extract_image_filename({}) is None
        assert patched_t2i_service._extract_image_filename(
            {"a": {"images": [{"filename": "tmp.png", "type": "temp"}]}}
        ) is None


# ==================== ImageToVideoService 测试 ====================


class TestImageToVideoGenerate:
    """提交图生视频任务."""

    def test_returns_prompt_id(self, patched_i2v_service, mock_comfyui_client, db):
        """ComfyUI 返回 prompt_id → 落库 + 返回."""
        mock_comfyui_client.generate_video.return_value = "vid_abc"

        result = asyncio.run(
            patched_i2v_service.generate(
                "cinematic motion", "视频生成", b"\x89PNG", "input.png", db
            )
        )

        assert result == "vid_abc"
        mock_comfyui_client.generate_video.assert_called_once_with(
            "cinematic motion", b"\x89PNG", "input.png"
        )

        task = db.query(ImageToVideoTask).filter_by(prompt_id="vid_abc").first()
        assert task is not None
        assert task.prompt == "cinematic motion"
        assert task.model_name == "视频生成"
        assert task.image_filename == "input.png"
        assert task.status == "pending"

    def test_comfyui_submit_failure_raises(self, patched_i2v_service, mock_comfyui_client, db):
        """ComfyUI 提交失败 → RuntimeError,不落库."""
        mock_comfyui_client.generate_video.return_value = None

        with pytest.raises(RuntimeError, match="ComfyUI 提交失败"):
            asyncio.run(
                patched_i2v_service.generate(
                    "x", "视频生成", b"\x89PNG", "input.png", db
                )
            )
        assert db.query(ImageToVideoTask).count() == 0


class TestImageToVideoGetVideo:
    """查询图生视频状态."""

    def test_task_not_found_returns_404(self, patched_i2v_service, db):
        data, status = asyncio.run(
            patched_i2v_service.get_video("nonexistent", db)
        )
        assert data is None
        assert status == 404

    def test_pending_and_history_empty_returns_202(
        self, patched_i2v_service, mock_comfyui_client, db
    ):
        db.add(
            ImageToVideoTask(
                prompt_id="v1",
                prompt="x",
                model_name="视频生成",
                status="pending",
            )
        )
        db.commit()
        mock_comfyui_client.check_task_status.return_value = {}

        data, status = asyncio.run(patched_i2v_service.get_video("v1", db))
        assert status == 202

    def test_pending_and_history_completed_pulls_and_backfills(
        self, patched_i2v_service, mock_comfyui_client, db
    ):
        db.add(
            ImageToVideoTask(
                prompt_id="v2",
                prompt="x",
                model_name="视频生成",
                status="pending",
            )
        )
        db.commit()

        mock_comfyui_client.check_task_status.return_value = {
            "status": {"status_str": "completed"},
            "outputs": {
                "9": {
                    "_meta": {"class_type": "VHS_VideoCombine"},
                    "gifs": [{"filename": "out.mp4", "type": "output"}],
                }
            },
        }
        with patch.object(
            patched_i2v_service, "_fetch_video", return_value=b"MP4-BYTES"
        ):
            data, status = asyncio.run(patched_i2v_service.get_video("v2", db))

        assert status == 200
        assert data == b"MP4-BYTES"

        task = db.query(ImageToVideoTask).filter_by(prompt_id="v2").first()
        assert task.status == "completed"
        assert task.video_filename == "out.mp4"
        assert task.completed_at is not None

    def test_pending_and_history_completed_but_no_video_marks_failed(
        self, patched_i2v_service, mock_comfyui_client, db
    ):
        db.add(
            ImageToVideoTask(
                prompt_id="v3",
                prompt="x",
                model_name="视频生成",
                status="pending",
            )
        )
        db.commit()

        mock_comfyui_client.check_task_status.return_value = {
            "status": {"status_str": "completed"},
            "outputs": {},
        }

        data, status = asyncio.run(patched_i2v_service.get_video("v3", db))
        assert status == 404

        task = db.query(ImageToVideoTask).filter_by(prompt_id="v3").first()
        assert task.status == "failed"

    def test_pending_and_history_error_marks_failed(
        self, patched_i2v_service, mock_comfyui_client, db
    ):
        db.add(
            ImageToVideoTask(
                prompt_id="v4",
                prompt="x",
                model_name="视频生成",
                status="pending",
            )
        )
        db.commit()

        mock_comfyui_client.check_task_status.return_value = {
            "status": {"status_str": "error", "messages": ["oom"]},
            "outputs": {},
        }

        data, status = asyncio.run(patched_i2v_service.get_video("v4", db))
        assert status == 404

        task = db.query(ImageToVideoTask).filter_by(prompt_id="v4").first()
        assert task.status == "failed"
        assert "oom" in (task.error_message or "")

    def test_completed_status_serves_from_db(self, patched_i2v_service, db):
        db.add(
            ImageToVideoTask(
                prompt_id="v5",
                prompt="x",
                model_name="视频生成",
                status="completed",
                video_filename="cached.mp4",
                completed_at=datetime.now(),
            )
        )
        db.commit()

        with patch.object(
            patched_i2v_service, "_fetch_video", return_value=b"CACHED-MP4"
        ):
            data, status = asyncio.run(patched_i2v_service.get_video("v5", db))

        assert status == 200
        assert data == b"CACHED-MP4"

    def test_failed_status_returns_404(self, patched_i2v_service, db):
        db.add(
            ImageToVideoTask(
                prompt_id="v6",
                prompt="x",
                model_name="视频生成",
                status="failed",
                error_message="bad prompt",
            )
        )
        db.commit()

        data, status = asyncio.run(patched_i2v_service.get_video("v6", db))
        assert status == 404


class TestExtractVideoFilename:
    """_extract_video_filename 的两段策略解析."""

    def test_prefers_videocombine_node(self, patched_i2v_service):
        """第一优先级: _meta.class_type 含 VideoCombine 的节点."""
        outputs = {
            "1": {"images": [{"filename": "noise.png", "type": "output"}]},
            "9": {
                "_meta": {"class_type": "VHS_VideoCombine"},
                "gifs": [{"filename": "main.mp4", "type": "output", "subfolder": "video"}],
            },
        }
        assert patched_i2v_service._extract_video_filename(outputs) == "video/main.mp4"

    def test_falls_back_to_extension_match(self, patched_i2v_service):
        """无 VideoCombine 节点时,按扩展名兜底."""
        outputs = {
            "5": {"images": [{"filename": "thing.mp4", "type": "output"}]},
        }
        assert patched_i2v_service._extract_video_filename(outputs) == "thing.mp4"

    def test_skips_temp_files(self, patched_i2v_service):
        """type==temp 的视频文件应跳过."""
        outputs = {
            "5": {"images": [
                {"filename": "tmp.mp4", "type": "temp"},
                {"filename": "real.mp4", "type": "output"},
            ]},
        }
        assert patched_i2v_service._extract_video_filename(outputs) == "real.mp4"

    def test_returns_none_when_no_video(self, patched_i2v_service):
        outputs = {
            "1": {"images": [{"filename": "pic.png", "type": "output"}]},
        }
        assert patched_i2v_service._extract_video_filename(outputs) is None

    def test_no_subfolder_returns_bare_filename(self, patched_i2v_service):
        outputs = {
            "5": {"images": [{"filename": "flat.mp4", "type": "output", "subfolder": ""}]},
        }
        assert patched_i2v_service._extract_video_filename(outputs) == "flat.mp4"


class TestFetchVideoUrlSplit:
    """_fetch_video 的 subfolder 拆分逻辑."""

    @staticmethod
    def _mock_httpx_client(response: MagicMock) -> MagicMock:
        """构造 httpx.AsyncClient 的 async context manager mock."""
        mock_client = MagicMock()
        mock_client.get = AsyncMock(return_value=response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)
        return mock_client

    def test_plain_filename(self, patched_i2v_service):
        """无 '/' 时不加 subfolder 参数."""
        mock_client = self._mock_httpx_client(
            MagicMock(status_code=200, content=b"V")
        )
        with patch(
            "app.services.image_to_video_service.httpx.AsyncClient",
            return_value=mock_client,
        ):
            result = asyncio.run(patched_i2v_service._fetch_video("plain.mp4"))

        assert result == b"V"
        called_url = mock_client.get.call_args[0][0]
        assert "filename=plain.mp4" in called_url
        assert "subfolder=" not in called_url

    def test_subfolder_filename(self, patched_i2v_service):
        """含 '/' 时拆分,最后一段是 filename,前面是 subfolder."""
        mock_client = self._mock_httpx_client(
            MagicMock(status_code=200, content=b"V")
        )
        with patch(
            "app.services.image_to_video_service.httpx.AsyncClient",
            return_value=mock_client,
        ):
            result = asyncio.run(
                patched_i2v_service._fetch_video("video/nested.mp4")
            )

        assert result == b"V"
        called_url = mock_client.get.call_args[0][0]
        assert "filename=nested.mp4" in called_url
        assert "subfolder=video" in called_url