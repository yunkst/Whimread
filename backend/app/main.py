#!/usr/bin/env python3
"""
FastAPI main application.

This module contains the main FastAPI application with all API endpoints
for novel searching, chapter management, and caching functionality.
"""

import logging
from typing import Any

from fastapi import (
    Depends,
    FastAPI,
    File,
    Form,
    HTTPException,
    Request,
    UploadFile,
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from . import __version__
from .api.routes.admin import router as admin_router
from .api.routes.backup import router as backup_router
from .api.routes.devices import router as devices_router
from .api.routes.llm_proxy import router as llm_proxy_router
from .api.routes.logs import router as logs_router
from .api.routes.models import router as models_router
from .config import settings
from .constants import CACHE_ONE_DAY, CACHE_ONE_HOUR
from .database import get_db, init_db
from .deps.auth import verify_token
from .exceptions import (
    NovelBuilderException,
    handle_exception,
)
from .logging_config import setup_logging
from .schemas import (
    ModelsResponse,
    Text2ImgGenerateRequest,
    WorkflowInfo,
)
from .services.comfyui_client import create_comfyui_client
from .services.image_to_video_service import create_image_to_video_service
from .services.text2img_service import create_text2img_service

logger = logging.getLogger(__name__)

# 创建文生图和图生视频服务实例
text2img_service = create_text2img_service()
image_to_video_service = create_image_to_video_service()

app = FastAPI(
    title="Whimread Backend",
    version=__version__,
    description="FastAPI backend for novel AI image/video generation, backup, and model management",
)

# CORS配置 - 使用环境变量控制允许的源
allowed_origins = settings.cors_origins.split(",") if settings.cors_origins else []
if settings.debug and not allowed_origins:
    # 开发环境默认允许本地访问
    allowed_origins = ["http://localhost:3154", "http://127.0.0.1:3154"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],  # 限制HTTP方法
    allow_headers=["*"],
)

# 注册API路由
app.include_router(backup_router)
app.include_router(logs_router)
app.include_router(models_router)
app.include_router(devices_router)
app.include_router(llm_proxy_router)
app.include_router(admin_router)


# 应用启动事件
@app.on_event("startup")
async def startup_event() -> None:
    # 初始化日志系统
    logger = setup_logging()

    # 初始化数据库
    init_db()

    logger.info("Whimread Backend 启动完成")

    if settings.debug:
        logger.warning("调试模式已开启")

    if not settings.is_secure():
        logger.warning("当前配置不安全，请检查环境变量设置")


# 全局异常处理器
@app.exception_handler(NovelBuilderException)
async def novel_builder_exception_handler(request: Request, exc: NovelBuilderException):  # noqa: ARG001
    """处理自定义应用异常"""
    status_code = getattr(exc, "status_code", 500)
    logger.exception(f"应用异常: {exc.error_code} - {exc.message} (HTTP {status_code})")
    return JSONResponse(status_code=status_code, content=exc.to_dict())


@app.exception_handler(Exception)
async def general_exception_handler(
    request: Request,  # noqa: ARG001
    exc: Exception,
) -> JSONResponse:
    """处理未预期的异常"""
    novel_exc = handle_exception(exc, logger)
    status_code = getattr(novel_exc, "status_code", 500)
    logger.exception(f"未处理异常: {novel_exc.message} (HTTP {status_code})")
    return JSONResponse(status_code=status_code, content=novel_exc.to_dict())


def handle_service_exception(
    exc: Exception, logger: logging.Logger, operation_name: str
) -> HTTPException:
    """
    统一的服务层异常处理函数

    Args:
        exc: 捕获的异常
        logger: 日志记录器
        operation_name: 操作名称（用于日志）

    Returns:
        HTTPException: 格式化的HTTP异常
    """
    expected_types = (ValueError, SQLAlchemyError)
    if isinstance(exc, expected_types):
        logger.warning(f"{operation_name}参数错误: {exc}")
        return HTTPException(status_code=400, detail=str(exc))

    logger.error(f"{operation_name}失败: {exc}")
    return HTTPException(status_code=500, detail=f"{operation_name}失败")


@app.get("/health")
def health_check() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/security-check")
def security_check() -> dict[str, Any]:
    """安全配置检查端点，仅在开发环境可用"""
    if not settings.debug:
        raise HTTPException(status_code=404, detail="Not found")

    return {
        "is_secure": settings.is_secure(),
        "has_api_token": bool(settings.api_token),
        "has_custom_secret_key": settings.has_custom_secret_key,
        "is_debug_mode": settings.debug,
        "cors_origins": settings.cors_origins.split(",")
        if settings.cors_origins
        else [],
        "warnings": [
            "DEBUG模式已启用" if settings.debug else None,
            "未设置API_TOKEN" if not settings.api_token else None,
            "使用默认SECRET_KEY" if not settings.has_custom_secret_key else None,
            "CORS设置为允许所有源" if "*" in (settings.cors_origins or "") else None,
        ],
    }


