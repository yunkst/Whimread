/// Riverpod Service Providers
///
/// 此文件统一导出所有服务层的 Provider。
///
/// **功能域**:
/// - [core_service_providers.dart] - 核心基础服务 (Logger, Preferences)
/// - [ai_service_providers.dart] - AI相关服务 (LlmConfig, CharacterCard, etc.)
/// - [network_service_providers.dart] - 网络相关服务 (Api, Preload, etc.)
/// - [database_service_providers.dart] - 数据库相关服务 (Chapter, Search, etc.)
/// - [cache_service_providers.dart] - 缓存相关服务 (RoleGallery, Avatar, etc.)
///
/// **使用示例**:
/// ```dart
/// // 导入所有服务 Providers
/// import 'package:novel_app/core/providers/service_providers.dart';
///
/// // 或者单独导入
/// import 'package:novel_app/core/providers/services/ai_service_providers.dart';
/// ```
///
/// **运行代码生成**:
/// ```bash
/// dart run build_runner build --delete-conflicting-outputs
/// ```
library;

// 核心服务
export 'services/core_service_providers.dart'
    show
        loggerServiceProvider,
        llmLoggerProvider,
        logReporterServiceProvider,
        preferencesServiceProvider,
        backupServiceProvider;

// AI服务
export 'services/ai_service_providers.dart'
    show
        llmConfigServiceProvider;

// 网络服务
export 'services/network_service_providers.dart'
    show
        apiServiceWrapperProvider,
        preloadServiceProvider;

// 数据库服务
export 'services/database_service_providers.dart'
    show
        chapterLoaderProvider,
        chapterActionHandlerProvider,
        chapterReorderControllerProvider,
        chapterSearchServiceProvider;

// 缓存服务
// 原 cache_service_providers.dart 已删除（ImageCacheManager 为孤儿组件）
