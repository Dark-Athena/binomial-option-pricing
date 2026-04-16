import java.util.Arrays;

/**
 * 美式/欧式期权二叉树定价模型 (CRR - Cox-Ross-Rubinstein)
 * 纯算法实现，不含数据库依赖
 *
 * 优化版相比原版主要改进：
 * 1. intr 递推替代 POWER() 调用（消除 99%+ 的 POWER 调用）
 * 2. SIGN 统一看涨/看跌，消除 IF/ELSE 分支
 * 3. 常量预计算（1-p, dd, intrStep）
 */
public class BinomialOptionPricing {

    // ========== V1: 原始版本 ==========
    public static double priceV1(
            double s0, double k, double t, double r, double sigma,
            int n, boolean isCall, boolean isAmer) {

        double dt = t / n;
        double u = Math.exp(sigma * Math.sqrt(dt));
        double d = 1.0 / u;
        double p = (Math.exp(r * dt) - d) / (u - d);
        double disc = Math.exp(-r * dt);

        // 叶子节点期权价值
        double[] opt = new double[n + 1];
        for (int j = 0; j <= n; j++) {
            double stk = s0 * Math.pow(u, n - j) * Math.pow(d, j);
            opt[j] = isCall ? Math.max(stk - k, 0) : Math.max(k - stk, 0);
        }

        // 倒推
        for (int i = n - 1; i >= 0; i--) {
            for (int j = 0; j <= i; j++) {
                double cont = disc * (p * opt[j + 1] + (1 - p) * opt[j]);
                if (isAmer) {
                    double stk = s0 * Math.pow(u, i - j) * Math.pow(d, j);
                    double intr = isCall ? Math.max(stk - k, 0) : Math.max(k - stk, 0);
                    opt[j] = Math.max(intr, cont);
                } else {
                    opt[j] = cont;
                }
            }
        }
        return opt[0];
    }

    // ========== V2: 优化版本 ==========
    public static double priceV2(
            double s0, double k, double t, double r, double sigma,
            int n, boolean isCall, boolean isAmer) {

        double dt = t / n;
        double u = Math.exp(sigma * Math.sqrt(dt));
        double d = 1.0 / u;
        double p = (Math.exp(r * dt) - d) / (u - d);
        double oneMinusP = 1.0 - p;
        double disc = Math.exp(-r * dt);
        double dd = d * d;
        double sign = isCall ? 1.0 : -1.0;
        double signK = sign * k;
        double intrStep = signK * (dd - 1.0);

        double[] opt = new double[n + 2];

        // 叶子节点
        double base = s0 * Math.pow(u, n);
        for (int j = 0; j <= n; j++) {
            opt[j] = Math.max(0.0, sign * (base - k));
            base = base * d;
        }

        // 倒推
        base = s0 * Math.pow(u, n) * d;
        for (int i = n - 1; i >= 0; i--) {
            double intr = sign * base - signK;
            for (int j = 0; j <= i; j++) {
                double cont = disc * (p * opt[j + 1] + oneMinusP * opt[j + 2]);
                if (isAmer) {
                    opt[j] = Math.max(cont, intr);
                } else {
                    opt[j] = cont;
                }
                intr = intr * dd + intrStep;
            }
            base = base * d;
        }
        return opt[0];
    }

    // ========== 基准测试入口 ==========
    public static void main(String[] args) {
        // --- 单次验证 ---
        System.out.println("=== Value Verification (S=100, K=100, T=1, r=0.05, sigma=0.2) ===");
        for (int n : new int[]{100, 500, 1000}) {
            for (String type : new String[]{"AC", "AP", "EC", "EP"}) {
                boolean isCall = type.charAt(0) == 'C';
                boolean isAmer = type.charAt(1) == 'A';
                double v1 = priceV1(100, 100, 1.0, 0.05, 0.2, n, isCall, isAmer);
                double v2 = priceV2(100, 100, 1.0, 0.05, 0.2, n, isCall, isAmer);
                double diff = Math.abs(v1 - v2);
                System.out.printf("  %s N=%-5d  V1=%.10f  V2=%.10f  diff=%.2e%n",
                    type, n, v1, v2, diff);
            }
        }

        // --- 性能基准 ---
        System.out.println();
        System.out.println("=== Performance Benchmark ===");
        System.out.printf("%-10s  %5s  %12s  %12s  %8s%n", "Case", "N", "V1 (ms/run)", "V2 (ms/run)", "Speedup");
        System.out.println("-".repeat(55));

        int runs = 50; // Java 快，多跑一些
        String[][] cases = {
            {"AC", "100"}, {"AC", "500"}, {"AC", "1000"}, {"AC", "2000"}, {"AC", "5000"},
            {"AP", "100"}, {"AP", "500"}, {"AP", "1000"}, {"AP", "2000"}, {"AP", "5000"},
            {"EC", "1000"}, {"EP", "1000"},
        };

        for (String[] tc : cases) {
            boolean isCall = tc[0].charAt(0) == 'C';
            boolean isAmer = tc[0].charAt(1) == 'A';
            int n = Integer.parseInt(tc[1]);

            // Warmup
            for (int w = 0; w < 10; w++) {
                priceV1(100, 100, 1.0, 0.05, 0.2, n, isCall, isAmer);
                priceV2(100, 100, 1.0, 0.05, 0.2, n, isCall, isAmer);
            }

            long t1 = System.nanoTime();
            for (int i = 0; i < runs; i++)
                priceV1(100, 100, 1.0, 0.05, 0.2, n, isCall, isAmer);
            long d1 = (System.nanoTime() - t1) / 1_000_000;

            long t2 = System.nanoTime();
            for (int i = 0; i < runs; i++)
                priceV2(100, 100, 1.0, 0.05, 0.2, n, isCall, isAmer);
            long d2 = (System.nanoTime() - t2) / 1_000_000;

            double sp = (double) d1 / Math.max(d2, 1);
            System.out.printf("%-10s  %5s  %10.1f  %10.1f  %6.2fx%n",
                tc[0], tc[1], d1 / (double) runs, d2 / (double) runs, sp);
        }
    }
}
