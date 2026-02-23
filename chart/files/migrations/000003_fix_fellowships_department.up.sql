-- Fix department and job title for users with "Fellowships" department
-- For these users, the job title contains both the actual job title and department
-- separated by a comma (e.g., "GRAD TEACHING ASST, Siebel School Comp & Data Sci")
-- This migration splits them appropriately.

-- Update users where department is "Fellowships" and job_title contains a comma
UPDATE users
SET
    job_title = TRIM(SPLIT_PART(job_title, ',', 1)),
    department = TRIM(SPLIT_PART(job_title, ',', 2))
WHERE
    department = 'Fellowships'
    AND job_title LIKE '%,%'
    AND SPLIT_PART(job_title, ',', 2) != '';
