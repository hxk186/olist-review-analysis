# Olist 电商平台用户评价归因分析

> 从"运费假设"到"超时预警"——用数据推翻业务方初始假设，定位差评真实归因

## 一、项目背景

Olist 是巴西最大的电商平台。平台数据显示，在已完成交付的订单中，**1–2 分差评占比约 12.77%**。业务方初步推测"运费过高"是差评主因，但该假设未经过数据验证。

**分析目标**：基于真实订单数据排查差评核心因素，输出可落地的运营优化方向。

## 二、数据与技术栈

| 项目 | 说明 |
|---|---|
| 数据来源 | [Olist Brazilian E-Commerce Public Dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)（Kaggle 公开数据集） |
| 数据规模 | 4 张一对多关联表，原始记录十万级 |
| 数据库 | MySQL（DataGrip） |
| 分析工具 | Python 3 · Pandas · Matplotlib · Jupyter Notebook |

涉及 4 张表：`olist_orders_dataset`、`olist_order_items_dataset`、`olist_order_reviews_dataset`、`olist_customers_dataset`

## 三、分析流程

### 3.1 数据提取（SQL）

**难点 1：时间格式不兼容**
CSV 中时间字段含斜杠（如 `2017/10/02`），直接导入 `DATETIME` 会报错。

> **策略**：建表时所有时间字段统一设为 `VARCHAR(50)` 接收，进入 Pandas 后用 `to_datetime()` 转换为标准格式——即在工程约束下做一次"降级接收 + 下游补偿"。

**难点 2：一对多关联导致数据膨胀**
一个订单含多件商品（订单明细表一对多），且可能有多次评价（评价表一对多）。若直接 JOIN，行数会成倍膨胀，导致金额被重复累加。

> **策略**：使用 CTE 分步聚合后再关联——

```sql
with order_items as (
    select order_id, sum(price) total_price, sum(freight_value) total_freight
    from olist_order_items_dataset group by order_id
),
order_reviews as (
    select order_id, avg(review_score) review_score
    from olist_order_reviews_dataset group by order_id
)
select ...
from order_items i
join order_reviews r on i.order_id = r.order_id
join customer_order c on r.order_id = c.order_id;
```

先按 `order_id` 分组 `SUM()` 金额与运费、`AVG()` 评分，再与客户表、订单表 JOIN，构建订单粒度宽表。

### 3.2 数据清洗与特征工程（Pandas）

```python
# 剔除未送达订单
df = df.dropna(subset='order_delivered_customer_date')
# 剔除运输天数异常值 & 约束运费占比合理范围
df = df[df['运输天数'] > 0]
df = df[df['运费占比'] <= 1]

# 衍生核心指标
df['运费占比'] = df['total_freight'] / (df['total_price'] + df['total_freight'])
df['运输天数'] = (df['order_delivered_customer_date'] - df['order_purchase_timestamp']).dt.days
df['超时天数'] = (df['order_delivered_customer_date'] - df['order_estimated_delivery_date']).dt.days

# 业务分箱（以 ±1000 替代 ±∞ 作为边界，确保输出有序 Categorical、图表按时间序列排列）
df['送达情况'] = pd.cut(df['超时天数'], bins=[-1000, 0, 3, 7, 15, 1000],
                       labels=['准时','超时1-3天','超时3-7天','超时7-15天','超时15天以上'])
df['运费档位'] = pd.cut(df['运费占比'], bins=[-1, 0, 0.1, 0.3, 1],
                       labels=['免邮','0-10%','10-30%','30%以上'])
```

### 3.3 分析一：验证假设——运费并非元凶

按运费档位分组计算平均评分：

| 运费档位 | 免邮 | 0-10% | 10-30% | 30% 以上 |
|---|---|---|---|---|
| 平均评分 | 4.39 | 4.20 | 4.16 | 4.11 |

**极差仅 0.28 分**——若运费真是差评诱因，评分应随运费档位显著下滑。

进一步以 `crosstab` 做「送达情况 × 运费档位」双变量交叉，排除交互影响：即便在超时 3-7 天档位下，四个运费档位评分（2.00 / 2.06 / 2.14 / 2.06）依然接近，**双重印证运费与差评无实质关联，初始假设被证伪**。

![不同运费档位对购物评分的影响](figures/01_运费档位与平均评分.png)

### 3.4 分析二：锁定真凶——物流超时

按超时天数分档计算差评率（评分 ≤ 2 分）：

| 送达情况 | 准时 | 超时 1-3 天 | 超时 3-7 天 | 超时 7-15 天 | 超时 15 天以上 |
|---|---|---|---|---|---|
| 差评率 | **9.2%** | 32.2% | **67.6%** | **79.9%** | 78.1% |

![物流超时天数对差评率的影响](figures/02_超时天数与差评率.png)

**关键发现**：
1. **"超时 3 天"是差评率断崖临界点**——从准时送达的 9.2% 跃升至 67.6%，**约 7 倍**；
2. 超时 1-3 天时差评率已达 32.2%，说明用户对延迟的容忍窗口极短；
3. 超时 7-15 天达到峰值 79.9%。

**边界条件的主动识别**：超时 15 天以上差评率反而微降至 78.1%。这并非噪声，可能源于**幸存者偏差**——极端延迟订单中大量顾客已取消或申请退款，剩余"已送达且被评价"样本的结构发生变化。这提示该档位的结论需谨慎外推。

## 四、业务建议

1. **资源重配**：数据证明运费非差评元凶，建议运营资源从"运费优化"转向"物流履约保障"。
2. **建立超时预警机制**：以"超时 3 天"为红线；当系统**预测订单可能超时 2 天**时，自动触发客服前置干预并发放补偿券，将差评扼杀在发生之前。
3. **承运商末位淘汰**：对超时率显著高于行业均值的物流承运商执行末位淘汰，纳入考核体系。

## 五、项目收获与局限

**收获**：
- 掌握了「一对多关联表的聚合前置」这一避免数据膨胀的核心 SQL 模式；
- 建立了「业务假设 → 数据验证 → 证伪 → 再定位 → 落地建议」的完整分析闭环；
- 理解到**主动指出结论的边界条件**（如小样本、幸存者偏差）比强行给出完美结论更重要。

**局限与改进方向**：
- 差评归因仅覆盖了运费与超时两个维度，未纳入商品品类、卖家质量、评论文本情感等变量；
- 可进一步引入逻辑回归 / 决策树做多因素归因，量化各因素的贡献度；
- `review_score` 使用了 `AVG()` 处理多次评价，可对比"取最后一次评价"的结果稳健性。

## 六、文件说明

```
├── olist_sql_extraction.sql        # 建表语句 + CTE 分步聚合查询
├── Olist_Project_Final.ipynb       # 完整分析 Notebook（含全部代码与输出）
├── Olist_Project_Final.pdf         # 导出报告
└── figures/                        # 分析图表
    ├── 01_运费档位与平均评分.png
    └── 02_超时天数与差评率.png
```

---

**作者**：黄鑫康 · 集美大学 金融学 · [GitHub](https://github.com/your-username) · 2075777177@qq.com
