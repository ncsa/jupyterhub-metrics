-- No-op: This migration corrects data corruption and cannot be safely reversed.
-- The original "Fellowships" department value and the embedded department string
-- in job_title cannot be reconstructed without the original source data from
-- Microsoft Graph API. Re-run export_user_details_with_token.py --refresh to
-- restore user data from the source if needed.
SELECT 1;
