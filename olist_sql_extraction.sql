create database if not exists olist_analysis
default character set utf8mb4
default collate utf8mb4_general_ci;

use olist_analysis;

CREATE TABLE IF NOT EXISTS olist_orders_dataset (
    order_id VARCHAR(50) PRIMARY KEY,
    customer_id VARCHAR(50),
    order_status VARCHAR(20),
    order_purchase_timestamp VARCHAR(50),
    order_approved_at VARCHAR(50),
    order_delivered_carrier_date VARCHAR(50),
    order_delivered_customer_date VARCHAR(50),
    order_estimated_delivery_date VARCHAR(50)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS olist_order_items_dataset (
    order_id VARCHAR(50),
    order_item_id INT,
    product_id VARCHAR(50),
    seller_id VARCHAR(50),
    shipping_limit_date VARCHAR(50),
    price DECIMAL(10,2),
    freight_value DECIMAL(10,2)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS olist_order_reviews_dataset (
    review_id VARCHAR(50),
    order_id VARCHAR(50),
    review_score INT,
    review_comment_title VARCHAR(255),
    review_comment_message TEXT,
    review_creation_date VARCHAR(50),
    review_answer_timestamp VARCHAR(50)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS olist_customers_dataset (
    customer_id VARCHAR(50) PRIMARY KEY,
    customer_unique_id VARCHAR(50),
    customer_zip_code_prefix VARCHAR(10),
    customer_city VARCHAR(50),
    customer_state VARCHAR(10)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

with order_items as (select order_id,sum(price) total_price,sum(freight_value) total_freight
from olist_order_items_dataset
group by order_id)
,order_reviews as (select order_id,avg(review_score) review_score
from olist_order_reviews_dataset
group by order_id)
,customer_order as (select c.customer_id,customer_unique_id,customer_state,order_id,order_purchase_timestamp,order_delivered_customer_date,order_estimated_delivery_date
from olist_customers_dataset c
join olist_orders_dataset o
on o.customer_id=c.customer_id)
select c.order_id,total_price,total_freight,customer_unique_id,customer_state,order_purchase_timestamp,order_delivered_customer_date,order_estimated_delivery_date,review_score
from order_items i
join order_reviews r
on i.order_id=r.order_id
join customer_order c
on r.order_id=c.order_id;


