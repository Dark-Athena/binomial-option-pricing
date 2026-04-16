#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
美式期权二叉树定价模型 (CRR - Cox-Ross-Rubinstein)

算法原理:
  1. 将期权到期时间 T 等分为 N 个时间步长 dt = T / N
  2. 计算 CRR 参数:
     - u = e^(sigma * sqrt(dt))      (股价上涨因子)
     - d = e^(-sigma * sqrt(dt))     (股价下跌因子, d = 1/u)
     - p = (e^(r*dt) - d) / (u - d) (风险中性概率)
     - disc = e^(-r*dt)             (单步折现因子)
  3. 正向构建股价二叉树: S[i][j] = S0 * u^j * d^(i-j)
     - i: 时间步 (0..N)
     - j: 节点位置 (0..i), j越大表示上涨次数越多
  4. 反向推导期权价值:
     a) 终点: opt[N][j] = max(payoff(S[N][j]), 0)
     b) 美式期权中间节点:
        opt[i][j] = max(
            payoff(S[i][j]),                # 提前行权的收益
            disc * (p * opt[i+1][j+1] + (1-p) * opt[i+1][j])  # 持有的期望价值
        )
     c) opt[0][0] 即为期权价格

使用方法:
  python3 option_pricing.py
  或
  python3 option_pricing.py --S0 100 --K 105 --T 1.0 --r 0.05 --sigma 0.2 --N 1000

