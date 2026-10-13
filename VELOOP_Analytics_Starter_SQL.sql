-- VELOOP Rewards Analytics Blueprint — starter SQL
-- IMPORTANT: this schema is PROPOSED, not evidence of production tables.
-- Store timestamps in UTC and define the reporting timezone in BI.
-- Amounts must include an asset/currency unit. Never sum unlike assets.

CREATE TABLE dim_users (
  user_id VARCHAR(100) PRIMARY KEY,
  registration_at TIMESTAMP NOT NULL,
  acquisition_source VARCHAR(100),
  platform VARCHAR(30),
  account_status VARCHAR(30),
  verification_status VARCHAR(30),
  onboarding_status VARCHAR(30),
  consent_status VARCHAR(30)
);

CREATE TABLE fact_sessions (
  session_id VARCHAR(100) PRIMARY KEY,
  user_id VARCHAR(100) NOT NULL REFERENCES dim_users(user_id),
  session_start TIMESTAMP NOT NULL,
  session_end TIMESTAMP,
  device VARCHAR(30),
  platform VARCHAR(30),
  entry_point VARCHAR(100),
  exit_feature VARCHAR(100),
  session_status VARCHAR(30),
  CHECK (session_end IS NULL OR session_end >= session_start)
);

CREATE TABLE fact_feature_events (
  event_id VARCHAR(100) PRIMARY KEY,
  user_id VARCHAR(100) NOT NULL REFERENCES dim_users(user_id),
  session_id VARCHAR(100) REFERENCES fact_sessions(session_id),
  event_at TIMESTAMP NOT NULL,
  event_name VARCHAR(120) NOT NULL,
  feature_name VARCHAR(100) NOT NULL,
  event_status VARCHAR(30),
  schema_version VARCHAR(30) NOT NULL,
  idempotency_key VARCHAR(200),
  source_system VARCHAR(100) NOT NULL,
  ingested_at TIMESTAMP
);

CREATE TABLE fact_task_activity (
  activity_id VARCHAR(100) PRIMARY KEY,
  user_id VARCHAR(100) NOT NULL REFERENCES dim_users(user_id),
  task_id VARCHAR(100) NOT NULL,
  session_id VARCHAR(100) REFERENCES fact_sessions(session_id),
  viewed_at TIMESTAMP,
  started_at TIMESTAMP,
  completed_at TIMESTAMP,
  task_status VARCHAR(30) NOT NULL,
  failure_reason_code VARCHAR(100),
  reward_status VARCHAR(30)
);

-- Proposed tables required for deeper product analytics. These source datasets
-- were not present in the supplied workbooks; validate business rules first.
CREATE TABLE fact_reward_ledger (
  transaction_id VARCHAR(100) PRIMARY KEY,
  user_id VARCHAR(100) NOT NULL REFERENCES dim_users(user_id),
  posted_at TIMESTAMP NOT NULL,
  transaction_type VARCHAR(30) NOT NULL,
  amount DECIMAL(20,6) NOT NULL,
  asset_code VARCHAR(30) NOT NULL,
  source_type VARCHAR(50),
  source_id VARCHAR(100),
  original_transaction_id VARCHAR(100),
  status VARCHAR(30) NOT NULL
);

CREATE TABLE fact_withdrawals (
  withdrawal_id VARCHAR(100) PRIMARY KEY,
  user_id VARCHAR(100) NOT NULL REFERENCES dim_users(user_id),
  requested_at TIMESTAMP NOT NULL,
  amount DECIMAL(20,6) NOT NULL,
  asset_code VARCHAR(30) NOT NULL,
  status VARCHAR(30) NOT NULL,
  approved_at TIMESTAMP,
  processed_at TIMESTAMP,
  rejected_at TIMESTAMP,
  rejection_reason_code VARCHAR(100)
);

CREATE TABLE fact_referrals (
  referral_id VARCHAR(100) PRIMARY KEY,
  referrer_user_id VARCHAR(100) NOT NULL REFERENCES dim_users(user_id),
  referred_user_id VARCHAR(100) NOT NULL REFERENCES dim_users(user_id),
  created_at TIMESTAMP NOT NULL,
  activated_at TIMESTAMP,
  status VARCHAR(30) NOT NULL
);

-- Example: daily active users. Approve the active-event list before production use.
SELECT CAST(event_at AS DATE) AS activity_date,
       COUNT(DISTINCT user_id) AS daily_active_users
FROM fact_feature_events
WHERE event_name IN ('feature_opened','task_started','daily_reward_claimed')
GROUP BY CAST(event_at AS DATE)
ORDER BY activity_date;

-- Example: task completion rate. Approve status mappings before production use.
SELECT
  COUNT(CASE WHEN LOWER(TRIM(task_status)) IN ('completed','complete','success') THEN 1 END) * 1.0
  / NULLIF(COUNT(CASE WHEN LOWER(TRIM(task_status)) IN ('started','completed','complete','success','failed') THEN 1 END),0)
    AS task_completion_rate
FROM fact_task_activity;

-- Run against a staging/raw events table before primary-key enforcement.
SELECT event_id, COUNT(*) AS copies
FROM staging_feature_events
GROUP BY event_id
HAVING COUNT(*) > 1;

-- Net ledger movement by user and asset. Validate reversal semantics with Finance.
SELECT user_id, asset_code,
       SUM(CASE WHEN transaction_type IN ('credit','adjustment_credit') THEN amount
                WHEN transaction_type IN ('debit','adjustment_debit','reversal') THEN -amount
                ELSE 0 END) AS net_ledger_movement
FROM fact_reward_ledger
WHERE status='posted'
GROUP BY user_id, asset_code;

-- Withdrawal processing time for paid requests with valid timestamps.
SELECT withdrawal_id, user_id,
       EXTRACT(EPOCH FROM (processed_at - requested_at))/3600.0 AS processing_hours
FROM fact_withdrawals
WHERE status='paid' AND processed_at IS NOT NULL AND processed_at >= requested_at;
