/*
===============================================================================
STAGE 8 — RELATIONAL MODELING
===============================================================================

The cleaned staging table still contains repeated company values and packed
skill information.

The next stages reorganize those attributes into relational structures better
suited to downstream analysis.
*/


/*
8.1 — Create the Company Reference Table

One company may appear across many job postings. Repeatedly storing the full
company name in the final analytical job structure is therefore unnecessary.

The standardized company values are extracted into a dedicated "companies"
table.

TECHNICAL NOTE — ROW_NUMBER()

ROW_NUMBER() is a window function that assigns sequential numbers according to
the specified ordering.

Here it generates a surrogate company_id for each distinct standardized
company name.
*/

CREATE TABLE companies AS
SELECT
    ROW_NUMBER() OVER (ORDER BY company_name) AS company_id,
    company_name
FROM (
    SELECT DISTINCT company_name
    FROM unique_raw_job_postings
) AS unique_companies;


/*
Enforce company-level integrity.

PRIMARY KEY ensures each "company_id" identifies one company record.

UNIQUE(company_name) prevents the same standardized company name from being
stored more than once.
*/

ALTER TABLE companies
    ADD CONSTRAINT companies_pkey
        PRIMARY KEY (company_id),
    ADD CONSTRAINT companies_company_name_unique
        UNIQUE (company_name);


/*
Validate the company reference table.
*/

SELECT
    COUNT(*) AS total_companies,
    COUNT(DISTINCT company_id) AS unique_company_ids,
    COUNT(DISTINCT company_name) AS unique_company_names
FROM companies;


/*
RESULT

    Total companies:            13,178
    Unique company IDs:         13,178
    Unique company names:       13,178

The company reference table therefore contains one record per standardized
company.
*/


/*
8.2 — Link the Cleaned Job Records to Companies

A "company_id" field is added to the cleaned staging table and populated by
matching the standardized company names.
*/

ALTER TABLE unique_raw_job_postings
ADD COLUMN company_id INTEGER;


UPDATE unique_raw_job_postings
SET company_id = companies.company_id
FROM companies
WHERE unique_raw_job_postings.company_name = companies.company_name;


/*
Validate that every cleaned job resolved to a company.
*/

SELECT
    COUNT(*) AS unmatched_jobs
FROM unique_raw_job_postings
WHERE company_id IS NULL;


/*
RESULT

    unmatched_jobs = 0

Every cleaned job record successfully resolves to a company in the new
reference table.

This validation is necessary so the final jobs table can replace the repeated
"company_name" attribute with its relational company identifier.
*/


/*
8.3 — Create the Final jobs Table

The jobs table retains the job-level attributes required for future analysis
while representing the employer through "company_id".
*/

CREATE TABLE jobs AS
SELECT
    job.job_id,
    job.title,
    company.company_id,
    job.location,
    job.date_time,
    job.schedule_type,
    job.work_from_home,
    job.salary,
    job.salary_pay,
    job.salary_rate,
    job.salary_avg,
    job.salary_min,
    job.salary_max,
    job.salary_hourly,
    job.salary_yearly,
    job.salary_standardized,
    job.description,
    job.via
FROM unique_raw_job_postings AS job
JOIN companies AS company
    ON job.company_name = company.company_name;


/*
The resulting relationship is:

    one company -> many jobs
*/


/*
8.4 — Validate the jobs Table
*/

SELECT
    COUNT(*) AS total_jobs,
    COUNT(DISTINCT job_id) AS unique_job_ids,
    COUNT(*) FILTER (
        WHERE company_id IS NULL
    ) AS jobs_without_company_id
FROM jobs;


/*
EXPECTED AND CONFIRMED IN FINAL INTEGRITY CHECK

    Total jobs:                58,775
    Unique job IDs:            58,775
    Jobs without company ID:        0
*/


/*
8.5 — Enforce Job-Level Relational Integrity

PRIMARY KEY(job_id) enforces one record per job.

FOREIGN KEY(company_id) ensures every company identifier stored in jobs
corresponds to an existing record in companies.

This moves the company relationship from a text-matching assumption to a
database-enforced integrity rule.
*/

ALTER TABLE jobs
ADD CONSTRAINT jobs_pkey
    PRIMARY KEY (job_id),
ADD CONSTRAINT jobs_company_id_fkey
    FOREIGN KEY (company_id)
    REFERENCES companies(company_id);