# ================= 文生图 API =================


@app.post("/api/text2img/generate", dependencies=[Depends(verify_token)])
async def text2img_generate(
    request: Text2ImgGenerateRequest, db: Session = Depends(get_db)
):
    """
    提交文生图任务

    - **prompt**: 图片生成提示词
    - **model_name**: 模型名称（可选，不填则使用默认模型）
    - **negative_prompt**: 负向提示词（可选，仅工作流含对应占位符时生效）

    返回 task_id，可通过 GET /api/text2img/image/{task_id} 获取图片
    """
    try:
        task_id = await text2img_service.generate(
            request.prompt,
            request.model_name,
            db,
            negative_prompt=request.negative_prompt,
        )
        return {"task_id": task_id}
    except Exception as e:
        raise handle_service_exception(e, logger, "提交文生图任务")


@app.get(
    "/api/text2img/image/{task_id}",
    response_class=Response,
    responses={
        200: {
            "content": {
                "image/png": {"schema": {"type": "string", "format": "binary"}}
            },
            "description": "成功返回图片二进制数据",
        },
        202: {"description": "图片仍在生成中"},
        404: {"description": "任务不存在或生成失败"},
    },
    dependencies=[Depends(verify_token)],
)
async def text2img_get_image(task_id: str, db: Session = Depends(get_db)):
    """
    根据 task_id 获取文生图结果

    - **task_id**: 提交时返回的任务ID
    - 未完成返回 202 {"status": "pending"}
    - 完成返回 200 image/png 二进制
    - 失败或不存在返回 404
    """
    try:
        data, status_code = await text2img_service.get_image(task_id, db)
        if status_code == 200:
            return Response(
                content=data,
                media_type="image/png",
                headers={
                    "Cache-Control": f"public, max-age={CACHE_ONE_DAY}",
                    "X-Content-Type-Options": "nosniff",
                },
            )
        if status_code == 202:
            return JSONResponse(status_code=202, content={"status": "pending"})
        raise HTTPException(status_code=404, detail="图片不存在或生成失败")
    except HTTPException:
        raise
    except Exception as e:
        raise handle_service_exception(e, logger, "获取文生图结果")


@app.get("/text2img/health", dependencies=[Depends(verify_token)])
async def text2img_health_check():
    """检查ComfyUI服务健康状态"""
    try:
        # 复用 ComfyUIClient.health_check (httpx 异步 + 超时)
        client = create_comfyui_client()
        healthy = await client.health_check()

        if healthy:
            return {
                "status": "healthy",
                "message": "ComfyUI服务正常",
                "services": {"comfyui": True, "api_accessible": True},
            }
        return {
            "status": "unhealthy",
            "message": "ComfyUI服务响应异常",
            "services": {"comfyui": False, "api_accessible": False},
        }
    except Exception as e:
        logger.warning(f"ComfyUI 健康检查异常: {e}")
        return {
            "status": "unhealthy",
            "message": f"无法连接ComfyUI服务: {e!s}",
            "services": {"comfyui": False, "api_accessible": False},
        }


# ================= 图生视频 API =================


# 图生视频输入图片大小上限(50MB)。ComfyUI 通常足够,过大的图影响 I2V 性能。
MAX_I2V_IMAGE_BYTES = 50 * 1024 * 1024
# 允许的图生视频输入图片 MIME 类型(ComfyUI upload/image 端点要求 image/png,但放宽校验)
ALLOWED_I2V_IMAGE_MIME = {"image/png", "image/jpeg", "image/webp"}


@app.post("/api/image-to-video/generate", dependencies=[Depends(verify_token)])
async def image_to_video_generate(
    prompt: str = Form(..., description="视频生成提示词"),
    model_name: str | None = Form(None, description="模型名称（可选）"),
    image: UploadFile = File(..., description="输入图片"),
    db: Session = Depends(get_db),
):
    """
    提交图生视频任务

    - **prompt**: 视频生成提示词
    - **model_name**: 模型名称（可选，不填则使用默认模型）
    - **image**: 输入图片文件(<=50MB,支持 png/jpeg/webp)

    返回 task_id，可通过 GET /api/image-to-video/video/{task_id} 获取视频
    """
    try:
        # MIME 校验(优先用客户端声明,缺失时按扩展名兜底)
        mime = (image.content_type or "").lower()
        if mime and mime not in ALLOWED_I2V_IMAGE_MIME:
            raise HTTPException(
                status_code=400,
                detail=f"不支持的图片类型: {mime},仅支持 {sorted(ALLOWED_I2V_IMAGE_MIME)}",
            )

        image_bytes = await image.read()
        if not image_bytes:
            raise HTTPException(status_code=400, detail="图片文件为空")

        # 大小校验
        if len(image_bytes) > MAX_I2V_IMAGE_BYTES:
            raise HTTPException(
                status_code=413,
                detail=(
                    f"图片过大({len(image_bytes)} bytes),"
                    f"上限 {MAX_I2V_IMAGE_BYTES} bytes"
                ),
            )

        task_id = await image_to_video_service.generate(
            prompt, model_name, image_bytes, image.filename or "input_image.png", db
        )
        return {"task_id": task_id}
    except HTTPException:
        raise
    except Exception as e:
        raise handle_service_exception(e, logger, "提交图生视频任务")


