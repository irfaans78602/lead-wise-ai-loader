-- 1. Increase EMAIL rate limits (Testing values: 50 per hour, 200 per day)
UPDATE settings SET setting_value = '50' WHERE setting_key = 'contact_email_rate_limit_max_1';
UPDATE settings SET setting_value = '200' WHERE setting_key = 'contact_email_rate_limit_max_2';

-- 2. Increase IP rate limits (Testing values: 50 per minute, 200 per hour)
UPDATE settings SET setting_value = '50' WHERE setting_key = 'contact_ip_rate_limit_max_1';
UPDATE settings SET setting_value = '200' WHERE setting_key = 'contact_ip_rate_limit_max_2';