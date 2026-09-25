/*
===============================================================================
DATA CLEANING, SKILL RECOVERY, AND RELATIONAL MODELING WORKFLOW
===============================================================================

PROJECT OBJECTIVE

Before any analysis can be performed, the underlying dataset must be vetted 
enough to be real, consistent, and reliable to support filtering, 
aggregation, relationships, and future analytical queries without any data
inconsistencies affecting the results.

This project approaches the Data Analyst Job Postings dataset as a structured data-cleaning,
skill-recovery, and relational-modeling workflow.

The process begins by auditing the raw job-posting records to establish the
dataset's structure and data-quality baseline. The indentified issues are then
addressed progressively across:

    - record-level duplication;
    - data types;
    - location formatting;
    - company-name consistency;
    - skill information;
    - relational structure.

With a primary objective to transform the original wide table into three primary
analytical tables:

    jobs
        One record per unique job_id.

    companies
        One standardized record per company.

    job_skills
        Standardized job-to-skill relationships.

The overall workflow is basically focused on data preparation, rather than 
job-market analysis, to establish a cleaner and more structured foundation from 
which salary, employer, location, skill, and other analyses can also be 
performed.
*/

/*
SCOPE BOUNDARY

This project, basically, does not establish conclusions about salary trends,
skill demand, employer behavior, geographic demand, or other job-market
outcomes.

Instead, it establishes a cleaner, validated, and more structured dataset from
which those analyses can be performed in the future.
*/

/*
===============================================================================
DATASET SETUP
===============================================================================

OBSERVATION

The source dataset was acquired as a CSV containing job-posting information
across 27 fields.

Before changing the data, the source records are preserved in their raw 
state, while the same version is staged in a new table so that the original 
structure can be inspected and audited.

APPROACH

All incoming fields are initially stored as TEXT. This is intentional at the
ingestion stage: loading the source values before enforcing stricter PostgreSQL
types reduces the risk of the loosing the effectiveness of the initial import
due to unexpected source formatting.

Appropriate analytical data types will be assigned only after the source
structure and values have been inspected.
*/

CREATE TABLE raw_job_postings (
    "Unnamed: 0" TEXT,
    index_col TEXT,
    title TEXT,
    company_name TEXT,
    location TEXT,
    via TEXT,
    description TEXT,
    extensions TEXT,
    job_id TEXT,
    thumbnail TEXT,
    posted_at TEXT,
    schedule_type TEXT,
    work_from_home TEXT,
    salary TEXT,
    search_term TEXT,
    date_time TEXT,
    search_location TEXT,
    commute_time TEXT,
    salary_pay TEXT,
    salary_rate TEXT,
    salary_avg TEXT,
    salary_min TEXT,
    salary_max TEXT,
    salary_hourly TEXT,
    salary_yearly TEXT,
    salary_standardized TEXT,
    description_tokens TEXT
);


/*
The source CSV is loaded into raw_job_postings using PostgreSQL's \copy
meta-command.

Before running this command, follow the README.md report to download the 
source dataset and replace <LOCAL_CSV_PATH> with the actual location of 
the CSV file on your machine.

TECHNICAL NOTE — \copy

\copy transfers data between a client-accessible file and a PostgreSQL table.
Because it is a psql meta-command rather than ordinary SQL, this statement is
executed from the psql terminal.
*/

\copy raw_job_postings
FROM '<LOCAL_CSV_PATH>/Data Analyst Job Postings [Pay, Skills, Benefits].csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');


/*
With the source data staged, the next task is to establish the dataset's
baseline and determine whether the physical row count represents the actual
number of unique job postings.
*/


/*
===============================================================================
STAGE 1 — INITIAL DATA AUDIT
===============================================================================
*/


/*
1.1 — Inspect the Table Structure

A small sample is reviewed first to understand the table layout and the types
of information available before initiating any changes.
*/

SELECT *
FROM raw_job_postings
LIMIT 10;


/*
OBSERVATION

The source table contains 27 columns covering job identity, employer,
location, descriptions, posting metadata, salary information, and extracted
description tokens among others.

Initial inspection indicates that job_id is the most suitable field for
identifying individual job postings.
*/


/*
1.2 — Establish the Unique-Job Baseline

WHY THIS MATTERS

The number of physical rows in a job-postings dataset does not necessarily
represent the number of distinct jobs. A posting may have been captured more
than once.

Treating repeated observations as independent jobs could distort later counts,
company frequencies, salary analysis, skill frequencies, and other
aggregations.

The first quantitative check therefore compares the number of observed records
with the number of distinct job IDs.
*/

SELECT
    COUNT(job_id) AS total_job_postings,
    COUNT(DISTINCT job_id) AS unique_job_ids,
    COUNT(*) - COUNT(DISTINCT job_id) AS repeated_jobs
FROM raw_job_postings;


/*
RESULT

    Observed records:        61,953
    Distinct job IDs:        58,775

The raw table therefore contains more observations than unique job IDs.

This establishes the need to investigate the repeated job IDs before building
the analytical dataset.
*/


/*
1.3 — Check Critical Identifier Completeness

The deduplication strategy will depend on:

    job_id
        To identify repeated observations of the same posting.

    date_time
        To determine which observation should be retained.

Before using these fields for deduplication, both are checked for NULL or empty
values.
*/

SELECT *
FROM raw_job_postings
WHERE
    (job_id IS NULL OR job_id = '')
    OR
    (date_time IS NULL OR date_time = '');


/*
RESULT

The query returned 0 rows.

That means every source record contains both a usable job_id and date_time
value, which allows to allow a deterministic deduplication rule.
*/


/*
1.4 — Distinguish Repeated Job IDs from Fully Identical Rows

A repeated job_id does not necessarily mean the entire row has been duplicated.

To distinguish repeated observations from exact duplicates, all 27 source
fields are compared.
*/

SELECT
    COUNT(*) AS duplicate_rows
FROM (
    SELECT *
    FROM raw_job_postings
    GROUP BY
        "Unnamed: 0",
        index_col,
        title,
        company_name,
        location,
        via,
        description,
        extensions,
        job_id,
        thumbnail,
        posted_at,
        schedule_type,
        work_from_home,
        salary,
        search_term,
        date_time,
        search_location,
        commute_time,
        salary_pay,
        salary_rate,
        salary_avg,
        salary_min,
        salary_max,
        salary_hourly,
        salary_yearly,
        salary_standardized,
        description_tokens
    HAVING COUNT(*) > 1
) AS duplicates;


/*
RESULT

The query returned no identical duplicate groups.

INTERPRETATION

The duplication problem becomes more specific: the same job_id can occur 
repeatedly while other values associated with those observations differ.

Therefore generalized removal of identical rows would not solve the underlying issue.
The repeated job IDs need to be examined directly.
*/


/*
1.5 — Profile Repeated Job IDs

This query identifies job IDs occurring more than once and measures how often
each one appears.
*/

SELECT
    job_id,
    COUNT(*) AS occurrence_count
FROM raw_job_postings
GROUP BY job_id
HAVING COUNT(*) > 1
ORDER BY occurrence_count DESC;


/*
RESULT

    Repeated job IDs:                         984
    Highest observations for one job_id:      75

Some repeated job IDs appear only twice, while others occur many more times.

DECISION

Because these are repeated observations rather than fully identical rows, the
next stage determines which observation should represent each job_id.
*/