-- Add college column to users table
-- College information from Microsoft Graph API

ALTER TABLE users ADD COLUMN IF NOT EXISTS college TEXT;

-- Add column comment for college
COMMENT ON COLUMN users.college IS 'User college/school from Microsoft Graph API';

-- Verification query
SELECT email, full_name, department, college, job_title
FROM users
LIMIT 5;
