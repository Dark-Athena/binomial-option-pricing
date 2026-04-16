#!/usr/bin/env bash
# ============================================================================
# run_benchmark.sh - 一键编译、执行、跑分对比并生成性能报告
#
# 用法:
#   chmod +x run_benchmark.sh
#   ./run_benchmark.sh              # 使用默认参数 (N=1000)
#   ./run_benchmark.sh 5000         # 指定 N=5000
#   ./run_benchmark.sh 5000 100     # N=5000, 每种语言跑 100 次
#
# 输出:
#   report/benchmark_results.csv    - 结构化数据
#   report/benchmark_report.md      - Markdown 格式报告
#
# 依赖:
#   - gcc / clang (C)
#   - Go 1.16+ (Go)
#   - JDK 8+ (Java)
#   - Python 3.6+ (Python)
#   - Rust toolchain (Rust)
#
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ---- 参数 ----
N="${1:-1000}"
RUNS="${2:-20}"
REPORT_DIR="$SCRIPT_DIR/report"
mkdir -p "$REPORT_DIR"

echo "============================================================"
echo "  二叉树期权定价模型 - 多语言性能基准测试"
echo "============================================================"
echo "  N (二叉树步数)  : $N"
echo "  RUNS (每种跑分)  : $RUNS"
echo "  输出目录         : $REPORT_DIR/"
echo "  日期             : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  系统             : $(uname -srm)"
echo "============================================================"
echo ""

# ---- 公共参数 ----
S0=100; K=100; T=1.0; R=0.05; SIGMA=0.2
CSV_HEADER="Language,Impl,N,Runs,Total_ms,Avg_ms,Price_AC,Price_AP,Price_EC,Price_EP"
CSV_FILE="$REPORT_DIR/benchmark_results.csv"

# ---- 1. C (V1 + V2) ----
echo "[1/5] 编译 C ..."
if command -v gcc &>/dev/null; then
    CC=gcc
elif command -v clang &>/dev/null; then
    CC=clang
else
    echo "  [SKIP] 未找到 gcc/clang"
    CC=""
fi

if [ -n "$CC" ]; then
    $CC -O2 -o "$REPORT_DIR/c_v1" src/c/option_pricing.c -lm 2>/dev/null
    echo "  编译完成: c_v1"
    # 注意: C 源码内已包含 intr 递推优化 (V2)
    # 这里直接运行 C V1 (power-based) 和 C V2 (intr-based) 的对比
    # 由于 C 源码只有一版 (已优化), 直接跑
fi

# ---- 2. Go (V1 + V2) ----
echo "[2/5] 编译 Go ..."
if command -v go &>/dev/null; then
    cd src/go
    go build -o "$REPORT_DIR/go_v1" option_pricing.go 2>/dev/null
    echo "  编译完成: go_v1"
    cd "$SCRIPT_DIR"
else
    echo "  [SKIP] 未找到 go"
fi

# ---- 3. Java (V1 + V2) ----
echo "[3/5] 编译 Java ..."
if command -v javac &>/dev/null; then
    javac -d "$REPORT_DIR" src/java/BinomialOptionPricing.java 2>/dev/null
    echo "  编译完成: BinomialOptionPricing.class"
else
    echo "  [SKIP] 未找到 javac"
fi

# ---- 4. Python ----
echo "[4/5] 检查 Python ..."
if command -v python3 &>/dev/null; then
    echo "  Python3 可用"
else
    echo "  [SKIP] 未找到 python3"
fi

# ---- 5. Rust (V1 + V2) ----
echo "[5/5] 编译 Rust ..."
if command -v rustc &>/dev/null; then
    rustc -O -o "$REPORT_DIR/rust_v1" src/rust/option_pricing.rs 2>/dev/null
    echo "  编译完成: rust_v1"
else
    echo "  [SKIP] 未找到 rustc"
fi

echo ""
echo "============================================================"
echo "  开始跑分 (每种语言 x ${RUNS} 次, N=${N})"
echo "============================================================"
echo ""

# ---- 写 CSV ----
echo "$CSV_HEADER" > "$CSV_FILE"