/*
===============================================================================
STAGE 9 — BUILD THE JOB-SKILL RELATIONSHIP
===============================================================================

OBSERVATION

A job can require multiple skills, while the same standardized skill can occur
across many jobs.

Keeping multiple skills packed inside description_tokens would make future
skill-level filtering, grouping, and aggregation unnecessarily difficult.

Conceptually, the data contains a many-to-many relationship:

    one job   -> many skills
    one skill -> many jobs

The job_skills table resolves that relationship into individual job-to-skill
records.
*/


/*
9.1 — Create the job_skills Junction Table

TECHNICAL NOTE — BIGSERIAL

BIGSERIAL automatically generates sequential integer identifiers for
individual relationship records.

TECHNICAL NOTE — UNIQUE(job_id, skill)

The composite UNIQUE constraint prevents the same standardized skill from being
assigned to the same job more than once.
*/

CREATE TABLE job_skills (
    job_skill_id BIGSERIAL PRIMARY KEY,
    job_id TEXT NOT NULL,
    skill TEXT NOT NULL,
    FOREIGN KEY (job_id) REFERENCES jobs(job_id),
    UNIQUE (job_id, skill)
);


/*
9.2 — Normalize description_tokens Before Extraction

The remaining "[]" values are converted to SQL NULL because "[]" is a textual
representation of an empty collection rather than an actual skill value.

For populated records, the surrounding square brackets are removed so the
remaining comma-delimited values can be split into individual skills.
*/

UPDATE unique_raw_job_postings
SET description_tokens =
    CASE
        WHEN description_tokens = '[]' THEN NULL
        ELSE TRIM(BOTH '[]' FROM description_tokens)
    END;


/*
9.3 — Populate the job_skills Junction Table

TECHNICAL NOTE — STRING_TO_ARRAY()

STRING_TO_ARRAY() converts the comma-delimited description_tokens string into
a PostgreSQL array.

TECHNICAL NOTE — UNNEST()

UNNEST() expands the resulting array into individual rows.

Together:

    UNNEST(STRING_TO_ARRAY(...))

transforms multiple skills packed inside one field into separate relational
records.

Each extracted source skill is then matched to "skill_mapping" table so the value
written to job_skills uses the standardized skill name.

SELECT DISTINCT provides an additional safeguard against repeated job-skill
pairs before insertion, while UNIQUE(job_id, skill) enforces the same rule at
the table level.
*/

INSERT INTO job_skills (job_id, skill)
SELECT DISTINCT
    job.job_id,
    skill_mapping.standardized_name
FROM unique_raw_job_postings AS job,
     UNNEST(
         STRING_TO_ARRAY(job.description_tokens, ', ')
     ) AS extracted_skill
JOIN skill_mapping
    ON TRIM(BOTH '''' FROM extracted_skill)
       = skill_mapping.source_skill_name
WHERE job.description_tokens IS NOT NULL;


/*
WHY THIS MATTERS

The transformation changes skill information from a packed text representation
into a relational structure suitable for future questions such as:

    - Which standardized skills occur across jobs?
    - How many jobs reference a particular skill?
    - Which skills coexist within job postings?
*/


/*
9.4 — Validate the Final job_skills Table
*/

SELECT
    COUNT(*) AS total_skill_records,
    COUNT(DISTINCT job_id) AS jobs_with_skills,
    COUNT(DISTINCT skill) AS unique_skills
FROM job_skills;


/*
RESULT

    Job-skill relationships:       190,002
    Jobs represented with skills:   46,560
    Unique standardized skills:        125

The skill information has therefore been transformed into 190,002 individual
job-to-skill relationships covering 46,560 jobs and 125 standardized skills.
*/


/*
9.5 — Check for Duplicate Job-Skill Relationships

Although the table already contains UNIQUE(job_id, skill), this query provides
an explicit validation that no duplicate relationship exists in the populated
data.
*/

SELECT
    RIGHT(job_id, 10) AS job_id,
    skill,
    COUNT(*) AS occurrences
FROM job_skills
GROUP BY
    job_id,
    skill
HAVING COUNT(*) > 1;


/*
RESULT

The query returned 0 rows.

No duplicate (job_id, skill) relationships are present in the final table.

The explicit validation result agrees with the UNIQUE(job_id, skill)
constraint, which protects the same integrity rule at the database level.
*/
