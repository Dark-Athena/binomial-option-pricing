-- ============================================================================
-- Oracle PL/SQL: 二叉树期权定价存储过程
-- V1 (原始版) + V2 (优化版)
-- CRR (Cox-Ross-Rubinstein) Model
-- ============================================================================

-- ----------------------------------------------------------------------------
-- V1: 原始版本
-- 特点: NUMBER 类型, POWER() 逐节点计算, IF/ELSE 分支
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE binomial_option_price (
    p_s0        IN NUMBER,
    p_k         IN NUMBER,
    p_t         IN NUMBER,
    p_r         IN NUMBER,
    p_sigma     IN NUMBER,
    p_n         IN NUMBER,
    p_is_call   IN NUMBER,     -- 1=看涨, 0=看跌
    p_is_amer   IN NUMBER,     -- 1=美式, 0=欧式
    p_result    OUT NUMBER
) AS
    v_dt        NUMBER;
    v_u         NUMBER;
    v_d         NUMBER;
    v_p         NUMBER;
    v_disc      NUMBER;
    v_cont      NUMBER;
    v_intrinsic NUMBER;
    v_stk       NUMBER;
    TYPE arr_t IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    v_opt       arr_t;
    i           PLS_INTEGER;
    j           PLS_INTEGER;
BEGIN
    v_dt   := p_t / p_n;
    v_u    := EXP(p_sigma * SQRT(v_dt));
    v_d    := 1.0 / v_u;
    v_p    := (EXP(p_r * v_dt) - v_d) / (v_u - v_d);
    v_disc := EXP(-p_r * v_dt);

    -- 叶子节点期权价值
    FOR j IN 0 .. p_n LOOP
        v_stk := p_s0 * POWER(v_u, p_n - j) * POWER(v_d, j);
        IF p_is_call = 1 THEN
            v_opt(j) := GREATEST(v_stk - p_k, 0);
        ELSE
            v_opt(j) := GREATEST(p_k - v_stk, 0);
        END IF;
    END LOOP;

    -- 倒推
    FOR i IN REVERSE 1 .. p_n LOOP
        FOR j IN 0 .. i LOOP
            v_cont := v_disc * (v_p * v_opt(j + 1) + (1 - v_p) * v_opt(j + 2));
            IF p_is_amer = 1 THEN
                v_stk := p_s0 * POWER(v_u, i - j) * POWER(v_d, j);
                IF p_is_call = 1 THEN
                    v_intrinsic := GREATEST(v_stk - p_k, 0);
                ELSE
                    v_intrinsic := GREATEST(p_k - v_stk, 0);
                END IF;
                v_opt(j) := GREATEST(v_intrinsic, v_cont);
            ELSE
                v_opt(j) := v_cont;
            END IF;
        END LOOP;
    END LOOP;

    p_result := v_opt(0);
END;
/

-- ----------------------------------------------------------------------------
-- V2: 优化版本
-- 特点:
--   1. BINARY_DOUBLE 替代 NUMBER (硬件浮点加速)
--   2. intr 递推替代 POWER() 调用 (消除 99%+ 的 POWER 调用)
--   3. SIGN 统一看涨/看跌, 消除 IF/ELSE 分支
--   4. 常量预计算 (1-p, dd, intrStep)
--   5. 支持 Delta 输出 + 异常处理
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE binomial_option_price_v2 (
    p_s0        IN NUMBER,
    p_k         IN NUMBER,
    p_t         IN NUMBER,
    p_r         IN NUMBER,
    p_sigma     IN NUMBER,
    p_n         IN NUMBER,
    p_is_call   IN NUMBER,      -- 1=看涨, 0=看跌
    p_is_amer   IN NUMBER,      -- 1=美式, 0=欧式
    p_result    OUT NUMBER,      -- 期权价格
    p_delta     OUT NUMBER,      -- Delta 值
    p_retcode   OUT NUMBER,      -- 返回码 (0=成功, -1=失败)
    p_retmsg    OUT VARCHAR2     -- 错误信息
) AS
    v_dt        BINARY_DOUBLE;
    v_u         BINARY_DOUBLE;
    v_d         BINARY_DOUBLE;
    v_p         BINARY_DOUBLE;
    v_disc      BINARY_DOUBLE;
    v_dd        BINARY_DOUBLE;
    v_1mp       BINARY_DOUBLE;
    v_sign      BINARY_DOUBLE;
    v_signK     BINARY_DOUBLE;
    v_intrStep  BINARY_DOUBLE;
    v_base      BINARY_DOUBLE;
    v_intr      BINARY_DOUBLE;
    v_cont      BINARY_DOUBLE;
    TYPE TB_BD  IS TABLE OF BINARY_DOUBLE;
    v_opt       TB_BD;
    i           PLS_INTEGER;
    j           PLS_INTEGER;
BEGIN
    p_retcode := 0;

    v_dt   := p_t / p_n;
    v_u    := EXP(p_sigma * SQRT(v_dt));
    v_d    := 1.0 / v_u;
    v_p    := (EXP(p_r * v_dt) - v_d) / (v_u - v_d);
    v_1mp  := 1.0 - v_p;
    v_disc := EXP(-p_r * v_dt);
    v_dd   := v_d * v_d;

    IF p_is_call = 1 THEN v_sign := 1.0; ELSE v_sign := -1.0; END IF;
    v_signK    := v_sign * p_k;
    v_intrStep := v_signK * (v_dd - 1.0);

    v_opt := TB_BD();
    v_opt.EXTEND(p_n + 1);
    FOR i IN 1 .. p_n + 1 LOOP
        v_opt(i) := GREATEST(0.0, v_sign * (p_s0 * POWER(v_u, p_n) * POWER(v_dd, i - 1) - p_k));
    END LOOP;

    v_base := p_s0 * POWER(v_u, p_n) * v_d;
    FOR i IN REVERSE 1 .. p_n LOOP
        v_intr := v_sign * v_base - v_signK;
        FOR j IN 1 .. i LOOP
            v_cont := v_disc * (v_p * v_opt(j) + v_1mp * v_opt(j + 1));
            IF p_is_amer = 1 THEN
                v_opt(j) := GREATEST(v_cont, v_intr);
            ELSE
                v_opt(j) := v_cont;
            END IF;
            v_intr := v_intr * v_dd + v_intrStep;
        END LOOP;

        -- Delta: 当 i=2 时，利用倒数第二层计算 (opt[2]-opt[1]) / (S*u*d - S)
        IF i = 2 THEN
            p_delta := (v_opt(2) - v_opt(1)) / (v_base * v_dd - v_base);
        END IF;

        v_base := v_base * v_d;
    END LOOP;

    p_result := v_opt(1);
EXCEPTION
    WHEN OTHERS THEN
        p_retcode := -1;
        p_retmsg  := 'exec failed: ' || SQLERRM;
        RAISE;
END;
/