run_test() {
    local lang="$1"
    local impl="$2"
    local cmd="$3"
    local label="${lang}_${impl}"

    if [ -z "$cmd" ] || [ ! -x "$cmd" ] && ! command -v "$cmd" &>/dev/null; then
        echo "  [SKIP] $label"
        return
    fi

    echo "  测试: $label ..."

    # AC
    local start end
    start=$(date +%s%3N 2>/dev/null || python3 -c "import time;print(int(time.time()*1000))")
    for i in $(seq 1 "$RUNS"); do
        if [[ "$cmd" == *.py ]]; then
            python3 "$cmd" "$S0" "$K" "$T" "$R" "$SIGMA" "$N" 1 1 >/dev/null 2>&1
        else
            "$cmd" "$S0" "$K" "$T" "$R" "$SIGMA" "$N" 1 1 >/dev/null 2>&1
        fi
    done
    end=$(date +%s%3N 2>/dev/null || python3 -c "import time;print(int(time.time()*1000))")
    local total_ac=$((end - start))

    # AP
    start=$(date +%s%3N 2>/dev/null || python3 -c "import time;print(int(time.time()*1000))")
    for i in $(seq 1 "$RUNS"); do
        if [[ "$cmd" == *.py ]]; then
            python3 "$cmd" "$S0" "$K" "$T" "$R" "$SIGMA" "$N" 0 1 >/dev/null 2>&1
        else
            "$cmd" "$S0" "$K" "$T" "$R" "$SIGMA" "$N" 0 1 >/dev/null 2>&1
        fi
    done
    end=$(date +%s%3N 2>/dev/null || python3 -c "import time;print(int(time.time()*1000))")
    local total_ap=$((end - start))

    # EC
    start=$(date +%s%3N 2>/dev/null || python3 -c "import time;print(int(time.time()*1000))")
    for i in $(seq 1 "$RUNS"); do
        if [[ "$cmd" == *.py ]]; then
            python3 "$cmd" "$S0" "$K" "$T" "$R" "$SIGMA" "$N" 1 0 >/dev/null 2>&1
        else
            "$cmd" "$S0" "$K" "$T" "$R" "$SIGMA" "$N" 1 0 >/dev/null 2>&1
        fi
    done
    end=$(date +%s%3N 2>/dev/null || python3 -c "import time;print(int(time.time()*1000))")
    local total_ec=$((end - start))

    # EP
    start=$(date +%s%3N 2>/dev/null || python3 -c "import time;print(int(time.time()*1000))")
    for i in $(seq 1 "$RUNS"); do
        if [[ "$cmd" == *.py ]]; then
            python3 "$cmd" "$S0" "$K" "$T" "$R" "$SIGMA" "$N" 0 0 >/dev/null 2>&1
        else
            "$cmd" "$S0" "$K" "$T" "$R" "$SIGMA" "$N" 0 0 >/dev/null 2>&1
        fi
    done
    end=$(date +%s%3N 2>/dev/null || python3 -c "import time;print(int(time.time()*1000))")
    local total_ep=$((end - start))

    local total=$((total_ac + total_ap + total_ec + total_ep))
    local avg=$(python3 -c "print(f'{$total / ($RUNS * 4):.1f}')")

    # 获取价格 (单次运行)
    local price_ac price_ap price_ec price_ep
    if [[ "$cmd" == *.py ]]; then
        price_ac=$(python3 "$cmd" "$S0" "$K" "$T" "$R" "$SIGMA" "$N" 1 1 2>/dev/null | tail -1)
        price_ap=$(python3 "$cmd" "$S0" "$K" "$T" "$R" "$SIGMA" "$N" 0 1 2>/dev/null | tail -1)
        price_ec=$(python3 "$cmd" "$S0" "$K" "$T" "$R" "$SIGMA" "$N" 1 0 2>/dev/null | tail -1)
        price_ep=$(python3 "$cmd" "$S0" "$K" "$T" "$R" "$SIGMA" "$N" 0 0 2>/dev/null | tail -1)
    else
        price_ac=$("$cmd" "$S0" "$K" "$T" "$R" "$SIGMA" "$N" 1 1 2>/dev/null | tail -1)
        price_ap=$("$cmd" "$S0" "$K" "$T" "$R" "$SIGMA" "$N" 0 1 2>/dev/null | tail -1)
        price_ec=$("$cmd" "$S0" "$K" "$T" "$R" "$SIGMA" "$N" 1 0 2>/dev/null | tail -1)
        price_ep=$("$cmd" "$S0" "$K" "$T" "$R" "$SIGMA" "$N" 0 0 2>/dev/null | tail -1)
    fi

    # 清理价格输出 (取数字部分)
    price_ac=$(echo "$price_ac" | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "0")
    price_ap=$(echo "$price_ap" | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "0")
    price_ec=$(echo "$price_ec" | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "0")
    price_ep=$(echo "$price_ep" | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "0")

    local total_ms=$((total))
    echo "$lang,$impl,$N,$RUNS,$total_ms,$avg,$price_ac,$price_ap,$price_ec,$price_ep" >> "$CSV_FILE"
    echo "    Total: ${total}ms  Avg: ${avg}ms/run  AC=${price_ac} AP=${price_ap}"
}

