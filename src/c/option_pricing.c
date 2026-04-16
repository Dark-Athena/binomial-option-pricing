/*
 * 美式期权二叉树定价模型 (CRR - Cox-Ross-Rubinstein)
 * 
 * 编译: gcc -O2 -o option_pricing option_pricing.c -lm
 * 运行: ./option_pricing [S0] [K] [T] [r] [sigma] [N]
 * 示例: ./option_pricing 100 100 1.0 0.05 0.2 1000
 */

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <time.h>

/*
 * CRR 二叉树计算美式/欧式期权价格
 * 
 * 参数:
 *   S0         - 标的资产当前价格
 *   K          - 执行价格
 *   T          - 到期时间(年)
 *   r          - 无风险利率
 *   sigma      - 波动率
 *   N          - 二叉树步数
 *   is_call    - 1=看涨期权, 0=看跌期权
 *   is_american - 1=美式(可提前行权), 0=欧式
 * 
 * 返回:
 *   期权价格
 */
double binomial_option(double S0, double K, double T, double r, double sigma,
                       int N, int is_call, int is_american)
{
    double dt = T / N;
    double u = exp(sigma * sqrt(dt));
    double d = 1.0 / u;
    double disc = exp(-r * dt);
    double p = (exp(r * dt) - d) / (u - d);

    /* 分配期权价值数组 (当前步 +1 个节点) */
    double *opt = (double *)malloc((N + 1) * sizeof(double));
    if (!opt) {
        fprintf(stderr, "内存分配失败\n");
        exit(1);
    }

    /* 终点: 到期收益 */
    for (int j = 0; j <= N; j++) {
        double S = S0 * pow(u, j) * pow(d, N - j);
        if (is_call)
            opt[j] = fmax(S - K, 0.0);
        else
            opt[j] = fmax(K - S, 0.0);
    }

    /* 反向推导 */
    for (int i = N - 1; i >= 0; i--) {
        for (int j = 0; j <= i; j++) {
            double S = S0 * pow(u, j) * pow(d, i - j);
            double continuation = disc * (p * opt[j + 1] + (1.0 - p) * opt[j]);

            if (is_american) {
                double intrinsic = is_call ? fmax(S - K, 0.0) : fmax(K - S, 0.0);
                opt[j] = fmax(intrinsic, continuation);
            } else {
                opt[j] = continuation;
            }
        }
    }

    double result = opt[0];
    free(opt);
    return result;
}

int main(int argc, char *argv[])
{
    /* 默认参数 */
    double S0 = 100.0;
    double K = 100.0;
    double T = 1.0;
    double r = 0.05;
    double sigma = 0.2;
    int N = 1000;

    /* 命令行参数解析 */
    if (argc >= 7) {
        S0 = atof(argv[1]);
        K = atof(argv[2]);
        T = atof(argv[3]);
        r = atof(argv[4]);
        sigma = atof(argv[5]);
        N = atoi(argv[6]);
    }

    /* 打印参数 */
    printf("============================================================\n");
    printf("  美式期权二叉树定价模型 (CRR - Cox-Ross-Rubinstein)\n");
    printf("============================================================\n");
    printf("  参数:\n");
    printf("    标的资产价格 S0  = %.2f\n", S0);
    printf("    执行价格 K       = %.2f\n", K);
    printf("    到期时间 T       = %.2f 年\n", T);
    printf("    无风险利率 r     = %.4f (%.2f%%)\n", r, r * 100);
    printf("    波动率 sigma     = %.4f (%.2f%%)\n", sigma, sigma * 100);
    printf("    二叉树步数 N     = %d\n", N);

    double dt = T / N;
    double u = exp(sigma * sqrt(dt));
    double d = 1.0 / u;
    double p = (exp(r * dt) - d) / (u - d);
    double disc = exp(-r * dt);

    printf("  CRR 模型参数:\n");
    printf("    时间步长 dt      = %.10f\n", dt);
    printf("    上涨因子 u       = %.10f\n", u);
    printf("    下跌因子 d       = %.10f\n", d);
    printf("    风险中性概率 p   = %.10f\n", p);
    printf("    折现因子 disc    = %.10f\n", disc);
    printf("============================================================\n");

    /* 计算并计时 */
    clock_t t0, t1;

    t0 = clock();
    double am_call = binomial_option(S0, K, T, r, sigma, N, 1, 1);
    t1 = clock();

    double am_put = binomial_option(S0, K, T, r, sigma, N, 0, 1);
    clock_t t2 = clock();

    double eu_call = binomial_option(S0, K, T, r, sigma, N, 1, 0);
    clock_t t3 = clock();

    double eu_put = binomial_option(S0, K, T, r, sigma, N, 0, 0);
    clock_t t4 = clock();

    printf("\n  计算结果:\n");
    printf("    美式看涨期权价格 = %.6f  (耗时 %.4fs)\n", am_call, (double)(t1 - t0) / CLOCKS_PER_SEC);
    printf("    美式看跌期权价格 = %.6f  (耗时 %.4fs)\n", am_put, (double)(t2 - t1) / CLOCKS_PER_SEC);
    printf("    欧式看涨期权价格 = %.6f  (耗时 %.4fs)\n", eu_call, (double)(t3 - t2) / CLOCKS_PER_SEC);
    printf("    欧式看跌期权价格 = %.6f  (耗时 %.4fs)\n", eu_put, (double)(t4 - t3) / CLOCKS_PER_SEC);

    /* 验证 */
    double pv_k = K * exp(-r * T);
    double pcp_am = fabs(am_call - am_put - (S0 - pv_k));
    double pcp_eu = fabs(eu_call - eu_put - (S0 - pv_k));

    printf("\n  验证:\n");
    printf("    美式期权 Put-Call 差异 (应 > 0)   = %.6f\n", pcp_am);
    printf("    欧式期权 Put-Call 差异 (应 ≈ 0)   = %.6f\n", pcp_eu);
    printf("    美式看涨 - 欧式看涨 = %.6f (提前行权利 = %s)\n",
           am_call - eu_call, am_call > eu_call ? "True" : "False");
    printf("    美式看跌 - 欧式看跌 = %.6f (提前行权利 = %s)\n",
           am_put - eu_put, am_put > eu_put ? "True" : "False");

    /* 收敛性测试 */
    printf("\n  收敛性测试 (美式看跌期权):\n");
    int steps[] = {10, 50, 100, 500, 1000, 5000, 10000};
    int num_steps = sizeof(steps) / sizeof(steps[0]);
    for (int i = 0; i < num_steps; i++) {
        double price = binomial_option(S0, K, T, r, sigma, steps[i], 0, 1);
        printf("    N = %6d  =>  %.6f\n", steps[i], price);
    }

    printf("============================================================\n");
    return 0;
}