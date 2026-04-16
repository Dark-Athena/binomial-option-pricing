-- ============================================================================
-- Oracle 性能对比测试: binomial_option_price (V1) vs binomial_option_price_v2 (V2)
-- 在 SQL*Plus 或其他 Oracle 客户端中执行
-- ============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
    v_v1_result   NUMBER;
    v_v2_result   NUMBER;
    v_v2_delta    NUMBER;
    v_v2_retcode  NUMBER;
    v_v2_retmsg   VARCHAR2(4000);
    v_start       NUMBER;
    v_end         NUMBER;
    v_v1_total    NUMBER;
    v_v2_total    NUMBER;
    v_runs        NUMBER := 10;

    TYPE rec_t IS RECORD (
        label  VARCHAR2(20),
        n      NUMBER,
        call_i NUMBER,
        amer_i NUMBER,
        v1_ms  NUMBER,
        v2_ms  NUMBER,
        speedup NUMBER,
        v1_val NUMBER,
        v2_val NUMBER,
        v2_del NUMBER
    );
    TYPE arr_t IS TABLE OF rec_t INDEX BY PLS_INTEGER;
    v_results arr_t;
    v_idx PLS_INTEGER := 0;
BEGIN
    -- 测试用例
    FOR tc IN (
        SELECT 1 AS cn, 100 AS nn, 1 AS ci, 1 AS ai, 'AC_100'  AS lb FROM DUAL UNION ALL
        SELECT 2, 500,  1, 1, 'AC_500'  FROM DUAL UNION ALL
        SELECT 3, 1000, 1, 1, 'AC_1000' FROM DUAL UNION ALL
        SELECT 4, 2000, 1, 1, 'AC_2000' FROM DUAL UNION ALL
        SELECT 5, 5000, 1, 1, 'AC_5000' FROM DUAL UNION ALL
        SELECT 6, 100,  0, 1, 'AP_100'  FROM DUAL UNION ALL
        SELECT 7, 500,  0, 1, 'AP_500'  FROM DUAL UNION ALL
        SELECT 8, 1000, 0, 1, 'AP_1000' FROM DUAL UNION ALL
        SELECT 9, 2000, 0, 1, 'AP_2000' FROM DUAL UNION ALL
        SELECT 10,5000, 0, 1, 'AP_5000' FROM DUAL UNION ALL
        SELECT 11,1000, 1, 0, 'EC_1000' FROM DUAL UNION ALL
        SELECT 12,1000, 0, 0, 'EP_1000' FROM DUAL
    ) LOOP
        v_idx := v_idx + 1;
        v_results(v_idx).label  := tc.lb;
        v_results(v_idx).n      := tc.nn;
        v_results(v_idx).call_i := tc.ci;
        v_results(v_idx).amer_i := tc.ai;

        -- V1 基准
        v_start := DBMS_UTILITY.get_time;
        FOR r IN 1 .. v_runs LOOP
            binomial_option_price(0.2, 100, 100, 0.05, 1, tc.nn,
                TO_CHAR(tc.ci), TO_CHAR(tc.ai), v_v1_result);
        END LOOP;
        v_end := DBMS_UTILITY.get_time;
        v_v1_total := (v_end - v_start) * 10;  -- centiseconds -> ms

        -- V2 基准
        v_start := DBMS_UTILITY.get_time;
        FOR r IN 1 .. v_runs LOOP
            binomial_option_price_v2(100, 100, 1.0, 0.05, 0.2, tc.nn,
                tc.ci, tc.ai, v_v2_result, v_v2_delta, v_v2_retcode, v_v2_retmsg);
        END LOOP;
        v_end := DBMS_UTILITY.get_time;
        v_v2_total := (v_end - v_start) * 10;

        -- 重新获取精确结果
        binomial_option_price(0.2, 100, 100, 0.05, 1, tc.nn,
            TO_CHAR(tc.ci), TO_CHAR(tc.ai), v_v1_result);
        binomial_option_price_v2(100, 100, 1.0, 0.05, 0.2, tc.nn,
            tc.ci, tc.ai, v_v2_result, v_v2_delta, v_v2_retcode, v_v2_retmsg);

        v_results(v_idx).v1_ms := v_v1_total / v_runs;
        v_results(v_idx).v2_ms := v_v2_total / v_runs;
        v_results(v_idx).speedup := ROUND(v_v1_total / GREATEST(v_v2_total, 1), 2);
        v_results(v_idx).v1_val := v_v1_result;
        v_results(v_idx).v2_val := v_v2_result;
        v_results(v_idx).v2_del := v_v2_delta;
    END LOOP;

    -- 输出结果
    DBMS_OUTPUT.PUT_LINE('================================================================================');
    DBMS_OUTPUT.PUT_LINE('  Oracle Performance Benchmark: V1 (NUMBER) vs V2 (BINARY_DOUBLE)');
    DBMS_OUTPUT.PUT_LINE('================================================================================');
    DBMS_OUTPUT.PUT_LINE('  Parameters: S=100, K=100, T=1yr, r=0.05, sigma=0.2, runs=' || v_runs);
    DBMS_OUTPUT.PUT_LINE('--------------------------------------------------------------------------------');
    DBMS_OUTPUT.PUT_LINE(RPAD('Case', 12) || ' ' || RPAD('N', 6) || ' ' ||
        RPAD('V1 ms/run', 14) || ' ' || RPAD('V2 ms/run', 14) || ' ' ||
        RPAD('Speedup', 10) || ' ' || RPAD('V1 Price', 14) || ' ' ||
        RPAD('V2 Price', 14) || ' ' || RPAD('Delta', 12));
    DBMS_OUTPUT.PUT_LINE('--------------------------------------------------------------------------------');
    FOR i IN 1 .. v_idx LOOP
        DBMS_OUTPUT.PUT_LINE(
            RPAD(v_results(i).label, 12) || ' ' ||
            RPAD(TO_CHAR(v_results(i).n), 6) || ' ' ||
            RPAD(TO_CHAR(ROUND(v_results(i).v1_ms, 1), 'FM999999990.0'), 14) || ' ' ||
            RPAD(TO_CHAR(ROUND(v_results(i).v2_ms, 1), 'FM999999990.0'), 14) || ' ' ||
            RPAD(TO_CHAR(v_results(i).speedup, 'FM99990.00') || 'x', 10) || ' ' ||
            RPAD(TO_CHAR(v_results(i).v1_val, 'FM9999990.000000'), 14) || ' ' ||
            RPAD(TO_CHAR(v_results(i).v2_val, 'FM9999990.000000'), 14) || ' ' ||
            RPAD(TO_CHAR(v_results(i).v2_del, 'FM9.00000000'), 12)
        );
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('================================================================================');
END;
/