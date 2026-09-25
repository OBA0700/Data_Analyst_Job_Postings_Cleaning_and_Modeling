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


/*
===============================================================================
STAGE 4 — LOCATION VALUE CONSISTENCY
===============================================================================
*/


/*
4.1 — Inspect Location Values and Their Frequency

The location field is first profiled without initially assuming the 
presence of errors from different representations.
*/

SELECT
    location,
    COUNT(*) AS job_count
FROM unique_raw_job_postings
GROUP BY location
ORDER BY job_count DESC;


/*
OBSERVATION

The field contains several representations such as "Anywhere", "United States", 
and other geographic values.

Different location labels are not automatically data-quality problems. Hence,
rather than forcing them into a new geographic hierarchy without supporting 
evidence, the next query tests for objective string-formatting inconsistencies.
*/


/*
4.2 — Diagnose Location Formatting

CASE classifies the location values into several potential formatting conditions.
*/

SELECT
    CASE
        WHEN location IS NULL THEN 'NULL'
        WHEN location = '' THEN 'Empty string'
        WHEN TRIM(location) = '' THEN 'Whitespace only'
        WHEN location <> TRIM(location) THEN 'Leading/trailing whitespace'
        ELSE 'No formatting issue'
    END AS location_issue,
    COUNT(*) AS job_count
FROM unique_raw_job_postings
GROUP BY location_issue
ORDER BY job_count DESC;


/*
RESULT

    Rows with leading/trailing whitespace:    36,571
    NULL location values:                         37

WHY THIS MATTERS

Leading or trailing whitespace can cause visually identical locations to
behave as different strings during grouping, filtering, joins, and distinct
counts.

The 37 NULL values is treated as a different situation because some job positngs
can genuinely contain no specified location value. 

DECISION

The confirmed whitespace inconsistency will be corrected.

The genuine NULL values will be preserved rather than replaced with invented
location information.
*/


/*
4.3 — Remove Leading and Trailing Location Whitespace

TECHNICAL NOTE — TRIM

TRIM() removes unwanted characters from the beginning and end of a string.
Here, it corrects confirmed formatting inconsistencies without altering the
meaning or geographic granularity of the location value.
*/

UPDATE unique_raw_job_postings
SET location = TRIM(location)
WHERE location <> TRIM(location);


/*
4.4 — Validate the Location Cleaning
*/

SELECT
    COUNT(*) AS whitespace_remaining
FROM unique_raw_job_postings
WHERE location <> TRIM(location);


/*
RESULT

    whitespace_remaining = 0

All identified leading/trailing location whitespace has been removed, while
the 37 genuinely missing locations remain preserved as NULL.
*/


/*
===============================================================================
STAGE 5 — COMPANY-NAME CONSISTENCY
===============================================================================
*/


/*
5.1 — Check Company Names for Whitespace
*/

SELECT
    COUNT(*) AS whitespace_error_count
FROM unique_raw_job_postings
WHERE company_name <> TRIM(company_name);


/*
RESULT

No company-name whitespace inconsistencies were detected.
*/


/*
5.2 — Check for Missing Company Names
*/

SELECT
    COUNT(*) AS missing_company_name
FROM unique_raw_job_postings
WHERE company_name IS NULL
   OR company_name = '';


/*
RESULT

No NULL or empty company names were detected.

Since basic completeness and whitespace are not found, the investigation
moves to whether equivalent companies are represented under different letter
cases.
*/


/*
5.3 — Inspect Companies Appearing Across Multiple Job Records

Repeated company names are expected because one employer may post more that one 
jobs.
This query helps to establish the repeated-company pattern before testing for 
naming variations.
*/

SELECT
    company_name,
    COUNT(*) AS job_count
FROM unique_raw_job_postings
GROUP BY company_name
HAVING COUNT(*) > 1
ORDER BY job_count DESC;


/*
OBSERVATION

Multiple companies appear across many job records. Upwork, for example,
appears in 7,533 records.

The important question is not whether a company appears repeatedly, but whether
the same company is being split into multiple similar entities because of
letter-case differences.
*/


/*
5.4 — Detect Case-Based Company-Name Variations

LOWER() creates a common comparison form while COUNT(DISTINCT company_name)
measures how many original representations occur for that normalized value.
*/

SELECT
    LOWER(company_name) AS company_name_normalized,
    COUNT(DISTINCT company_name) AS name_variations
