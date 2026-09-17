#!/bin/bash
# 通用 DMS 迁移脚本生成器：自动从源库导出 pre/post/verify SQL
# 依赖: psql, pg_dump (PostgreSQL 17 客户端)
#   sudo dnf install postgresql17 dos2unix
#   dos2unix generate_migration_scripts.sh && bash generate_migration_scripts.sh
set -e
 
# ==================== 配置区（按需修改）====================
SRC_HOST="10.0.1.20";  SRC_PORT="5432"; SRC_DB="appdb"; SRC_USER="postgres"; SRC_PASSWORD="<源库口令>"
TGT_HOST="mytarget.abcdefg.us-east-1.rds.amazonaws.com"; TGT_PORT="5432"; TGT_DB="appdb"; TGT_USER="postgres"; TGT_PASSWORD="<目标口令>"
OUTPUT_DIR="./migration_scripts_$(date +%Y%m%d_%H%M%S)"
EXCLUDE_TABLES="awsdms_ddl_audit"
# =========================================================
export PGPASSWORD="$SRC_PASSWORD"
mkdir -p "$OUTPUT_DIR"
 
# [0] 源库全表 REPLICA IDENTITY FULL
psql -h "$SRC_HOST" -U "$SRC_USER" -d "$SRC_DB" -t -A -c "
  SELECT 'ALTER TABLE '||table_schema||'.'||table_name||' REPLICA IDENTITY FULL;'
  FROM information_schema.tables
  WHERE table_schema NOT IN ('pg_catalog','information_schema') AND table_type='BASE TABLE';
" >> "$OUTPUT_DIR/00_set_source_db_identity_full.sql"
 
# [1] pre-data（表结构/序列/默认值/函数）
pg_dump -h "$SRC_HOST" -U "$SRC_USER" -d "$SRC_DB" --schema-only --section=pre-data \
  --no-owner --no-privileges --no-tablespaces --exclude-table="$EXCLUDE_TABLES" \
  -f "$OUTPUT_DIR/01_pre_data.sql"
 
# [2] 禁用触发器 + session_replication_role=replica
psql -h "$SRC_HOST" -U "$SRC_USER" -d "$SRC_DB" -t -A -c "
  SELECT DISTINCT 'ALTER TABLE '||event_object_schema||'.'||event_object_table||' DISABLE TRIGGER USER;'
  FROM information_schema.triggers
  WHERE trigger_schema NOT IN ('pg_catalog','information_schema')
    AND trigger_name NOT LIKE 'RI_ConstraintTrigger_%';
" >> "$OUTPUT_DIR/02_pre_dms_disable_triggers.sql"
echo "ALTER ROLE $TGT_USER SET session_replication_role='replica';" >> "$OUTPUT_DIR/02_pre_dms_disable_triggers.sql"
 
# [3] post-data（索引/外键/CHECK/UNIQUE/触发器）
pg_dump -h "$SRC_HOST" -U "$SRC_USER" -d "$SRC_DB" --schema-only --section=post-data \
  --no-owner --no-privileges --no-tablespaces --exclude-table="$EXCLUDE_TABLES" \
  -f "$OUTPUT_DIR/03_post_data.sql"
 
# [4] 序列重置 + 启用触发器 + ANALYZE  → 04_post_dms_restore.sql
# [5] 一致性校验 SQL                    → 05_verify.sql
# [6] DMS 任务配置参考 + RUN_ORDER.md（执行清单）
echo "✅ 生成完成，按 RUN_ORDER.md 执行"
