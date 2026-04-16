package main

import (
	"fmt"
	"math"
	"os"
	"strconv"
	"time"
)

// BinomialOption CRR 二叉树计算美式/欧式期权价格
//
// 参数:
//   S0         - 标的资产当前价格
//   K          - 执行价格
//   T          - 到期时间(年)
//   r          - 无风险利率
//   sigma      - 波动率
//   N          - 二叉树步数
//   isCall     - true=看涨, false=看跌
//   isAmerican - true=美式(可提前行权), false=欧式
func BinomialOption(S0, K, T, r, sigma float64, N int, isCall, isAmerican bool) float64 {
	dt := T / float64(N)
	u := math.Exp(sigma * math.Sqrt(dt))
	d := 1.0 / u
	disc := math.Exp(-r * dt)
	p := (math.Exp(r*dt) - d) / (u - d)

	opt := make([]float64, N+1)

	// 终点: 到期收益
	for j := 0; j <= N; j++ {
		S := S0 * math.Pow(u, float64(j)) * math.Pow(d, float64(N-j))
		if isCall {
			opt[j] = math.Max(S-K, 0.0)
		} else {
			opt[j] = math.Max(K-S, 0.0)
		}
	}

	// 反向推导
	for i := N - 1; i >= 0; i-- {
		for j := 0; j <= i; j++ {
			S := S0 * math.Pow(u, float64(j)) * math.Pow(d, float64(i-j))
			continuation := disc * (p*opt[j+1] + (1.0-p)*opt[j])

			if isAmerican {
				var intrinsic float64
				if isCall {
					intrinsic = math.Max(S-K, 0.0)
				} else {
					intrinsic = math.Max(K-S, 0.0)
				}
				opt[j] = math.Max(intrinsic, continuation)
			} else {
				opt[j] = continuation
			}
		}
	}

	return opt[0]
}

func main() {
	// 默认参数
	S0 := 100.0
	K := 100.0
	T := 1.0
	r := 0.05
	sigma := 0.2
	N := 1000

	// 命令行参数
	if len(os.Args) >= 7 {
		S0, _ = strconv.ParseFloat(os.Args[1], 64)
		K, _ = strconv.ParseFloat(os.Args[2], 64)
		T, _ = strconv.ParseFloat(os.Args[3], 64)
		r, _ = strconv.ParseFloat(os.Args[4], 64)
		sigma, _ = strconv.ParseFloat(os.Args[5], 64)
		N, _ = strconv.Atoi(os.Args[6])
	}

	// CRR 模型参数
	dt := T / float64(N)
	u := math.Exp(sigma * math.Sqrt(dt))
	d := 1.0 / u
	p := (math.Exp(r*dt) - d) / (u - d)
	disc := math.Exp(-r * dt)

	fmt.Println("============================================================")
	fmt.Println("  美式期权二叉树定价模型 (CRR - Cox-Ross-Rubinstein)")
	fmt.Println("============================================================")
	fmt.Println("  参数:")
	fmt.Printf("    标的资产价格 S0  = %.2f\n", S0)
	fmt.Printf("    执行价格 K       = %.2f\n", K)
	fmt.Printf("    到期时间 T       = %.2f 年\n", T)
	fmt.Printf("    无风险利率 r     = %.4f (%.2f%%)\n", r, r*100)
	fmt.Printf("    波动率 sigma     = %.4f (%.2f%%)\n", sigma, sigma*100)
	fmt.Printf("    二叉树步数 N     = %d\n", N)
	fmt.Println("  CRR 模型参数:")
	fmt.Printf("    时间步长 dt      = %.10f\n", dt)
	fmt.Printf("    上涨因子 u       = %.10f\n", u)
	fmt.Printf("    下跌因子 d       = %.10f\n", d)
	fmt.Printf("    风险中性概率 p   = %.10f\n", p)
	fmt.Printf("    折现因子 disc    = %.10f\n", disc)
	fmt.Println("============================================================")

	// 计算并计时
	t0 := time.Now()
	amCall := BinomialOption(S0, K, T, r, sigma, N, true, true)
	t1 := time.Now()

	amPut := BinomialOption(S0, K, T, r, sigma, N, false, true)
	t2 := time.Now()

	euCall := BinomialOption(S0, K, T, r, sigma, N, true, false)
	t3 := time.Now()

	euPut := BinomialOption(S0, K, T, r, sigma, N, false, false)
	t4 := time.Now()

	fmt.Println("\n  计算结果:")
	fmt.Printf("    美式看涨期权价格 = %.6f  (耗时 %.4fs)\n", amCall, t1.Sub(t0).Seconds())
	fmt.Printf("    美式看跌期权价格 = %.6f  (耗时 %.4fs)\n", amPut, t2.Sub(t1).Seconds())
	fmt.Printf("    欧式看涨期权价格 = %.6f  (耗时 %.4fs)\n", euCall, t3.Sub(t2).Seconds())
	fmt.Printf("    欧式看跌期权价格 = %.6f  (耗时 %.4fs)\n", euPut, t4.Sub(t3).Seconds())

	// 验证
	pvK := K * math.Exp(-r*T)
	pcpAm := math.Abs(amCall - amPut - (S0 - pvK))
	pcpEu := math.Abs(euCall - euPut - (S0 - pvK))

	fmt.Println("\n  验证:")
	fmt.Printf("    美式期权 Put-Call 差异 (应 > 0)   = %.6f\n", pcpAm)
	fmt.Printf("    欧式期权 Put-Call 差异 (应 ≈ 0)   = %.6f\n", pcpEu)
	fmt.Printf("    美式看涨 - 欧式看涨 = %.6f (提前行权利 = %v)\n",
		amCall-euCall, amCall > euCall)
	fmt.Printf("    美式看跌 - 欧式看跌 = %.6f (提前行权利 = %v)\n",
		amPut-euPut, amPut > euPut)

	// 收敛性测试
	fmt.Println("\n  收敛性测试 (美式看跌期权):")
	steps := []int{10, 50, 100, 500, 1000, 5000, 10000}
	for _, step := range steps {
		price := BinomialOption(S0, K, T, r, sigma, step, false, true)
		fmt.Printf("    N = %6d  =>  %.6f\n", step, price)
	}

	fmt.Println("============================================================")
}