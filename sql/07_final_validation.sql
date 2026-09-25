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