echo ""
# C
[ -x "$REPORT_DIR/c_v1" ] && run_test "C" "optimized" "$REPORT_DIR/c_v1" || echo "  [SKIP] C"

# Go
[ -x "$REPORT_DIR/go_v1" ] && run_test "Go" "V1" "$REPORT_DIR/go_v1" || echo "  [SKIP] Go"

# Java
if [ -f "$REPORT_DIR/BinomialOptionPricing.class" ]; then
    run_test "Java" "V1" "java"  # Java 特殊处理
fi

# Python
if command -v python3 &>/dev/null; then
    run_test "Python" "CPython" "src/python/option_pricing.py"
fi

# Rust
[ -x "$REPORT_DIR/rust_v1" ] && run_test "Rust" "V1" "$REPORT_DIR/rust_v1" || echo "  [SKIP] Rust"

echo ""
echo "============================================================"
echo "  测试完成! 结果已写入: $CSV_FILE"
echo "============================================================"
echo ""

# ---- 生成 Markdown 报告 ----
python3 -c "
import csv, sys
from datetime import datetime

rows = []
with open('$CSV_FILE') as f:
    reader = csv.DictReader(f)
    for r in reader:
        rows.append(r)

if not rows:
    print('No data'); sys.exit(0)

md = []
md.append('# 二叉树期权定价模型 - 多语言性能基准报告')
md.append('')
md.append('> **生成时间:** ' + datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
md.append('> **N (二叉树步数):** $N')
md.append('> **每种语言运行次数:** $RUNS')
md.append('> **系统:** ' + '$(uname -srm)')
md.append('> **参数:** S0=$S0, K=$K, T=$T, r=$R, sigma=$SIGMA')
md.append('')
md.append('## 测试结果汇总')
md.append('')
md.append('| 语言 | 实现 | 总耗时(ms) | 平均耗时(ms/run) | AC 价格 | AP 价格 | EC 价格 | EP 价格 |')
md.append('|------|------|:----------:|:----------------:|:--------:|:--------:|:--------:|:--------:|')
for r in rows:
    md.append(f\"| {r['Language']} | {r['Impl']} | {r['Total_ms']} | {r['Avg_ms']} | {r['Price_AC']} | {r['Price_AP']} | {r['Price_EC']} | {r['Price_EP']} |\")
md.append('')

# 价格一致性检查
prices = [(r['Language'], r['Price_AC']) for r in rows if r['Price_AC'] != '0']
if len(prices) >= 2:
    vals = [float(p[1]) for p in prices]
    diff = max(vals) - min(vals)
    md.append('## 价格一致性验证')
    md.append('')
    if diff < 0.01:
        md.append(f'所有语言实现的美式看涨(AC)价格差异 < 0.01 ({diff:.6f}), 计算结果一致。')
    else:
        md.append(f'**警告:** 美式看涨价格差异较大: {diff:.6f}')
        for lang, val in prices:
            md.append(f'- {lang}: {val}')
    md.append('')

md.append('---')
md.append('')
md.append('*本报告由 run_benchmark.sh 自动生成*')

report_path = '$REPORT_DIR/benchmark_report.md'
with open(report_path, 'w') as f:
    f.write('\\n'.join(md))
print(f'报告已生成: {report_path}')
"

echo ""
echo "============================================================"
echo "  Markdown 报告: $REPORT_DIR/benchmark_report.md"
echo "  CSV 数据:      $CSV_FILE"
echo "============================================================"
