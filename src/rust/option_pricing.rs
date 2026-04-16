//! 美式期权二叉树定价模型 (CRR - Cox-Ross-Rubinstein)
//!
//! 编译: rustc -O -o option_pricing option_pricing.rs
//! 运行: ./option_pricing [S0] [K] [T] [r] [sigma] [N]
//! 示例: ./option_pricing 100 100 1.0 0.05 0.2 1000

use std::env;
use std::time::Instant;

/// CRR 二叉树计算美式/欧式期权价格
///
/// # 参数
/// - `S0`: 标的资产当前价格
/// - `K`: 执行价格
/// - `T`: 到期时间(年)
/// - `r`: 无风险利率
/// - `sigma`: 波动率
/// - `n`: 二叉树步数
/// - `is_call`: true=看涨, false=看跌
/// - `is_american`: true=美式(可提前行权), false=欧式
fn binomial_option(
    s0: f64,
    k: f64,
    t: f64,
    r: f64,
    sigma: f64,
    n: usize,
    is_call: bool,
    is_american: bool,
) -> f64 {
    let dt = t / n as f64;
    let u = (sigma * dt.sqrt()).exp();
    let d = 1.0 / u;
    let disc = (-r * dt).exp();
    let p = ((r * dt).exp() - d) / (u - d);

    let mut opt = vec![0.0f64; n + 1];

    // 终点: 到期收益
    for j in 0..=n {
        let s = s0 * u.powi(j as i32) * d.powi((n - j) as i32);
        opt[j] = if is_call {
            (s - k).max(0.0)
        } else {
            (k - s).max(0.0)
        };
    }

    // 反向推导
    for i in (0..n).rev() {
        for j in 0..=i {
            let s = s0 * u.powi(j as i32) * d.powi((i - j) as i32);
            let continuation = disc * (p * opt[j + 1] + (1.0 - p) * opt[j]);

            if is_american {
                let intrinsic = if is_call {
                    (s - k).max(0.0)
                } else {
                    (k - s).max(0.0)
                };
                opt[j] = intrinsic.max(continuation);
            } else {
                opt[j] = continuation;
            }
        }
    }

    opt[0]
}

fn main() {
    let args: Vec<String> = env::args().collect();

    // 默认参数
    let mut s0 = 100.0_f64;
    let mut k = 100.0_f64;
    let mut t = 1.0_f64;
    let mut r = 0.05_f64;
    let mut sigma = 0.2_f64;
    let mut n: usize = 1000;

    if args.len() >= 7 {
        s0 = args[1].parse().unwrap_or(s0);
        k = args[2].parse().unwrap_or(k);
        t = args[3].parse().unwrap_or(t);
        r = args[4].parse().unwrap_or(r);
        sigma = args[5].parse().unwrap_or(sigma);
        n = args[6].parse().unwrap_or(n);
    }

    // CRR 模型参数
    let dt = t / n as f64;
    let u = (sigma * dt.sqrt()).exp();
    let d = 1.0 / u;
    let p = ((r * dt).exp() - d) / (u - d);
    let disc = (-r * dt).exp();

    println!("============================================================");
    println!("  美式期权二叉树定价模型 (CRR - Cox-Ross-Rubinstein)");
    println!("============================================================");
    println!("  参数:");
    println!("    标的资产价格 S0  = {:.2}", s0);
    println!("    执行价格 K       = {:.2}", k);
    println!("    到期时间 T       = {:.2} 年", t);
    println!("    无风险利率 r     = {:.4} ({:.2}%)", r, r * 100.0);
    println!("    波动率 sigma     = {:.4} ({:.2}%)", sigma, sigma * 100.0);
    println!("    二叉树步数 N     = {}", n);
    println!("  CRR 模型参数:");
    println!("    时间步长 dt      = {:.10}", dt);
    println!("    上涨因子 u       = {:.10}", u);
    println!("    下跌因子 d       = {:.10}", d);
    println!("    风险中性概率 p   = {:.10}", p);
    println!("    折现因子 disc    = {:.10}", disc);
    println!("============================================================");

    // 计算
    let t0 = Instant::now();
    let am_call = binomial_option(s0, k, t, r, sigma, n, true, true);
    let t1 = Instant::now();

    let am_put = binomial_option(s0, k, t, r, sigma, n, false, true);
    let t2 = Instant::now();

    let eu_call = binomial_option(s0, k, t, r, sigma, n, true, false);
    let t3 = Instant::now();

    let eu_put = binomial_option(s0, k, t, r, sigma, n, false, false);
    let t4 = Instant::now();

    println!("\n  计算结果:");
    println!(
        "    美式看涨期权价格 = {:.6}  (耗时 {:.4}s)",
        am_call,
        t1.duration_since(t0).as_secs_f64()
    );
    println!(
        "    美式看跌期权价格 = {:.6}  (耗时 {:.4}s)",
        am_put,
        t2.duration_since(t1).as_secs_f64()
    );
    println!(
        "    欧式看涨期权价格 = {:.6}  (耗时 {:.4}s)",
        eu_call,
        t3.duration_since(t2).as_secs_f64()
    );
    println!(
        "    欧式看跌期权价格 = {:.6}  (耗时 {:.4}s)",
        eu_put,
        t4.duration_since(t3).as_secs_f64()
    );

    // 验证
    let pv_k = k * (-r * t).exp();
    let pcp_am = (am_call - am_put - (s0 - pv_k)).abs();
    let pcp_eu = (eu_call - eu_put - (s0 - pv_k)).abs();

    println!("\n  验证:");
    println!(
        "    美式期权 Put-Call 差异 (应 > 0)   = {:.6}",
        pcp_am
    );
    println!(
        "    欧式期权 Put-Call 差异 (应 ≈ 0)   = {:.6}",
        pcp_eu
    );
    println!(
        "    美式看涨 - 欧式看涨 = {:.6} (提前行权利 = {})",
        am_call - eu_call,
        am_call > eu_call
    );
    println!(
        "    美式看跌 - 欧式看跌 = {:.6} (提前行权利 = {})",
        am_put - eu_put,
        am_put > eu_put
    );

    // 收敛性测试
    println!("\n  收敛性测试 (美式看跌期权):");
    let steps: [usize; 7] = [10, 50, 100, 500, 1000, 5000, 10000];
    for &step in &steps {
        let price = binomial_option(s0, k, t, r, sigma, step, false, true);
        println!("    N = {:6}  =>  {:.6}", step, price);
    }

    println!("============================================================");
}