FROM unique_raw_job_postings
GROUP BY company_name_normalized
HAVING COUNT(DISTINCT company_name) > 1
ORDER BY name_variations DESC;


/*
The result confirms that some equivalent company names differ only by
capitalization.

The next query displays the different representation versions directly.
*/


/*
5.5 — Inspect the Actual Case Variations

TECHNICAL NOTE — STRING_AGG

STRING_AGG() combines values from multiple rows into one readable string.

Here it is used diagnostically to display the different representations of an
otherwise equivalent company name side by side before any update is made.
*/

SELECT
    LOWER(company_name) AS normalized_name,
    STRING_AGG(
        DISTINCT company_name,
        ' | ' ORDER BY company_name
    ) AS variations
FROM unique_raw_job_postings
GROUP BY LOWER(company_name)
HAVING COUNT(DISTINCT company_name) > 1
ORDER BY normalized_name;


/*
DECISION

Because the identified variations are case-based, company names are normalized
to lowercase before they are extracted into a dedicated company reference
table.
*/


/*
5.6 — Standardize Company Names
*/

UPDATE unique_raw_job_postings
SET company_name = LOWER(company_name);


/*
5.7 — Validate Company-Name Standardization
*/

SELECT
    LOWER(company_name) AS normalized_name,
    COUNT(DISTINCT company_name) AS variations
FROM unique_raw_job_postings
GROUP BY LOWER(company_name)
HAVING COUNT(DISTINCT company_name) > 1;


/*
RESULT

The validation returns no case-based company-name variations.

WHY THIS MATTERS

Standardizing case prevents the same employer from being represented as
multiple company entities merely because capitalization differs.

The dataset now contains unique jobs, standardized analytical types, cleaned
location formatting, and consistent company-name casing.

The next major quality issue concerns the availability and consistency of
job-skill information.
*/


/*
===============================================================================
STAGE 6 — SKILL INFORMATION ASSESSMENT
===============================================================================
*/


/*
6.1 — Measure Jobs With and Without Supplied Skill Tokens

From early observation, "description_tokens" contains the skill information allocated
for jobs, while some records without supplied tokens use the textual empty-list
representation:

    []

The first task is to measure the scale of that missing-token population.

TECHNICAL NOTE — FILTER

PostgreSQL's FILTER clause allows conditional aggregate counts to be measured
against the same population within one query.
*/

SELECT
    COUNT(*) AS total_jobs,

    COUNT(*) FILTER (
        WHERE description_tokens <> '[]'
    ) AS jobs_with_tokens,

    COUNT(*) FILTER (
        WHERE description_tokens = '[]'
    ) AS jobs_without_token

FROM unique_raw_job_postings;


/*
RESULT

    Total jobs:                   58,775
    Jobs without skill tokens:    12,812

WHY THIS MATTERS

Leaving the missing tokens untouched is possible, but each job also contains a
full description.

Before settliing for all 12,812 missing-token records as unrecoverable, the project
tests whether some absent skills can be reconstructed conservatively from the
existing "description" column texts.
*/


/*
6.2 — Confirm Description Availability Where Tokens Are Missing

Skill recovery is only worth investigating if the underlying job descriptions
are actually available.
*/

SELECT
    COUNT(*) FILTER (
        WHERE description_tokens = '[]'
          AND description IS NOT NULL
          AND description <> ''
    ) AS empty_tokens_but_description_available,

    COUNT(*) FILTER (
        WHERE description_tokens = '[]'
          AND (description IS NULL OR description = '')
    ) AS empty_tokens_and_description_missing
FROM unique_raw_job_postings;


/*
RESULT

There are no missing "descriptions" value among the records being investigated for
absent skill tokens.

DECISION

Because the descriptive source text is available, skill recovery can be
explored without introducing information from an external dataset.

However, a central term and a conservative matching method are
required before any records are updated.
*/


/*
===============================================================================
STAGE 7 — SKILL VOCABULARY STANDARDIZATION AND CONSERVATIVE RECOVERY
===============================================================================
*/


/*
7.1 — Inspect Existing Skill Names

The populated "description_tokens" values are separated into individual skills
to understand the vocabulary already present in the source.

TECHNICAL NOTE — CROSS JOIN LATERAL + regexp_split_to_table()

regexp_split_to_table() separates a delimited text value into multiple rows.

CROSS JOIN LATERAL allows that function to operate against each source row's
description_tokens value.

Together, they transform the list-like token strings into individual skill
values that can be observed separately.
*/

