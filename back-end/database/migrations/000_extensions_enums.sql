CREATE TYPE expense_category AS ENUM (
    'food_dining',
    'transport',
    'shopping',
    'groceries',
    'entertainment',
    'health_medical',
    'utilities',
    'education',
    'travel',
    'personal_care',
    'subscription',
    'investment',
    'other'
);
 
CREATE TYPE input_method AS ENUM (
    'manual',
    'ocr_receipt',
    'voice'
);
 
CREATE TYPE alert_type AS ENUM (
    'gentle_suggestion',   -- 60-75% budget utilization
    'budget_warning',      -- 75-90% budget utilization
    'critical_alert',      -- >90% budget utilization
    'goal_milestone',      -- saving goal progress alert
    'location_nudge'       -- GPS-triggered spending nudge
);
 
CREATE TYPE wishlist_status AS ENUM (
    'pending',
    'purchased',
    'dismissed',
    'expired'
);
 
CREATE TYPE goal_status AS ENUM (
    'active',
    'completed',
    'cancelled'
);
 
CREATE TYPE user_role AS ENUM (
    'user',
    'admin'
);