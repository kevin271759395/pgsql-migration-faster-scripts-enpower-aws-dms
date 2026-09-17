# 执行顺序
# 前提: 已设置源库 wal 参数；已创建目标库并配置自定义参数组；AWS DMS 迁移任务已创建
 
# Step 0: 设置源库 REPLICA IDENTITY FULL
psql -h 10.0.1.20 -p 5432 -U postgres -d appdb \
     -f 00_set_source_db_identity_full.sql
 
# Step 1: 清空目标库（如需，需对所有 schema 执行）
# 直接删除并重建目标数据库最快，或逐个删除 schema
 
# Step 2: 创建表结构（序列 / 默认值 / 函数）
psql -h mytarget.abcdefg.us-east-1.rds.amazonaws.com -p 5432 -U postgres -d appdb \
     -v ON_ERROR_STOP=1 -f 01_pre_data.sql
 
# Step 3: 禁用触发器
psql -h mytarget.abcdefg.us-east-1.rds.amazonaws.com -p 5432 -U postgres -d appdb \
     -f 02_pre_dms_disable_triggers.sql
 
# Step 3.5: 创建 DMS 过程表及授权
psql -h mytarget.abcdefg.us-east-1.rds.amazonaws.com -p 5432 -U postgres -d appdb \
     -f ../DMS-use-tables.sql
 
# Step 4: 启动 DMS 同构迁移任务（参考 dms_task_config_reference.json）
#   等待全量加载完成 → 开始增量(CDC) → 验证行数与增量结果
 
# Step 5: 创建索引、约束、触发器
psql -h mytarget.abcdefg.us-east-1.rds.amazonaws.com -p 5432 -U postgres -d appdb \
     -f 03_post_data.sql
 
# Step 6: 重置序列、启用触发器、ANALYZE
psql -h mytarget.abcdefg.us-east-1.rds.amazonaws.com -p 5432 -U postgres -d appdb \
     -f 04_post_dms_restore.sql
 
# Step 7: 一致性校验（源库与目标库分别执行并比对）
psql -h mytarget.abcdefg.us-east-1.rds.amazonaws.com -p 5432 -U postgres -d appdb \
     -f 05_verify.sql
 
# 后续: 切换应用连接、应用回归测试、停止 AWS DMS 任务
说明
上例中 10.0.1.20（源库）、mytarget.abcdefg.us-east-1.rds.amazonaws.com（目标 Amazon RDS 终端节点）、appdb 等均为占位示例，请替换为实际环境的连接信息。RUN_ORDER.md 由脚本按“配置区”的取值自动填充生成，无需手工拼接命令。