作者: WPS灵犀
"""

import math
import argparse
import time


def american_option_binomial(S0, K, T, r, sigma, N, option_type="call"):
    """
    CRR 二叉树模型计算美式期权价格

    参数:
        S0        : 标的资产当前价格
        K         : 期权执行价格 (行权价)
        T         : 到期时间 (年)
        r         : 无风险年利率 (如 0.05 表示 5%)
        sigma     : 标的资产年波动率 (如 0.2 表示 20%)
        N         : 二叉树步数 (步数越多越精确，但越慢)
        option_type: "call" 看涨期权 / "put" 看跌期权

    返回:
        期权价格 (float)
    """
    dt = T / N
    u = math.exp(sigma * math.sqrt(dt))
    d = 1.0 / u
    disc = math.exp(-r * dt)
    p = (math.exp(r * dt) - d) / (u - d)

    # 仅存储当前列和下一列，空间优化 O(N)
    # opt[j] 表示当前时间步第 j 个节点的期权价值
    opt = [0.0] * (N + 1)

    # 终点: 计算到期时的期权收益
    for j in range(N + 1):
        S = S0 * (u ** j) * (d ** (N - j))
        if option_type == "call":
            opt[j] = max(S - K, 0.0)
        else:
            opt[j] = max(K - S, 0.0)

    # 反向推导: 从 N-1 步到第 0 步
    for i in range(N - 1, -1, -1):
        for j in range(i + 1):
            S = S0 * (u ** j) * (d ** (i - j))
            if option_type == "call":
                intrinsic = max(S - K, 0.0)
            else:
                intrinsic = max(K - S, 0.0)
            continuation = disc * (p * opt[j + 1] + (1.0 - p) * opt[j])
            opt[j] = max(intrinsic, continuation)

    return opt[0]


def european_option_binomial(S0, K, T, r, sigma, N, option_type="call"):
    """
    欧式期权二叉树定价 (不含提前行权判断)
    """
    dt = T / N
    u = math.exp(sigma * math.sqrt(dt))
    d = 1.0 / u
    disc = math.exp(-r * dt)
    p = (math.exp(r * dt) - d) / (u - d)

    opt = [0.0] * (N + 1)

    for j in range(N + 1):
        S = S0 * (u ** j) * (d ** (N - j))
        if option_type == "call":
            opt[j] = max(S - K, 0.0)
        else:
            opt[j] = max(K - S, 0.0)

    for i in range(N - 1, -1, -1):
        for j in range(i + 1):
            opt[j] = disc * (p * opt[j + 1] + (1.0 - p) * opt[j])

    return opt[0]


def print_parameters(S0, K, T, r, sigma, N):
    """打印 CRR 模型参数"""
    dt = T / N
    u = math.exp(sigma * math.sqrt(dt))
    d = 1.0 / u
    p = (math.exp(r * dt) - d) / (u - d)
    disc = math.exp(-r * dt)

    print(f"{'='*60}")
    print(f"  美式期权二叉树定价模型 (CRR - Cox-Ross-Rubinstein)")
    print(f"{'='*60}")
    print(f"  参数:")
    print(f"    标的资产价格 S0  = {S0}")
    print(f"    执行价格 K       = {K}")
    print(f"    到期时间 T       = {T} 年")
    print(f"    无风险利率 r     = {r} ({r*100:.2f}%)")
    print(f"    波动率 sigma     = {sigma} ({sigma*100:.2f}%)")
    print(f"    二叉树步数 N     = {N}")
    print(f"  CRR 模型参数:")
    print(f"    时间步长 dt      = {dt:.10f}")
    print(f"    上涨因子 u       = {u:.10f}")
    print(f"    下跌因子 d       = {d:.10f}")
    print(f"    风险中性概率 p   = {p:.10f}")
    print(f"    折现因子 disc    = {disc:.10f}")
    print(f"{'='*60}")


def main():
    parser = argparse.ArgumentParser(description="美式期权二叉树定价模型")
    parser.add_argument("--S0", type=float, default=100.0, help="标的资产当前价格 (默认: 100)")
    parser.add_argument("--K", type=float, default=100.0, help="执行价格 (默认: 100)")
    parser.add_argument("--T", type=float, default=1.0, help="到期时间/年 (默认: 1.0)")
    parser.add_argument("--r", type=float, default=0.05, help="无风险利率 (默认: 0.05)")
    parser.add_argument("--sigma", type=float, default=0.2, help="波动率 (默认: 0.2)")
    parser.add_argument("--N", type=int, default=1000, help="二叉树步数 (默认: 1000)")
    args = parser.parse_args()

    print_parameters(args.S0, args.K, args.T, args.r, args.sigma, args.N)

    # 美式看涨期权
    t0 = time.perf_counter()
    am_call = american_option_binomial(args.S0, args.K, args.T, args.r, args.sigma, args.N, "call")
    t1 = time.perf_counter()

    # 美式看跌期权
    am_put = american_option_binomial(args.S0, args.K, args.T, args.r, args.sigma, args.N, "put")
    t2 = time.perf_counter()

    # 欧式看涨期权 (对比)
    eu_call = european_option_binomial(args.S0, args.K, args.T, args.r, args.sigma, args.N, "call")
    t3 = time.perf_counter()

    # 欧式看跌期权 (对比)
    eu_put = european_option_binomial(args.S0, args.K, args.T, args.r, args.sigma, args.N, "put")
    t4 = time.perf_counter()

    print(f"\n  计算结果:")
    print(f"    美式看涨期权价格 = {am_call:.6f}  (耗时 {t1-t0:.4f}s)")
    print(f"    美式看跌期权价格 = {am_put:.6f}  (耗时 {t2-t1:.4f}s)")
    print(f"    欧式看涨期权价格 = {eu_call:.6f}  (耗时 {t3-t2:.4f}s)")
    print(f"    欧式看跌期权价格 = {eu_put:.6f}  (耗时 {t4-t3:.4f}s)")

    # Put-Call Parity 验证: C - P = S0 - K*e^(-rT)
    pv_k = args.K * math.exp(-args.r * args.T)
    pcp_diff_call = abs(am_call - am_put - (args.S0 - pv_k))
    pcp_diff_eu = abs(eu_call - eu_put - (args.S0 - pv_k))
    print(f"\n  验证:")
    print(f"    美式期权 Put-Call 差异 (应 > 0, 美式不满足严格平价) = {pcp_diff_call:.6f}")
    print(f"    欧式期权 Put-Call 差异 (应 ≈ 0)                   = {pcp_diff_eu:.6f}")
    print(f"    美式看涨 - 欧式看涨 = {am_call - eu_call:.6f} (提前行权利 = {am_call > eu_call})")
    print(f"    美式看跌 - 欧式看跌 = {am_put - eu_put:.6f} (提前行权利 = {am_put > eu_put})")
    print(f"{'='*60}")

    # 不同步数收敛性测试
    print(f"\n  收敛性测试 (美式看跌期权):")
    for n in [10, 50, 100, 500, 1000, 5000, 10000]:
        price = american_option_binomial(args.S0, args.K, args.T, args.r, args.sigma, n, "put")
        print(f"    N = {n:6d}  =>  {price:.6f}")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