SELECT DISTINCT
    TRIM(BOTH '[] ' FROM REPLACE(token, '''', '')) AS skill
FROM unique_raw_job_postings
CROSS JOIN LATERAL
    regexp_split_to_table(description_tokens, ',') AS token
WHERE description_tokens <> '[]'
ORDER BY skill;


/*
OBSERVATION

The source vocabulary contains naming variations representing equivalent
technologies, including examples such as:

    postgres / postgresql
    mongo / mongodb
    js / javascript
    node / node.js
    no-sql / nosql

If left untreated, these aliases could fragment future skill-level counts.
*/


/*
7.2 — Create a Controlled Skill Mapping

A supporting mapping table translates known source aliases into standardized
analytical names.

The source_skill_name remains available as the source vocabulary, while
standardized_name provides the common value used in the final relational
structure.
*/

CREATE TABLE skill_mapping (
    source_skill_name TEXT PRIMARY KEY,
    standardized_name TEXT NOT NULL
);


/*
Populate the mapping table.

The full mapping contains 134 source skill names resolving to 125 standardized
skill names. Representative aliases include the mappings in the query below.
*/

INSERT INTO skill_mapping (source_skill_name, standardized_name)
VALUES
    ('postgres', 'PostgreSQL'),
    ('postgresql', 'PostgreSQL'),
    ('mongo', 'MongoDB'),
    ('mongodb', 'MongoDB'),
    ('js', 'JavaScript'),
    ('javascript', 'JavaScript'),
    ('node', 'Node.js'),
    ('node.js', 'Node.js'),
    ('no-sql', 'NoSQL'),
    ('nosql', 'NoSQL');


/*
IMPORTANT SCOPE NOTE

The mapping table defines the vocabulary eligible for the description-based
recovery process.

Therefore, a job without a detected match should not yet be interpreted as a job
containing no skills. It only means that no sufficiently supported match from
the project's defined vocabulary was recovered using this method.
*/


/*
7.3 — Test the Skill-Recovery Hypothesis

Before constructing a generalized extraction method, some recognizable
skills are searched manually in "descriptions", for jobs with missing
tokens, to determine if the "description" column has potential skill
values suitable to cover for the actual jobs missing token values.

To explore, ILIKE provides a case-insensitive substring search.
*/

SELECT
    'python' AS potential_skill,
    COUNT(*) AS job_count
FROM unique_raw_job_postings
WHERE description_tokens = '[]'
  AND description ILIKE '%python%'

UNION ALL

SELECT
    'sql',
    COUNT(*)
FROM unique_raw_job_postings
WHERE description_tokens = '[]'
  AND description ILIKE '%sql%'

UNION ALL

SELECT
    'excel',
    COUNT(*)
FROM unique_raw_job_postings
WHERE description_tokens = '[]'
  AND description ILIKE '%excel%'

UNION ALL

SELECT
    'tableau',
    COUNT(*)
FROM unique_raw_job_postings
WHERE description_tokens = '[]'
  AND description ILIKE '%tableau%';


/*
RESULT

Recognizable skill terms are present within "descriptions" even where the
supplied "description_tokens" field is empty.

DECISION

The result supports the investigation of description-based recovery.

However, an unrestricted substring matching is not considered safe enough for the
final enrichment because short or ambiguous skill names may appear inside
ordinary words.
*/


/*
7.4 — Investigate False-Match Risk

Longer mapped skill names are first tested using ILIKE.

This remains an exploratory query rather than the final recovery method.
*/

SELECT
    skill_mapping.source_skill_name,
    COUNT(DISTINCT job_postings.job_id) AS job_count
FROM skill_mapping
JOIN unique_raw_job_postings AS job_postings
  ON job_postings.description_tokens = '[]'
 AND job_postings.description ILIKE
     '%' || skill_mapping.source_skill_name || '%'
WHERE LENGTH(skill_mapping.source_skill_name) > 2
GROUP BY skill_mapping.source_skill_name
ORDER BY job_count DESC;


/*
Short skill names such as R, C, Go, and JS require additional caution because
ordinary substring matching can detect their characters inside unrelated
words.

The exploratory tests demonstrate that recovery is possible, but they are not
sufficiently conservative for the final update.

ANALYTICAL DECISION

A stricter boundary-aware regular-expression method will be used.

The project prioritizes reducing false-positive skill assignments over
maximizing the number of recovered records.
*/


/*
7.5 — Stage Skills Using Boundary-Aware Matching

TECHNICAL NOTE — REGEX OPERATOR ~

PostgreSQL's ~ operator evaluates whether text matches a regular expression.

Instead of accepting a skill name anywhere inside another word, the constructed
pattern requires non-alphanumeric boundaries around the mapped term.

This reduces the likelihood that short or ambiguous skill names are detected
merely because their letters appear inside ordinary prose.

TECHNICAL NOTE — regexp_replace()

Some skill names contain characters such as ".", "+", "(" or ")" that have
special meanings in regular expressions.

regexp_replace() escapes those metacharacters before each source skill name is
inserted into the dynamically constructed regex pattern.
*/

SELECT
    RIGHT(job.job_id, 10) AS job_id,
    job.title,
    COUNT(DISTINCT skill.source_skill_name) AS skill_count,
    STRING_AGG(
        DISTINCT skill.standardized_name,
        ', ' ORDER BY skill.standardized_name
    ) AS skills_to_extract
FROM unique_raw_job_postings AS job
JOIN skill_mapping AS skill
    ON LOWER(job.description) ~
       (
           '(^|[^a-z0-9_])' ||
           regexp_replace(
               LOWER(skill.source_skill_name),
               E'([\\\\.^$|()\\[\\]{}*+?])',
               E'\\\\\\1',
               'g'
           ) ||
           '([^a-z0-9_]|$)'
       )
WHERE job.description_tokens = '[]'
  AND job.description IS NOT NULL
  AND TRIM(job.description) <> ''
GROUP BY
    job.job_id,
    job.title
HAVING COUNT(DISTINCT skill.source_skill_name) > 1
ORDER BY
    skill_count DESC,
    job.job_id;


/*
INTERPRETATION

The boundary-aware approach produces fewer matches than broad substring
matching.

That reduction is intentional: the stricter method excludes less reliable
matches and supports a more conservative cleaning strategy.
*/


/*
7.6 — Measure Recoverable Jobs

The boundary-aware matching logic is now applied across all 12,812 jobs with
missing skill tokens.

A LEFT JOIN is used so that jobs with no mapped skill match remain in the
population with a matched_skill_count of 0.
*/

SELECT
    COUNT(*) AS total_missing_token_jobs,

    COUNT(*) FILTER (
        WHERE matched_skill_count > 0
    ) AS jobs_with_discovered_skills,

    COUNT(*) FILTER (
        WHERE matched_skill_count = 0
    ) AS jobs_with_no_discovered_skills

FROM (
    SELECT
        job.job_id,
        COUNT(DISTINCT skill.source_skill_name) AS matched_skill_count
    FROM unique_raw_job_postings AS job
    LEFT JOIN skill_mapping AS skill
        ON LOWER(job.description) ~
           (
               '(^|[^a-z0-9])' ||
               regexp_replace(
                   LOWER(skill.source_skill_name),
                   E'([\\.^$|()\\[\\]{}*+?])',
                   E'\\\1',
                   'g'
               ) ||
               '([^a-z0-9]|$)'
           )
    WHERE job.description_tokens = '[]'
    GROUP BY job.job_id
) AS skill_match_counts;


/*
RESULT

The conservative matching method identifies 597 jobs for which at least one
skill from the defined mapping vocabulary can be recovered.

DECISION

Only positively matched records will be retrieved.

Jobs without a sufficiently supported match will remain without skill tokens
rather than being populated speculatively.
*/


/*
7.7 — Preview the Recovered Skill Tokens Before Updating

Before modifying the staging table, the proposed output is generated for
inspection.

STRING_AGG() reconstructs the matched source skills into the same list-like
representation used by "description_tokens".

This follows a recurring validation principle in the workflow:

    investigate first;
    transform second;
    validate afterward.
*/

SELECT
    job.job_id,
    job.title,
    '[' ||
    STRING_AGG(
        '''' || skill.source_skill_name || '''',
        ', ' ORDER BY skill.source_skill_name
    ) ||
    ']' AS recovered_description_tokens
FROM unique_raw_job_postings AS job
JOIN skill_mapping AS skill
    ON LOWER(job.description) ~
       (
           '(^|[^a-z0-9])' ||
           regexp_replace(
               LOWER(skill.source_skill_name),
               E'([\\.^$|()\\[\\]{}*+?])',
               E'\\\1',
               'g'
           ) ||
           '([^a-z0-9]|$)'
       )
WHERE job.description_tokens = '[]'
GROUP BY
    job.job_id,
    job.title
ORDER BY
    job.job_id;


/*
7.8 — Populate the Recovered Skill Tokens

Only "description_token" records currently represented by "[]" and having a positive mapped-skill
match are included in the update.
*/

UPDATE unique_raw_job_postings AS job
SET description_tokens = skill_matches.recovered_description_tokens
FROM (
    SELECT
        job.job_id,
        '[' ||
        STRING_AGG(
            '''' || skill.source_skill_name || '''',
            ', ' ORDER BY skill.source_skill_name
        ) ||
        ']' AS recovered_description_tokens
    FROM unique_raw_job_postings AS job
    JOIN skill_mapping AS skill
        ON LOWER(job.description) ~
           (
               '(^|[^a-z0-9])' ||
               regexp_replace(
                   LOWER(skill.source_skill_name),
                   E'([\\.^$|()\\[\\]{}*+?])',
                   E'\\\1',
                   'g'
               ) ||
               '([^a-z0-9]|$)'
           )
    WHERE job.description_tokens = '[]'
    GROUP BY job.job_id
) AS skill_matches
WHERE job.job_id = skill_matches.job_id;


/*
RESULT

PostgreSQL reports:

    UPDATE 597

Exactly 597 previously empty skill-token records are enriched.
*/


/*
7.9 — Validate Skill Recovery

The full skill-token population is measured again after retrieval.
*/

SELECT
    COUNT(*) AS total_jobs,

    COUNT(*) FILTER (
        WHERE description_tokens <> '[]'
    ) AS jobs_with_tokens,

    COUNT(*) FILTER (
        WHERE description_tokens = '[]'
    ) AS jobs_still_without_token

FROM unique_raw_job_postings;


/*
RESULT

    Total jobs:                         58,775
    Jobs with skill tokens:             46,560
    Jobs still without skill tokens:    12,215

VALIDATION

The dataset initially contained 12,812 jobs without supplied skill tokens.

    12,812 initial missing-token jobs
       597 conservatively recovered
    --------------------------------
    12,215 remaining without tokens

The remaining records are deliberately preserved without inferred skills
rather than populated with unrealistic matches.

This completes the skill-recovery stage while maintaining a conservative
standard for inferred information.
*/


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


/*
===============================================================================
STAGE 10 — FINAL RELATIONAL INTEGRITY VALIDATION
===============================================================================

The final model is now validated as one connected structure rather than
checking each table only in isolation.

This query confirms the core record counts and uniqueness conditions across
jobs, companies, and job_skills.
*/

SELECT
    (SELECT COUNT(*) FROM jobs) AS total_jobs,
    (SELECT COUNT(DISTINCT job_id) FROM jobs) AS unique_job_ids,
    (SELECT COUNT(*) FROM companies) AS total_companies,
    (SELECT COUNT(DISTINCT company_id) FROM companies) AS unique_company_ids,
    (SELECT COUNT(*) FROM job_skills) AS total_skill_records,
    (SELECT COUNT(DISTINCT job_id) FROM job_skills) AS jobs_with_skills,
    (SELECT COUNT(DISTINCT skill) FROM job_skills) AS unique_skills;


/*
FINAL RESULTS

    Total jobs:                         58,775
    Unique job IDs:                     58,775

    Total companies:                    13,178
    Unique company IDs:                 13,178

    Total job-skill relationships:     190,002
    Jobs represented in job_skills:     46,560
    Unique standardized skills:            125


FINAL INTEGRITY INTERPRETATION

1. JOB-LEVEL UNIQUENESS

       58,775 total jobs
       =
       58,775 unique job IDs

   This confirms one final jobs-table record per job_id.


2. COMPANY-LEVEL UNIQUENESS

       13,178 total companies
       =
       13,178 unique company IDs

   This confirms one identifier per company in the companies table.


3. SKILL RELATIONSHIP INTEGRITY

   job_skills contains:

       190,002 job-skill relationships
        46,560 jobs represented with skills
           125 standardized skills

   The separate duplicate validation returned 0 rows, confirming that no
   (job_id, skill) relationship occurs more than once.


4. SKILL-COVERAGE RECONCILIATION

       46,560 jobs with skills
       +
       12,215 jobs without recovered skill tokens
       =
       58,775 total jobs

   The skill populations therefore reconcile exactly with the final job
   population.


Together, these checks provide the final evidence that the cleaned dataset and
its primary relationships are internally consistent.
*/


/*
===============================================================================
FINAL DATA MODEL
===============================================================================

The original wide job-postings dataset has been transformed into three
principal analytical tables.


1. companies
-------------------------------------------------------------------------------

Purpose:
    Stores one standardized record per company.

Key structure:

    company_id
        PRIMARY KEY

    company_name
        UNIQUE standardized company name


2. jobs
-------------------------------------------------------------------------------

Purpose:
    Stores one record per cleaned job posting.

Key structure:

    job_id
        PRIMARY KEY

    company_id
        FOREIGN KEY -> companies.company_id

    Additional job-level attributes:
        title
        location
        date_time
        schedule_type
        work_from_home
        salary fields
        description
        via

Relationship:

    companies 1 -> many jobs


3. job_skills
-------------------------------------------------------------------------------

Purpose:
    Stores standardized skills associated with individual jobs.

Key structure:

    job_skill_id
        PRIMARY KEY

    job_id
        FOREIGN KEY -> jobs.job_id

    skill
        Standardized skill name

    UNIQUE(job_id, skill)
        Prevents duplicate job-skill relationships

Relationship:

    jobs 1 -> many job_skills

Across the complete dataset, the same standardized skill may occur in many
different jobs. The junction structure therefore supports the underlying
many-to-many relationship between jobs and skills.
*/


/*
===============================================================================
WORKFLOW SUMMARY
===============================================================================

The project follows a cumulative sequence:

    Raw CSV ingestion
        |
        v
    Initial data-quality audit
        |
        v
    Identification of 58,775 unique job IDs
    from 61,953 raw observations
        |
        v
    Record-level deduplication using the
    most recent observation per job_id
        |
        v
    Data-type standardization
        |
        v
    Location formatting correction
        |
        v
    Company-name standardization
        |
        v
    Skill-information completeness assessment
        |
        v
    Controlled skill-vocabulary standardization
        |
        v
    Conservative description-based recovery
    for 597 previously missing-token jobs
        |
        v
    Company reference-table creation
        |
        v
    Job/company relational modeling
        |
        v
    Job-skill normalization
        |
        v
    Primary-key, foreign-key, uniqueness,
    and record-level validation
        |
        v
    Final three-table analytical structure
    ready for downstream analysis
*/


/*
===============================================================================
KEY TECHNICAL TECHNIQUES DEMONSTRATED
===============================================================================

DISTINCT ON
    Retains the latest observation of each repeated job_id according to the
    project's documented retention rule.

USING + explicit type casts
    Converts initially imported TEXT fields into appropriate analytical types.

FILTER
    Calculates conditional aggregate counts against the same population.

TRIM
    Corrects confirmed leading/trailing string-formatting inconsistencies.

LOWER + STRING_AGG
    Diagnoses and standardizes case-based company-name variations.

CROSS JOIN LATERAL + regexp_split_to_table
    Decomposes list-like skill-token strings into individual values for
    vocabulary inspection.

Regular-expression matching (~)
    Provides safer description-based skill detection than unrestricted
    substring matching.

regexp_replace
    Escapes regex metacharacters in dynamically matched skill names.

STRING_AGG
    Reconstructs multiple detected skills into a controlled token
    representation during recovery.

ROW_NUMBER()
    Generates surrogate identifiers for standardized company records.

STRING_TO_ARRAY + UNNEST
    Converts packed skill strings into individual relational job-skill records.

PRIMARY KEY, FOREIGN KEY, and UNIQUE constraints
    Move important integrity assumptions into database-enforced rules.
*/


/*
===============================================================================
WHAT THE CLEANING PROCESS ESTABLISHED
===============================================================================

The completed workflow establishes that:

    - The raw table contained more observations than unique job IDs.

    - Critical analytical fields could be converted from generic TEXT into
      appropriate PostgreSQL data types.

    - 36,571 location values containing leading/trailing whitespace could be
      corrected while maintaining integrity over the 37 genuinely missing
      locations.

    - Some jobs without supplied skill tokens contained safely detectable
      mapped skills within their descriptions.

    - A conservative vocabulary-driven recovery method enriched 597 additional
      jobs while leaving unsupported records unresolved.

    - The cleaned wide table could be reorganized into a relational structure
      centered on jobs, companies, and job_skills.


