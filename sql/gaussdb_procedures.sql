-- ============================================================================
-- GaussDB PL/pgSQL: 二叉树期权定价函数
-- V1 (原始版 NUMERIC) + V2 (优化版 float8)
-- CRR (Cox-Ross-Rubinstein) Model
-- ============================================================================

-- ----------------------------------------------------------------------------
-- V1: 原始版本 (NUMERIC 全量)
-- 特点: NUMERIC 参数+变量, POWER() 逐节点计算, IF/ELSE 分支
-- 注意: N 过大时 POWER 结果可能超出 NUMERIC 范围 (溢出)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION binomial_amer_opt_v3 (
    p_s0    NUMERIC,
    p_k     NUMERIC,
    p_t     NUMERIC,
    p_r     NUMERIC,
    p_sigma NUMERIC,
    p_n     INTEGER,
    p_is_call INTEGER,      -- 1=看涨, 0=看跌
    p_is_amer INTEGER       -- 1=美式, 0=欧式
) RETURNS NUMERIC AS $$
DECLARE
    v_dt        NUMERIC;
    v_u         NUMERIC;
    v_d         NUMERIC;
    v_p         NUMERIC;
    v_disc      NUMERIC;
    v_intrinsic NUMERIC;
    v_cont      NUMERIC;
    v_stk       NUMERIC;
    v_opt       NUMERIC[];
    i           INTEGER;
    j           INTEGER;
BEGIN
    v_dt   := p_t / p_n;
    v_u    := EXP(p_sigma * SQRT(v_dt));
    v_d    := 1.0 / v_u;
    v_p    := (EXP(p_r * v_dt) - v_d) / (v_u - v_d);
    v_disc := EXP(-p_r * v_dt);
    v_opt  := array_fill(0, ARRAY[p_n + 2]);

    FOR j IN 0 .. p_n LOOP
        v_stk := p_s0 * POWER(v_u, p_n - j) * POWER(v_d, j);
        IF p_is_call = 1 THEN v_opt[j+1] := GREATEST(v_stk - p_k, 0);
        ELSE v_opt[j+1] := GREATEST(p_k - v_stk, 0); END IF;
    END LOOP;

    i := p_n - 1;
    WHILE i >= 0 LOOP
        j := 0;
        WHILE j <= i LOOP
            v_cont := v_disc * (v_p * v_opt[j+1] + (1 - v_p) * v_opt[j+2]);
            IF p_is_amer = 1 THEN
                v_stk := p_s0 * POWER(v_u, i - j) * POWER(v_d, j);
                IF p_is_call = 1 THEN v_intrinsic := GREATEST(v_stk - p_k, 0);
                ELSE v_intrinsic := GREATEST(p_k - v_stk, 0); END IF;
                v_opt[j+1] := GREATEST(v_intrinsic, v_cont);
            ELSE
                v_opt[j+1] := v_cont;
            END IF;
            j := j + 1;
        END LOOP;
        i := i - 1;
    END LOOP;

    RETURN v_opt[1];
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------------------------------------
-- V2: 优化版本 (float8 全量 + 算法优化)
-- 特点:
--   1. float8 (DOUBLE PRECISION) 替代 NUMERIC
--   2. intr 递推替代 POWER() 调用 (消除 99%+ 的 POWER 调用)
--   3. SIGN 统一看涨/看跌, 消除 IF/ELSE 分支
--   4. 常量预计算 (1-p, dd, intrStep)
--   5. 不受 NUMERIC 溢出限制, 支持更大的 N
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION binomial_amer_opt_v3_opt (
    p_s0    float8,
    p_k     float8,
    p_t     float8,
    p_r     float8,
    p_sigma float8,
    p_n     INTEGER,
    p_is_call INTEGER,      -- 1=看涨, 0=看跌
    p_is_amer INTEGER       -- 1=美式, 0=欧式
) RETURNS float8 AS $$
DECLARE
    v_dt        float8;
    v_u         float8;
    v_d         float8;
    v_p         float8;
    v_disc      float8;
    v_dd        float8;
    v_1mp       float8;
    v_sign      float8;
    v_signK     float8;
    v_intrStep  float8;
    v_base      float8;
    v_intr      float8;
    v_cont      float8;
    v_opt       float8[];
    i           INTEGER;
    j           INTEGER;
BEGIN
    v_dt   := p_t / p_n;
    v_u    := exp(p_sigma * sqrt(v_dt));
    v_d    := 1.0 / v_u;
    v_p    := (exp(p_r * v_dt) - v_d) / (v_u - v_d);
    v_1mp  := 1.0 - v_p;
    v_disc := exp(-p_r * v_dt);
    v_dd   := v_d * v_d;

    IF p_is_call = 1 THEN v_sign := 1.0; ELSE v_sign := -1.0; END IF;
    v_signK    := v_sign * p_k;
    v_intrStep := v_signK * (v_dd - 1.0);

    v_opt := array_fill(0.0, ARRAY[p_n + 2]);
    FOR i IN 1 .. p_n + 1 LOOP
        v_opt[i] := greatest(0.0, v_sign * (p_s0 * power(v_u, p_n) * power(v_dd, i - 1) - p_k));
    END LOOP;

    v_base := p_s0 * power(v_u, p_n) * v_d;
    FOR i IN REVERSE p_n .. 1 LOOP
        v_intr := v_sign * v_base - v_signK;
        FOR j IN 1 .. i LOOP
            v_cont := v_disc * (v_p * v_opt[j] + v_1mp * v_opt[j + 1]);
            IF p_is_amer = 1 THEN v_opt[j] := greatest(v_cont, v_intr);
            ELSE v_opt[j] := v_cont; END IF;
            v_intr := v_intr * v_dd + v_intrStep;
        END LOOP;
        v_base := v_base * v_d;
    END LOOP;

    RETURN v_opt[1];
END;
$$ LANGUAGE plpgsql;