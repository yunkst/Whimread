-- 授权:让 service_role 角色能 CRUD 业务表
-- 背景:CloudBase PG 模式新建表后,默认只有 owner 有权限;
-- 必须显式 GRANT 给 PG 角色才能通过 REST API 访问。
--
-- 角色映射:[Skill: auth-and-rls.md]
--   Publishable Key -> anon
--   用户 access_token -> authenticated
--   API Key / 云函数内部 -> service_role
--
-- Whimread 用法:云函数调 PG REST API 走 service_role。

-- devices / device_jwts 用字符串 PK,无 sequence
GRANT ALL ON public.devices TO service_role;
GRANT ALL ON public.device_jwts TO service_role;

-- quota_changes / app_releases 用 BIGSERIAL,有 sequence
GRANT ALL ON public.quota_changes TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.quota_changes_id_seq TO service_role;

GRANT ALL ON public.app_releases TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.app_releases_id_seq TO service_role;

-- 关掉 RLS:service_role 已经足够,业务表不做客户端 RLS
ALTER TABLE public.devices DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_jwts DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.quota_changes DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_releases DISABLE ROW LEVEL SECURITY;
