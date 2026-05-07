-- =============================================================
-- V1: schema khởi đầu
-- =============================================================

CREATE TABLE category (
    code        VARCHAR(32) PRIMARY KEY,
    label_vi    VARCHAR(64) NOT NULL,
    label_en    VARCHAR(64) NOT NULL,
    color_hex   CHAR(7)     NOT NULL,
    sort_order  INT         NOT NULL DEFAULT 0,
    is_income   BOOLEAN     NOT NULL DEFAULT FALSE
);

INSERT INTO category(code, label_vi, label_en, color_hex, sort_order, is_income) VALUES
    ('food',          'Ăn uống',       'Food',          '#ef4444', 10, FALSE),
    ('transport',     'Di chuyển',     'Transport',     '#3b82f6', 20, FALSE),
    ('utilities',     'Tiện ích',      'Utilities',     '#10b981', 30, FALSE),
    ('bills',         'Hoá đơn',       'Bills',         '#f59e0b', 40, FALSE),
    ('shopping',      'Mua sắm',       'Shopping',      '#ec4899', 50, FALSE),
    ('entertainment', 'Giải trí',      'Entertainment', '#8b5cf6', 60, FALSE),
    ('salary',        'Lương',         'Salary',        '#22c55e', 70, TRUE),
    ('transfer',      'Chuyển khoản',  'Transfer',      '#6b7280', 80, FALSE),
    ('others',        'Khác',          'Others',        '#94a3b8', 99, FALSE);

CREATE TABLE import_batch (
    id              BIGSERIAL PRIMARY KEY,
    file_name       VARCHAR(255) NOT NULL,
    bank_code       VARCHAR(16),
    row_count       INT          NOT NULL DEFAULT 0,
    created_count   INT          NOT NULL DEFAULT 0,
    skipped_count   INT          NOT NULL DEFAULT 0,
    error_count     INT          NOT NULL DEFAULT 0,
    status          VARCHAR(16)  NOT NULL,
    error_message   TEXT,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE transaction (
    id              BIGSERIAL PRIMARY KEY,
    occurred_on     DATE        NOT NULL,
    amount_vnd      BIGINT      NOT NULL,
    description_raw TEXT        NOT NULL,
    merchant        VARCHAR(255),
    category_code   VARCHAR(32) NOT NULL REFERENCES category(code),
    category_source VARCHAR(16) NOT NULL,
    bank_code       VARCHAR(16),
    import_batch_id BIGINT      REFERENCES import_batch(id),
    dedup_hash      CHAR(64)    NOT NULL,
    metadata        JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uk_transaction_dedup UNIQUE (dedup_hash),
    CONSTRAINT ck_transaction_category_source
        CHECK (category_source IN ('AI','USER','RULE'))
);

CREATE INDEX ix_transaction_occurred_on ON transaction(occurred_on);
CREATE INDEX ix_transaction_category    ON transaction(category_code);
CREATE INDEX ix_transaction_merchant    ON transaction(merchant);

CREATE TABLE merchant_category_cache (
    merchant_normalized VARCHAR(255) PRIMARY KEY,
    category_code       VARCHAR(32)      NOT NULL REFERENCES category(code),
    confidence          DOUBLE PRECISION,
    sample_count        INT              NOT NULL DEFAULT 1,
    user_confirmed      BOOLEAN          NOT NULL DEFAULT FALSE,
    last_seen_at        TIMESTAMPTZ      NOT NULL DEFAULT now()
);
