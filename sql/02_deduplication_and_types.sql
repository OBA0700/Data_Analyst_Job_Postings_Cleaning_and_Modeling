/*
===============================================================================
STAGE 2 — RECORD-LEVEL DEDUPLICATION
===============================================================================
*/


/*
2.1 — Determine the Temporal Pattern of Repeated Jobs

MIN() and MAX() are used to inspect the earliest and latest recorded date_time
for each repeated job_id.

This establishes the temporal range across which the same posting is being
observed.
*/

SELECT
    job_id,
    COUNT(*) AS repeated_count,
    MIN(date_time) AS first_seen,
    MAX(date_time) AS last_seen
FROM raw_job_postings
GROUP BY job_id
HAVING COUNT(*) > 1
ORDER BY repeated_count DESC, job_id;


/*
DECISION

The project requires one representative record per job_id.

For repeated job IDs, the most recent observation is retained. Jobs appearing
only once are preserved unchanged.

This provides a consistent and reproducible retention rule rather than
arbitrarily selecting one repeated row.
*/


/*
2.2 — Create the Unique-Job Dataset

TECHNICAL NOTE — DISTINCT ON

DISTINCT ON is a PostgreSQL-specific technique that retains one row from each
specified group.

Here:

    DISTINCT ON (job_id)
        creates one result per job ID.

    ORDER BY job_id, date_time DESC
        places the most recent observation first within each job_id.

PostgreSQL therefore retains the latest observed record for every job_id.
*/

CREATE TABLE unique_raw_job_postings AS
SELECT DISTINCT ON (job_id) *
FROM raw_job_postings
ORDER BY job_id, date_time DESC;


/*
2.3 — Validate the Deduplication

The resulting row count is compared with the number of distinct job IDs.
*/

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT job_id) AS unique_job_ids
FROM unique_raw_job_postings;


/*
RESULT

    Total rows:          58,775
    Unique job IDs:      58,775

VALIDATION

COUNT(*) now matches COUNT(DISTINCT job_id), confirming that the staging table
contains one record per job_id.

The result also reconciles with the 58,775 distinct job IDs identified before
deduplication.

With record-level duplication resolved, the next stage standardizes the
structural data types required for reliable filtering and calculations.
*/


/*
===============================================================================
STAGE 3 — DATA-TYPE AND STRUCTURAL STANDARDIZATION
===============================================================================

OBSERVATION

The source fields were deliberately imported as TEXT to simplify ingestion.
That representation is useful for staging but unsuitable as the permanent
analytical structure.

For example:

    - salary fields require numeric types for calculations;
    - work_from_home represents a logical TRUE/FALSE state;
    - date_time requires temporal semantics;
    - index_col represents an integer.

The relevant fields are therefore converted to appropriate PostgreSQL types.
*/


/*
3.1 — Convert Analytical Fields to Appropriate Data Types

TECHNICAL NOTE — USING AND TYPE CASTING

When an existing column changes type, PostgreSQL needs to know how the current
values should be interpreted in the target type.

Expressions such as:

    USING salary_avg::NUMERIC

explicitly cast the existing TEXT value into NUMERIC while the column
definition changes.

This is analytically important because a salary stored as text cannot be
reliably sorted, aggregated, or calculated as a quantitative measure.
*/

ALTER TABLE unique_raw_job_postings
    ALTER COLUMN index_col TYPE INTEGER
        USING index_col::INTEGER,

    ALTER COLUMN work_from_home TYPE BOOLEAN
        USING work_from_home::BOOLEAN,

    ALTER COLUMN date_time TYPE TIMESTAMP
        USING date_time::TIMESTAMP,

    ALTER COLUMN salary_avg TYPE NUMERIC
        USING salary_avg::NUMERIC,

    ALTER COLUMN salary_min TYPE NUMERIC
        USING salary_min::NUMERIC,

    ALTER COLUMN salary_max TYPE NUMERIC
        USING salary_max::NUMERIC,

    ALTER COLUMN salary_hourly TYPE NUMERIC
        USING salary_hourly::NUMERIC,

    ALTER COLUMN salary_yearly TYPE NUMERIC
        USING salary_yearly::NUMERIC,

    ALTER COLUMN salary_standardized TYPE NUMERIC
        USING salary_standardized::NUMERIC;


/*
3.2 — Validate the Resulting Column Types

information_schema.columns is queried to verify the resulting schema while
preserving the source column order for easier comparison.
*/

SELECT
    column_name,
    data_type
FROM information_schema.columns
WHERE table_name = 'unique_raw_job_postings'
ORDER BY ordinal_position;


/*
RESULT

All 27 columns are intact, and the targeted fields have been converted to
their intended data types.

The dataset is now unique at the job_id level and structurally formated by type. The next
stage investigates consistency within the values themselves.
*/