include_directories(${CMAKE_CURRENT_SOURCE_DIR})

# 本仓只 vendor 了 CLI（模型管理页的本地推理验证/调试用）；
# server 示例依赖被裁剪的 frontend submodule，不随仓发布。
add_subdirectory(cli)
