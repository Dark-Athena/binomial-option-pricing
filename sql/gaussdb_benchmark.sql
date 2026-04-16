-- ============================================================================
-- GaussDB 性能对比测试: binomial_amer_opt_v3 (V1 NUMERIC) vs binomial_amer_opt_v3_opt (V2 float8)
-- 在 gsql 或其他 GaussDB 客户端中执行
-- ============================================================================

\set ON_ERROR_STOP on
\pset format wrapped

-- 创建临时结果表
DROP TABLE IF EXISTS _bench_results;
CREATE TEMP TABLE _bench_results (
    case_label VARCHAR(20),
    n_steps    INTEGER,
    v1_ms      DOUBLE PRECISION,
    v2_ms      DOUBLE PRECISION,
    speedup    DOUBLE PRECISION,
    v1_price   DOUBLE PRECISION,
    v2_price   DOUBLE PRECISION
);

DO $$
DECLARE
    v_label VARCHAR(20);
    v_n     INTEGER;
    v_call  INTEGER;
    v_amer  INTEGER;
    v_start BIGINT;
    v_end   BIGINT;
    v_v1    DOUBLE PRECISION;
    v_v2    DOUBLE PRECISION;
    v_runs  INTEGER := 10;
    v_v1_total DOUBLE PRECISION;
    v_v2_total DOUBLE PRECISION;
BEGIN
    -- 测试用例
    FOR tc IN (
        SELECT 'AC_100'  AS lb, 100  AS nn, 1 AS ci, 1 AS ai UNION ALL
        SELECT 'AC_200',        200,       1,    1 UNION ALL
        SELECT 'AC_300',        300,       1,    1 UNION ALL
        SELECT 'AC_500',        500,       1,    1 UNION ALL
        SELECT 'AP_100',        100,       0,    1 UNION ALL
        SELECT 'AP_200',        200,       0,    1 UNION ALL
        SELECT 'AP_300',        300,       0,    1 UNION ALL
        SELECT 'AP_500',        500,       0,    1 UNION ALL
        SELECT 'EC_300',        300,       1,    0 UNION ALL
        SELECT 'EP_300',        300,       0,    0
    ) LOOP
        v_label := tc.lb;
        v_n     := tc.nn;
        v_call  := tc.ci;
        v_amer  := tc.ai;

        -- V1 (NUMERIC) 基准测试
        v_start := clock_timestamp()::BIGINT;
        FOR r IN 1..v_runs LOOP
            v_v1 := binomial_amer_opt_v3(100, 100, 1.0, 0.05, 0.2, v_n, v_call, v_amer);
        END LOOP;
        v_end := clock_timestamp()::BIGINT;
        v_v1_total := (v_end - v_start)::DOUBLE PRECISION / v_runs;

        -- V2 (float8 优化版) 基准测试
        v_start := clock_timestamp()::BIGINT;
        FOR r IN 1..v_runs LOOP
            v_v2 := binomial_amer_opt_v3_opt(100, 100, 1.0, 0.05, 0.2, v_n, v_call, v_amer);
        END LOOP;
        v_end := clock_timestamp()::BIGINT;
        v_v2_total := (v_end - v_start)::DOUBLE PRECISION / v_runs;

        -- 重新获取精确价格
        v_v1 := binomial_amer_opt_v3(100, 100, 1.0, 0.05, 0.2, v_n, v_call, v_amer);
        v_v2 := binomial_amer_opt_v3_opt(100, 100, 1.0, 0.05, 0.2, v_n, v_call, v_amer);

        INSERT INTO _bench_results VALUES (
            v_label, v_n,
            v_v1_total, v_v2_total,
            CASE WHEN v_v2_total > 0 THEN v_v1_total / v_v2_total ELSE 0 END,
            v_v1, v_v2
        );

        RAISE NOTICE '%  N=%  V1=%.1fms  V2=%.1fms  x=%.1f  V1=%.6f  V2=%.6f',
            v_label, v_n, v_v1_total, v_v2_total,
            CASE WHEN v_v2_total > 0 THEN v_v1_total / v_v2_total ELSE 0 END,
            v_v1, v_v2;
    END LOOP;
END;
$$;

-- 输出结果
SELECT
    case_label   AS "场景",
    n_steps      AS "N",
    ROUND(v1_ms, 1)  AS "V1 NUMERIC (ms)",
    ROUND(v2_ms, 1)  AS "V2 float8 (ms)",
    CASE
        WHEN speedup > 1.05 THEN ROUND(speedup, 2)::TEXT || 'x (V2 faster)'
        WHEN speedup < 0.95 THEN ROUND(speedup, 2)::TEXT || 'x (V1 faster)'
        ELSE ROUND(speedup, 2)::TEXT || 'x (similar)'
    END          AS "加速比",
    ROUND(v1_price, 6) AS "V1 价格",
    ROUND(v2_price, 6) AS "V2 价格"
FROM _bench_results
ORDER BY n_steps, case_label;

-- 汇总统计
SELECT
    '最大加速比' AS metric,
    CASE_LABEL || ' N=' || N_STEPS || ' (' || ROUND(speedup, 2) || 'x)' AS detail
FROM _bench_results WHERE speedup = (SELECT MAX(speedup) FROM _bench_results)
UNION ALL
SELECT
    '最小加速比',
    CASE_LABEL || ' N=' || N_STEPS || ' (' || ROUND(speedup, 2) || 'x)'
FROM _bench_results WHERE speedup = (SELECT MIN(speedup) FROM _bench_results);

-- 清理
DROP TABLE IF EXISTS _bench_results;