@app.get(
    "/api/image-to-video/video/{task_id}",
    response_class=Response,
    responses={
        200: {
            "content": {
                "video/mp4": {"schema": {"type": "string", "format": "binary"}}
            },
            "description": "成功返回视频二进制数据",
        },
        202: {"description": "视频仍在生成中"},
        404: {"description": "任务不存在或生成失败"},
    },
    dependencies=[Depends(verify_token)],
)
async def image_to_video_get_video(task_id: str, db: Session = Depends(get_db)):
    """
    根据 task_id 获取图生视频结果

    - **task_id**: 提交时返回的任务ID
    - 未完成返回 202 {"status": "pending"}
    - 完成返回 200 video/mp4 二进制
    - 失败或不存在返回 404
    """
    try:
        data, status_code = await image_to_video_service.get_video(task_id, db)
        if status_code == 200:
            return Response(
                content=data,
                media_type="video/mp4",
                headers={
                    "Cache-Control": f"public, max-age={CACHE_ONE_HOUR}",
                    "X-Content-Type-Options": "nosniff",
                },
            )
        if status_code == 202:
            return JSONResponse(status_code=202, content={"status": "pending"})
        raise HTTPException(status_code=404, detail="视频不存在或生成失败")
    except HTTPException:
        raise
    except Exception as e:
        raise handle_service_exception(e, logger, "获取图生视频结果")


# ================= 模型管理 API =================


@app.get("/api/models", dependencies=[Depends(verify_token)])
async def get_models() -> ModelsResponse:
    """获取所有可用模型，按文生图和图生视频分类"""
    try:
        from app.workflow_config import WorkflowType, workflow_config_manager

        default_t2i_workflow = workflow_config_manager.get_default_workflow(
            WorkflowType.T2I
        )
        default_t2i_title = default_t2i_workflow.title

        t2i_response = workflow_config_manager.list_workflows(WorkflowType.T2I)
        text2img_models = [
            WorkflowInfo(
                title=workflow.title,
                description=workflow.description,
                path=workflow.path,
                width=workflow.width,
                height=workflow.height,
                is_default=(workflow.title == default_t2i_title),
                prompt_skill=workflow.prompt_skill,
            )
            for workflow in t2i_response.workflows
        ]

        i2v_response = workflow_config_manager.list_workflows(WorkflowType.I2V)
        img2video_models = [
            WorkflowInfo(
                title=workflow.title,
                description=workflow.description,
                path=workflow.path,
                width=None,
                height=None,
                is_default=False,
                prompt_skill=None,
            )
            for workflow in i2v_response.workflows
        ]

        return ModelsResponse(text2img=text2img_models, img2video=img2video_models)
    except Exception as e:
        raise handle_service_exception(e, logger, "获取模型列表")


# 便于 Docker 容器启动时的提示
@app.get("/")
def index():
    return {
        "message": "Whimread Backend",
        "version": __version__,
        "docs": "/docs",
        "token_required": True,
        "token_header": settings.token_header,
        "features": [
            "ComfyUI文生图",
            "ComfyUI图生视频",
            "数据库备份上传与下载",
            "ComfyUI 模型文件分块上传",
            "客户端日志上报",
        ],
        "endpoints": [
            "POST /api/text2img/generate - 提交文生图任务",
            "GET /api/text2img/image/{task_id} - 获取文生图结果",
            "GET /text2img/health - ComfyUI服务健康检查",
            "POST /api/image-to-video/generate - 提交图生视频任务",
            "GET /api/image-to-video/video/{task_id} - 获取图生视频结果",
            "GET /api/models - 获取可用模型列表",
            "POST /api/backup/upload - 上传数据库备份",
            "GET /api/backup/list - 列出已上传的备份",
            "GET /api/backup/download/{backup_id} - 下载备份文件",
            "POST /api/logs/upload - 上报客户端日志",
        ],
    }
