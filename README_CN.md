# 二叉树期权定价模型：跨语言性能基准测试

**CRR (Cox-Ross-Rubinstein) 二叉树模型 — 多语言实现与性能优化研究**

---

## 摘要

本项目提供了 CRR 二叉树期权定价模型的完整跨语言实现，涵盖 **C、Go、Java、Python、Rust** 五种编程语言以及 **Oracle PL/SQL / GaussDB PL/pgSQL** 两种数据库存储过程，并对两种不同的算法实现（V1 基线版 vs V2 优化版）进行了系统的性能对比分析。

**核心发现：** 通过将逐节点 `POWER()` 调用替换为常数时间内在价值递推（`intr = intr * dd + intrStep`），我们将 `POWER()` 调用总量从 O(N²) 降至 O(N)——对于典型 N 值，减少率超过 **99%**。结合硬件原生浮点类型（Oracle `BINARY_DOUBLE` / GaussDB `float8`）替代软件模拟十进制类型（`NUMBER` / `NUMERIC`），我们在 **Oracle 19c 上实现了最高 18.4 倍加速，GaussDB 9.2 上实现了 2.3 倍加速**。

---

## 目录

- [1. 数学模型](#1-数学模型)
- [2. 算法设计](#2-算法设计)
- [3. 优化策略](#3-优化策略)
- [4. 项目结构](#4-项目结构)
- [5. 编译与运行指南](#5-编译与运行指南)
  - [5.1 C](#51-c)
  - [5.2 Go](#52-go)
  - [5.3 Java](#53-java)
  - [5.4 Python](#54-python)
  - [5.5 Rust](#55-rust)
  - [5.6 Oracle PL/SQL](#56-oracle-plsql)
  - [5.7 GaussDB PL/pgSQL](#57-gaussdb-plpgsql)
- [6. 一键跑分脚本](#6-一键跑分脚本)
- [7. 跨语言性能分析](#7-跨语言性能分析)
- [8. 数据库优化深度分析](#8-数据库优化深度分析)
- [9. 结论](#9-结论)
- [10. 参考文献](#10-参考文献)

---

## 1. 数学模型

CRR 二叉树模型 [1] 将资产价格的连续时间随机过程离散化为二叉树。给定以下参数：

- **S₀**: 当前资产价格
- **K**: 行权价格
- **T**: 到期时间（年）
- **r**: 无风险利率
- **σ**: 波动率
- **N**: 时间步数

树参数定义为：

```
dt    = T / N                              # 时间步长
u     = exp(σ × √dt)                       # 上涨因子
d     = 1 / u                              # 下跌因子（重合树）
p     = (exp(r × dt) - d) / (u - d)        # 风险中性概率
disc  = exp(-r × dt)                       # 每步折现因子
```

节点 (i, j) 处的资产价格为：

```
S(i, j) = S₀ × u^j × d^(i-j)
```

**期权估值**通过逆向归纳法完成：

1. **终端节点 (i = N)：**
   ```
   看涨: opt(N, j) = max(S(N, j) - K, 0)
   看跌: opt(N, j) = max(K - S(N, j), 0)
   ```

2. **逆向归纳 (i = N-1 到 0)：**
   ```
   续值 = disc × (p × opt(i+1, j+1) + (1-p) × opt(i+1, j))

   欧式:    opt(i, j) = 续值
   美式:    opt(i, j) = max(内在价值(i, j), 续值)
   ```

3. **结果：** `opt(0, 0)` 即为期权价格。

---

## 2. 算法设计

### V1：基线实现

基线实现直接遵循教科书算法：

```
for i = N-1 down to 0:
    for j = 0 to i:
        S = S0 × POWER(u, i-j) × POWER(d, j)       # 每节点调用 POWER()
        cont = disc × (p × opt[j+1] + (1-p) × opt[j+2])
        if 美式:
            opt[j] = max(收益(S), cont)
        else:
            opt[j] = cont
```

**每节点开销：** 2 次 `POWER()` + 1 次内在价值计算（含分支判断）。

### V2：优化实现

V2 引入了三项关键优化（详见第 3 节）：

```
# 预计算常量
dd = d × d                              # d 的平方
signK = sign × K                        # 统一看涨/看跌
intrStep = signK × (dd - 1)             # 递推步长

for i = N-1 down to 0:
    base = base × d                      # 每层 O(1)
    intr = sign × base - signK           # 第一个节点内在价值
    for j = 0 to i:
        cont = disc × (p × opt[j+1] + q × opt[j+2])
        opt[j] = max(cont, intr)         # SIGN 统一处理看涨/看跌
        intr = intr × dd + intrStep      # 递推：O(1)，无 POWER()
```

**每节点开销：** 1 次乘法 + 1 次加法（递推内在价值），无分支。

---

## 3. 优化策略

### 3.1 内在价值递推（主要优化）

**这是单项影响最大的优化。**

V1 在每个节点计算 `S = S0 × u^(i-j) × d^j`，需要 2 次 `POWER()` 调用。对于 N 步二叉树，`POWER()` 总调用次数约为 N(N+1)/2 × 2 = O(N²)。

V2 利用了重合树的结构特性：在同一层 i 中，股价构成等比数列，公比为 d：

```
S(i, j) = S(i, 0) × d^j
```

这允许 O(1) 递推：

```
intr(j+1) = intr(j) × d² + signK × (d² - 1)
           = intr(j) × dd   + intrStep
```

**POWER() 调用次数对比：**

| N     | V1 POWER() 总次数 | V2 POWER() 总次数 | 减少比例 |
|-------|:-----------------:|:-----------------:|:--------:|
| 100   | 10,100            | 100               | 99.0%    |
| 500   | 250,500           | 500               | 99.8%    |
| 1,000 | 1,001,000         | 1,000             | 99.9%    |
| 5,000 | 25,005,000        | 5,000             | 99.98%   |

### 3.2 硬件浮点类型

Oracle 的 `NUMBER` 类型在软件层面实现十进制算术，而 `BINARY_DOUBLE` 直接映射到 IEEE 754 双精度硬件指令。对于二叉树模型的紧密内层循环（数百万次浮点运算），这一替换可带来 3-5 倍加速。

GaussDB 的 `NUMERIC` 同样存在类似问题——每次 `POWER`/`EXP` 运算后将结果转回高精度 NUMERIC（几十位小数），后续运算需要维护这些精度，累加效应随 N 急剧放大。

### 3.3 SIGN 统一看涨/看跌

替代循环内的分支判断：

```
-- V1: 热循环内分支
IF is_call = 1 THEN intrinsic := GREATEST(stk - K, 0);
ELSE               intrinsic := GREATEST(K - stk, 0); END IF;

-- V2: 通过符号乘数消除分支
sign = 1.0 (看涨) 或 -1.0 (看跌)
intrinsic = GREATEST(sign × stk - sign × K, 0)
```

### 3.4 常量外提

将 `1-p`、`d²`、递推步长 `signK × (dd - 1)` 等在循环外预计算，消除每个节点的冗余运算。

---

## 4. 项目结构

```
binomial-option-pricing/
├── README.md                          # 英文版文档
├── README_CN.md                       # 中文版文档（本文件）
├── .gitignore
├── run_benchmark.sh                   # 一键编译 + 跑分 + 生成报告
├── src/
│   ├── c/
│   │   └── option_pricing.c           # C 实现 (GCC/Clang)
│   ├── go/
│   │   └── option_pricing.go          # Go 实现
│   ├── java/
│   │   └── BinomialOptionPricing.java # Java 实现
│   ├── python/
│   │   └── option_pricing.py          # Python 实现
│   └── rust/
│       └── option_pricing.rs          # Rust 实现
├── sql/
│   ├── oracle_procedures.sql          # Oracle: V1 + V2 存储过程
│   ├── oracle_benchmark.sql           # Oracle: 性能对比测试
│   ├── gaussdb_procedures.sql         # GaussDB: V1 (NUMERIC) + V2 (float8)
│   └── gaussdb_benchmark.sql          # GaussDB: 性能对比测试
├── report/                            # 由 run_benchmark.sh 生成
│   ├── benchmark_results.csv
│   └── benchmark_report.md
└── lib/                               # JDBC 驱动（仅供参考）
```

---

## 5. 编译与运行指南

所有实现接受相同格式的命令行参数：

```
S0 K T r sigma N [is_call] [is_american]
```

- `is_call`: 1 = 看涨, 0 = 看跌（默认: 1）
- `is_american`: 1 = 美式, 0 = 欧式（默认: 1）

默认参数: `100 100 1.0 0.05 0.2 1000 1 1`（美式看涨, N=1000）

### 5.1 C

**依赖：** GCC 或 Clang，标准 C 数学库。

| 平台 | 编译 | 运行 |
|------|------|------|
| **Linux** | `gcc -O2 -o option_pricing option_pricing.c -lm` | `./option_pricing 100 100 1.0 0.05 0.2 1000 1 1` |
| **macOS** | `gcc -O2 -o option_pricing option_pricing.c -lm`<br>或 `clang -O2 -o option_pricing option_pricing.c -lm` | `./option_pricing 100 100 1.0 0.05 0.2 1000 1 1` |
| **Windows** | `gcc -O2 -o option_pricing.exe option_pricing.c -lm` (MSYS2/MinGW)<br>或 MSVC: `cl /O2 option_pricing.c` | `option_pricing.exe 100 100 1.0 0.05 0.2 1000 1 1` |

### 5.2 Go

**依赖：** Go 1.16+

| 平台 | 编译 | 运行 |
|------|------|------|
| **Linux** | `cd src/go && go build -o option_pricing option_pricing.go` | `./option_pricing 100 100 1.0 0.05 0.2 1000 1 1` |
| **macOS** | `cd src/go && go build -o option_pricing option_pricing.go` | `./option_pricing 100 100 1.0 0.05 0.2 1000 1 1` |
| **Windows** | `cd src\go && go build -o option_pricing.exe option_pricing.go` | `option_pricing.exe 100 100 1.0 0.05 0.2 1000 1 1` |

交叉编译示例：
```bash
GOOS=linux GOARCH=amd64 go build -o option_pricing_linux option_pricing.go
GOOS=windows GOARCH=amd64 go build -o option_pricing.exe option_pricing.go
```

### 5.3 Java

**依赖：** JDK 8+（无需外部库）。

| 平台 | 编译 | 运行 |
|------|------|------|
| **Linux** | `javac -d out src/java/BinomialOptionPricing.java` | `java -cp out BinomialOptionPricing 100 100 1.0 0.05 0.2 1000 1 1` |
| **macOS** | `javac -d out src/java/BinomialOptionPricing.java` | `java -cp out BinomialOptionPricing 100 100 1.0 0.05 0.2 1000 1 1` |
| **Windows** | `javac -d out src\java\BinomialOptionPricing.java` | `java -cp out BinomialOptionPricing 100 100 1.0 0.05 0.2 1000 1 1` |

### 5.4 Python

**依赖：** Python 3.6+（仅使用标准库 `math`、`time`、`argparse`）。

| 平台 | 运行 |
|------|------|
| **Linux** | `python3 src/python/option_pricing.py 100 100 1.0 0.05 0.2 1000 1 1`<br>或命名参数: `python3 src/python/option_pricing.py --S0 100 --K 100 --T 1 --r 0.05 --sigma 0.2 --N 1000` |
| **macOS** | 同 Linux |
| **Windows** | `python src\python\option_pricing.py 100 100 1.0 0.05 0.2 1000 1 1` |

如需更高性能，可使用 [PyPy](https://www.pypy.org/)：`pypy3 src/python/option_pricing.py 100 100 1.0 0.05 0.2 1000`

### 5.5 Rust

**依赖：** Rust 工具链 (`rustc`)。通过 [rustup](https://rustup.rs/) 安装。

| 平台 | 编译 | 运行 |
|------|------|------|
| **Linux** | `rustc -O -o option_pricing src/rust/option_pricing.rs` | `./option_pricing 100 100 1.0 0.05 0.2 1000 1 1` |
| **macOS** | `rustc -O -o option_pricing src/rust/option_pricing.rs` | `./option_pricing 100 100 1.0 0.05 0.2 1000 1 1` |
| **Windows** | `rustc -O -o option_pricing.exe src\rust\option_pricing.rs` | `option_pricing.exe 100 100 1.0 0.05 0.2 1000 1 1` |

交叉编译示例：
```bash
rustc -O --target x86_64-unknown-linux-gnu -o option_pricing_linux src/rust/option_pricing.rs
rustc -O --target x86_64-pc-windows-gnu -o option_pricing.exe src/rust/option_pricing.rs
```

### 5.6 Oracle PL/SQL

**文件：**
- `sql/oracle_procedures.sql` — V1 + V2 存储过程定义
- `sql/oracle_benchmark.sql` — 性能对比测试（在 SQL*Plus 中执行）

```sql
-- 步骤 1: 部署存储过程
@sql/oracle_procedures.sql

-- 步骤 2: 运行性能对比
@sql/oracle_benchmark.sql
```

**快速测试（匿名块）：**
```sql
SET SERVEROUTPUT ON;
DECLARE
    v_result NUMBER;
BEGIN
    -- V1
    binomial_option_price(100, 100, 1.0, 0.05, 0.2, 1000, 1, 1, v_result);
    DBMS_OUTPUT.PUT_LINE('V1 美式看涨: ' || v_result);

    -- V2（含 Delta 输出）
    DECLARE v2_delta NUMBER; v2_rc NUMBER; v2_msg VARCHAR2(4000);
    BEGIN
        binomial_option_price_v2(100, 100, 1.0, 0.05, 0.2, 1000, 1, 1,
            v_result, v2_delta, v2_rc, v2_msg);
        DBMS_OUTPUT.PUT_LINE('V2 美式看涨: ' || v_result || ', Delta: ' || v2_delta);
    END;
END;
/
```

### 5.7 GaussDB PL/pgSQL

**文件：**
- `sql/gaussdb_procedures.sql` — V1 (NUMERIC) + V2 (float8 优化版) 函数定义
- `sql/gaussdb_benchmark.sql` — 性能对比测试（在 gsql 中执行）

```sql
-- 步骤 1: 部署函数
\i sql/gaussdb_procedures.sql

-- 步骤 2: 运行性能对比
\i sql/gaussdb_benchmark.sql
```

**快速测试：**
```sql
SELECT binomial_amer_opt_v3(100, 100, 1.0, 0.05, 0.2, 1000, 1, 1);       -- V1 (NUMERIC)
SELECT binomial_amer_opt_v3_opt(100, 100, 1.0, 0.05, 0.2, 1000, 1, 1);   -- V2 (float8)
```

> **注意：** V1 使用 NUMERIC 类型，在 N >= 500 时可能因中间 POWER() 结果超出 NUMERIC 表示范围而溢出。V2 (float8) 不存在此限制。

---

## 6. 一键跑分脚本

`run_benchmark.sh` 可自动编译所有实现、运行基准测试并生成 Markdown 报告：

```bash
chmod +x run_benchmark.sh

# 默认: N=1000, 每种语言跑 20 次
./run_benchmark.sh

# 自定义 N 和运行次数
./run_benchmark.sh 5000 50

# N=10000, 10 次（解释型语言可能较慢）
./run_benchmark.sh 10000 10
```

**输出文件：**
- `report/benchmark_results.csv` — 结构化数据，可用于进一步分析
- `report/benchmark_report.md` — 人类可读的 Markdown 报告

**前置要求：** 脚本会自动检测可用的工具链，跳过缺失的。完整测试需安装：`gcc`、`go`、`jdk`、`python3`、`rustc`。

**Windows 用户：** 请通过 Git Bash、WSL 或 MSYS2 运行。

---

## 7. 跨语言性能分析

### 7.1 相对性能排名（单线程, N=1000）

典型的相对性能排名（从快到慢）：

| 排名 | 语言 | 相对速度 | 说明 |
|:----:|------|:--------:|------|
| 1 | **C** | 1.0x (基线) | 直接硬件访问, -O2 优化 |
| 2 | **Rust** | ~1.0-1.2x | 零成本抽象, LLVM 后端 |
| 3 | **Go** | ~2-3x | GC 暂停, 边界检查 |
| 4 | **Java** | ~2-4x | JIT 预热, GC 开销 |
| 5 | **Python** | ~50-100x | 解释执行, 无 JIT (CPython) |

> 实际数据因硬件、N 和编译器参数而异。请运行 `run_benchmark.sh` 获取您环境下的数据。

### 7.2 扩展性

所有实现的时间复杂度均为 O(N²)（算法本质上是二次的），差异体现在常数因子：

- **C/Rust：** 每次操作开销最小，最接近理论下界
- **Go/Java：** 运行时带来中等开销（GC、边界检查、JIT 编译）
- **Python：** 解释器分派带来极高的单次操作开销

### 7.3 价格一致性

所有实现在相同输入下产生相同的价格结果（浮点精度 epsilon ~1e-10 内），验证了跨平台算法正确性。

---

## 8. 数据库优化深度分析

### 8.1 Oracle 19c: NUMBER vs BINARY_DOUBLE

Oracle 的 `NUMBER` 类型完全在软件层面实现任意精度十进制算术。每一次算术运算（+、-、×、÷、EXP、POWER、SQRT）都要经过软件模拟层，比硬件 FPU 指令慢数个数量级。

`BINARY_DOUBLE`（IEEE 754 双精度）直接映射到 CPU FPU 寄存器，实现硬件加速计算。对于二叉树模型的紧密内层循环（数百万次浮点运算），仅此替换即可带来 **3-5 倍加速**。

**结合 intr 递推（消除 POWER() 调用），总加速比达到 18.4 倍。**

| N     | V1 NUMBER (ms/run) | V2 BINARY_DOUBLE (ms/run) | 加速比 |
|-------|:------------------:|:-------------------------:|:------:|
| 100   | 38                 | 14                        | 2.7x   |
| 500   | 820                | 75                        | 10.9x  |
| 1,000 | 3,244              | 176                       | 18.4x  |
| 2,000 | 13,078             | 717                       | 18.2x  |
| 5,000 | 82,691             | 4,526                     | 18.3x  |

### 8.2 GaussDB 9.2: NUMERIC vs float8

GaussDB 的 `NUMERIC` 与 `float8`（DOUBLE PRECISION）性能差距同样显著。虽然 GaussDB 内部在执行 `EXP`、`POWER`、`SQRT` 时会委托给 float64 计算，但结果会转换回高精度 NUMERIC 值（可达几十位小数），后续运算必须处理这些大尺寸 NUMERIC 值，产生随 N 超线性增长的累加开销。

> **重要说明：** 早期测试中，因 GaussDB 函数重载机制（同名函数同时存在 NUMERIC 和 float8 两个版本），JDBC `setDouble` 优先匹配了 float8 参数版本，导致 V1 实际执行的是 float8 版本。删除 float8 重载后，确认 V1 走的是真正的全 NUMERIC 路径，性能差距远大于此前测量值。

| N   | V1 全 NUMERIC (ms/run) | V2 float8 优化 (ms/run) | 加速比 |
|-----|:----------------------:|:----------------------:|:------:|
| 100 | 1,092                  | 920                    | 1.2x   |
| 200 | 1,515                  | 1,138                  | 1.3x   |
| 300 | 2,706                  | 1,179                  | 2.3x   |

此外，V1 (NUMERIC) **在 N >= 500 时直接溢出**（`value overflows numeric format`），而 V2 (float8) 不受此限制。

### 8.3 核心结论

> **两种优化都重要，但在不同数据库中的相对重要性不同。**
>
> - **Oracle：** 类型替换（NUMBER -> BINARY_DOUBLE）单独可提供 3-5 倍加速，结合 intr 递推达到 **18.4 倍**。NUMBER 类型是主要瓶颈。
> - **GaussDB：** intr 递推是主要差异化因素。NUMERIC -> float8 提供有意义的加成（~1.2-2.3 倍），但递推对于在高 N 时防止溢出同样至关重要。
> - **两者共同点：** intr 递推将 `POWER()` 调用减少 99%+，这是与平台无关的最重要优化。

---

## 9. 结论

1. **所有 5 种语言 + 2 种数据库产生一致的定价结果**（浮点精度 epsilon 内），验证了跨平台正确性。

2. **C 和 Rust** 提供最高的原始性能，适合低延迟定价引擎和实时风险系统。

3. **intr 递推优化**与语言和数据库无关。它将 `POWER()` 调用减少 99% 以上，是 CRR 二叉树模型任何实现中**单项影响最大的优化**。

4. **Oracle 上 BINARY_DOUBLE vs NUMBER** 提供额外 3-5 倍乘数，使组合优化达到 **18.4 倍**。

5. **GaussDB 上 float8 vs NUMERIC** 提供实质性改善（N=300 时 ~2.3 倍），且关键地避免了 NUMERIC 在 N >= 500 时的溢出问题。

6. **Python** 虽然比 C 慢 50-100 倍，但仍可用于原型验证、教学和低频应用。算法设计选择（O(1) 数组、逆向归纳）使其即使 N=10,000 也可在秒级完成。

7. **生产建议：** 涉及大量浮点运算的数据库场景（蒙特卡洛模拟、二叉树定价、数值积分等），应优先使用硬件浮点类型（Oracle `BINARY_DOUBLE`、GaussDB `float8`），避免不必要的 NUMERIC 开销。同时采用 intr 递推算法，可将性能提升一个数量级。

---

## 10. 参考文献

1. Cox, J. C., Ross, S. A., & Rubinstein, M. (1979). Option pricing: A simplified approach. *Journal of Financial Economics*, 7(3), 229-263.
2. Hull, J. C. (2018). *Options, Futures, and Other Derivatives* (10th ed.). Pearson.
3. Oracle Corporation. (2023). *Oracle Database PL/SQL Language Reference*. NUMBER vs BINARY_DOUBLE 性能特征。
4. PostgreSQL Global Development Group. (2023). *PostgreSQL 文档*, 第 8 章: 数值类型。
5. Higham, D. J. (2004). *An Introduction to Financial Option Valuation: Mathematics, Stochastics and Computation*. Cambridge University Press.

---

## 许可证

本项目仅供教育和研究目的使用。数学模型和算法基于成熟的学术文献。
