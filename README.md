# Data Analyst Job Postings — Data Cleaning, Skill Recovery & Relational Modeling

## Introduction

Real-world datasets are rarely ready for analysis the moment they are collected.

Before trends can be measured or conclusions drawn, the underlying data needs to be checked for duplication, inconsistent formatting, unsuitable data types, missing information, and structural problems that could distort downstream results.

This project transforms a large, wide job-postings dataset into a **cleaner, validated, and relationally structured PostgreSQL database** suitable for future analysis.

Starting with **61,953 raw job-posting observations across 27 fields**, I built a staged SQL workflow to:

* investigate and resolve repeated job records; 
* standardize analytical data types;
* correct location-formatting inconsistencies;
* normalize company names;
* assess missing skill information;
* conservatively recover supported skills from job descriptions;
* standardize equivalent skill names;
* separate companies, jobs, and skills into relational structures; and
* validate the resulting relationships using database constraints and reconciliation queries.

The final model contains:

| Final structure              |  Result |
| ---------------------------- | ------: |
| Unique job records           |  58,775 |
| Standardized companies       |  13,178 |
| Job-skill relationships      | 190,002 |
| Jobs represented with skills |  46,560 |
| Standardized skills          |     125 |

The resulting database is organized primarily around three tables: `jobs`, `companies`, and `job_skills`.

### Explore the SQL Workflow

The complete documented SQL workflow—including the audit queries, cleaning decisions, transformations, technical explanations, and validation checks—is available here:

**[View the complete SQL cleaning workflow](C:\Users\User\Desktop\data_analyst_job_postings_cleaning\sql\data_cleaning_and_modeling.sql)**

---

## Background

### Why This Project?

A job-postings dataset can reliably answer questions about salaries, employers, locations, skills, remote work, and other labor-market characteristics—but only when the records underneath those analyses are sufficiently reliable.

The source data presented several issues that could affect such analysis.

For example, the raw dataset contained more rows than unique job IDs. Location strings contained substantial whitespace inconsistencies. Equivalent companies could appear under different letter cases. Skill names contained aliases, while thousands of jobs had no supplied skill tokens at all.

Rather than immediately using the dataset to answer job-market questions, I focused first on a more fundamental question:

> **Can this dataset be transformed into a cleaner and more reliable analytical foundation before downstream analysis begins?**

That led to several supporting questions:

* How many genuinely distinct job IDs are represented by the raw observations?
* Are repeated job IDs exact duplicates, or repeated observations containing different information?
* Which record should represent a job observed multiple times?
* Are analytical fields stored using suitable PostgreSQL data types?
* Which inconsistencies are objective formatting problems, and which values should be preserved?
* Can equivalent company names be standardized without merging unsupported entities?
* How much skill information is missing?
* Can some missing skills be recovered from the existing job descriptions without relying on unsafe substring matching?
* How can equivalent skill aliases be standardized?
* How should the original wide dataset be reorganized for more convenient future analysis?
* How can the final relationships be validated and protected at the database level?

These questions shaped the SQL workflow from the initial audit through final relational validation.

### Data Source

The project uses the **Data Analyst Job Postings [Pay, Skills, Benefits]** dataset published by **Luke Barousse on Kaggle**.

**Dataset:** [Data Analyst Job Postings [Pay, Skills, Benefits] — Kaggle](https://www.kaggle.com/datasets/lukebarousse/data-analyst-job-postings-google-search)

The source data contains job-posting attributes covering areas such as job titles, companies, locations, descriptions, posting metadata, salaries, work arrangements, and extracted description tokens.

The raw CSV used in this project was staged in PostgreSQL across **27 columns** before cleaning began.

---

## Tools I Used

Several tools supported different parts of the workflow:

* **SQL:** The core language used to audit, clean, transform, normalize, and validate the dataset. The project moves beyond basic querying into conditional aggregation, PostgreSQL-specific deduplication, regular-expression matching, window functions, text decomposition, relational constraints, and validation queries.

* **PostgreSQL:** The database management system used to store and transform the job-postings data. PostgreSQL-specific functionality such as `DISTINCT ON`, `FILTER`, `CROSS JOIN LATERAL`, regex operators, `STRING_AGG()`, `UNNEST()`, and relational constraints played important roles throughout the workflow.

* **Visual Studio Code:** My primary working environment for developing, organizing, documenting, and executing the SQL workflow.

* **Git & GitHub:** Used for version control and for publishing the project, SQL workflow, supporting documentation, and project structure in a reproducible portfolio format.

* **ChatGPT:** Used selectively as a technical brainstorming and syntax-support tool, particularly while developing safer approaches for some of the more advanced SQL logic. Suggested approaches were inspected, adapted to the project context, executed against the database, and validated before being incorporated into the final workflow.

---

# The Analysis

To prevent the data cleaning process from looking like a series of disconnected corrections, I structured the project as a progressive investigation.

Each major stage is built on the same general principle:

**Inspect → diagnose → transform → validate**

This allowed each cleaning decision to be based on an observed problem and verified before moving on to the next.

---

## 1. Establishing the True Job-Level Baseline

The first important question was whether the number of the identiable rows is the same as the number of job postings.

```sql
SELECT
    COUNT(job_id) AS total_job_postings,
    COUNT(DISTINCT job_id) AS unique_job_ids,
    COUNT(*) - COUNT(DISTINCT job_id) AS repeated_jobs
FROM raw_job_postings;
```
![Relational data model](media\image1.png)

The audit established:

| Measure          | Result |
| ---------------- | -----: |
| Raw observations | 61,953 |
| Unique job IDs   | 58,775 |

This immediately flagged that the raw row count cannot be equivated as the number of jobs. It would simply overstate the job population.

Further validation found:

* no missing `job_id` or `date_time` values;
* no fully identical duplicate rows;
* **984 job IDs** appearing more than once; and
* as many as **75 observations** for a single repeated job ID.

This mattered because the identified patterns were not mere identical rows that could be indiscriminately deleted. They were repeated observations having the same job identifier.

### Deduplication Strategy

I compared the earliest and latest `date_time` values for repeated IDs and arrived at a consistent retention rule: **retain the most recent observation for each `job_id`.**

PostgreSQL's `DISTINCT ON` provided an effective way to apply that rule:

```sql
CREATE TABLE unique_raw_job_postings AS
SELECT DISTINCT ON (job_id) *
FROM raw_job_postings
ORDER BY job_id, date_time DESC;
```

The result was then validated:

```sql
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT job_id) AS unique_job_ids
FROM unique_raw_job_postings;
```
![Relational data model](media\image2.png)

Both counts returned **58,775**.

That equality confirmed that the new staging table contained one record per unique `job_id`.

---

## 2. Standardizing Analytical Data Types

The source data was initially imported as `TEXT` to reduce ingestion risk, but text is not an appropriate permanent type for fields intended for calculations or logical operations.

I therefore converted fields such as:

* `index_col` → `INTEGER`
* `work_from_home` → `BOOLEAN`
* `date_time` → `TIMESTAMP`
* salary measures → `NUMERIC`

For example:

```sql
ALTER TABLE unique_raw_job_postings
    ALTER COLUMN work_from_home TYPE BOOLEAN
        USING work_from_home::BOOLEAN,

    ALTER COLUMN date_time TYPE TIMESTAMP
        USING date_time::TIMESTAMP,

    ALTER COLUMN salary_avg TYPE NUMERIC
        USING salary_avg::NUMERIC,

    ALTER COLUMN salary_standardized TYPE NUMERIC
        USING salary_standardized::NUMERIC;
```

It is important to note here that **a value looking numeric does not literally mean it is stored numerically**.

Correct data types make operations such as sorting, filtering, arithmetic, aggregation, and date operations more reliable.

The final schema was checked through `information_schema.columns`, confirming that all **27 columns remained present** after the conversions.

---

## 3. Cleaning Location Values Without Inventing Data

Location inspection revealed a clear gap between formatting problems and genuinely missing information.

Using `TRIM()` as a diagnostic test showed:

* **36,571 records** with leading or trailing whitespace;
* **37 genuine `NULL` location values**.

```sql
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
GROUP BY location_issue;
```
![Relational data model](media\image3.png)

The whitespace represented a confirmed formatting defect and was corrected:

```sql
UPDATE unique_raw_job_postings
SET location = TRIM(location)
WHERE location <> TRIM(location);
```

Validation returned:

**0 records with remaining leading/trailing whitespace.**

![Relational data model](media\image4.png)

The 37 `NULL` values were retained.

The dataset has no reliable details for assigning those jobs a location, so replacing them would have introduced outliers rather than cleaning the data.

---

## 4. Standardizing Company Names

The company field contained no missing values and no identifiable whitespace problem. But it contained a more subtle inconsistency: **letter case**.

I first normalized company names temporarily with `LOWER()` and counted their actual variations:

```sql
SELECT
    LOWER(company_name) AS company_name_normalized,
    COUNT(DISTINCT company_name) AS name_variations
FROM unique_raw_job_postings
GROUP BY company_name_normalized
HAVING COUNT(DISTINCT company_name) > 1;
```

`STRING_AGG()` then made it possible to display competing representations side by side before modifying them.

After confirming the issue, company names were standardized to lowercase:

```sql
UPDATE unique_raw_job_postings
SET company_name = LOWER(company_name);
```

Several varied tests returned no case-based differences.

That was especially important because company names were later used to construct the `companies` reference table. Without the name standardization, capitalization differences could incorrectly create multiple company entities.

---

## 5. Assessing Missing Skill Information

The `description_tokens` field contained skill information for many jobs, but **12,812 jobs** initially contained:

```text
[]
```

rather than supplied skill tokens.

![Relational data model](media\image5.png)

Instead of immediately treating all 12,812 records as unrecoverable, I investigated the full job descriptions.

Every job in the missing-token population still had description text available.

That raised a useful cleaning question:

> **Could some missing skill information be recovered from text already contained in the dataset without introducing unsupported external information?**

Simple exploratory searches for terms such as Python, SQL, Excel, and Tableau demonstrated that known skill names did occur in those descriptions.

However, simply searching for every skill with:

```sql
ILIKE '%skill%'
```

would create a critical reliability problem.

Short terms such as `R`, `C`, `Go`, and `JS` can appear inside ordinary words. A broad substring match could therefore assign skills to jobs incorrectly.

The recovery method needed to become more conservative.

---

## 6. Building a Controlled Skill Vocabulary

Before recovering skills, I decomposed the existing token strings to inspect the vocabulary already present in the dataset.

```sql
SELECT DISTINCT
    TRIM(BOTH '[] ' FROM REPLACE(token, '''', '')) AS skill
FROM unique_raw_job_postings
CROSS JOIN LATERAL
    regexp_split_to_table(description_tokens, ',') AS token
WHERE description_tokens <> '[]'
ORDER BY skill;
```

This exposed aliases representing equivalent technologies, including examples such as:

* `postgres` / `postgresql`
* `mongo` / `mongodb`
* `js` / `javascript`
* `node` / `node.js`
* `no-sql` / `nosql`

A dedicated `skill_mapping` table was created to resolve those source aliases to standardized names.

The completed mapping represented:

**134 source skill names → 125 standardized skills**

For example:

```sql
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
```

This mapping served two purposes:

1. equivalent skill names could be represented consistently; and
2. it established a controlled vocabulary for conservative description-based recovery.

---

## 7. Recovering Missing Skills Conservatively

This became the most technically challenging part of the cleaning workflow.

Rather than maximizing the number of recovered records, I prioritized **reducing false-positive assignments**.

The final approach used PostgreSQL regular expressions with explicit boundaries:

```sql
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
```

Two pieces of this logic were particularly important:

* **Regex boundaries** reduced the risk of matching a skill merely because its characters occurred inside another word.
* **`regexp_replace()`** escaped special regex characters contained in skill names so that punctuation-bearing technologies could be interpreted literally.

The stricter method returned fewer matches than broad substring searching—which was intentional.

The goal was not:

> *How many empty skill records can I fill?*

It was:

> *How many can I support strongly enough to justify changing the data?*

Before applying the update, the proposed recovered values were staged for inspection.

Only then were the supported records updated.

### Skill-Recovery Result

**597 jobs** received recovered skill information.

![Relational data model](media\image6.png)

The resulting skill coverage was:

| Skill-token status                |   Jobs |
| --------------------------------- | -----: |
| Initially without supplied tokens | 12,812 |
| Conservatively recovered          |    597 |
| Remaining without tokens          | 12,215 |
| Final jobs with skill information | 46,560 |

The remaining 12,215 jobs were deliberately left unresolved rather than being assigned speculative skills.

---

## 8. Separating Companies from Jobs

After company names had been standardized, they could be moved into their own reference table.

```sql
CREATE TABLE companies AS
SELECT
    ROW_NUMBER() OVER (ORDER BY company_name) AS company_id,
    company_name
FROM (
    SELECT DISTINCT company_name
    FROM unique_raw_job_postings
) AS unique_companies;
```

The resulting table contained:

**13,178 unique companies**

A primary key and unique constraint were then added.

Each cleaned job was matched back to its company using `company_id`, and validation confirmed:

**0 unmatched jobs**

The final `jobs` table could therefore represent employers relationally instead of repeatedly storing company names.

This established:

**one company → many jobs**

---

## 9. Normalizing the Job-Skill Relationship

Skills presented a different structural challenge.

One job can contain several skills, while the same skill can occur across many jobs. Keeping these values packed inside a text field would make future skill-level analysis unnecessarily difficult.

I therefore created `job_skills`:

```sql
CREATE TABLE job_skills (
    job_skill_id BIGSERIAL PRIMARY KEY,
    job_id TEXT NOT NULL,
    skill TEXT NOT NULL,
    FOREIGN KEY (job_id) REFERENCES jobs(job_id),
    UNIQUE (job_id, skill)
);
```

The token strings were then converted into individual relational records using `STRING_TO_ARRAY()` and `UNNEST()`:

```sql
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
```

This produced:

| `job_skills` validation                   |  Result |
| ----------------------------------------- | ------: |
| Job-skill relationships                   | 190,002 |
| Jobs represented                          |  46,560 |
| Standardized skills                       |     125 |
| Duplicate `(job_id, skill)` relationships |       0 |

The final duplicate validation returned an empty result set, confirming that the same standardized skill was never assigned to the same job more than once.

---

## 10. Final Relational Model

The original wide dataset was ultimately reorganized around three primary analytical tables:

### `companies`

One standardized record per company.

* `company_id` — Primary Key
* `company_name` — Unique company name

### `jobs`

One record per unique job posting.

* `job_id` — Primary Key
* `company_id` — Foreign Key → `companies.company_id`
* job-level attributes such as title, location, posting date, work arrangement, salaries, description, and source

### `job_skills`

Individual standardized job-to-skill relationships.

* `job_skill_id` — Primary Key
* `job_id` — Foreign Key → `jobs.job_id`
* `skill` — standardized skill
* `(job_id, skill)` — Unique relationship

### Relationship Structure

![Relational data model](media\image7.png)

---

## 11. Final Integrity Validation

The final validation tested the completed model as one connected structure:

```sql
SELECT
    (SELECT COUNT(*) FROM jobs) AS total_jobs,
    (SELECT COUNT(DISTINCT job_id) FROM jobs) AS unique_job_ids,
    (SELECT COUNT(*) FROM companies) AS total_companies,
    (SELECT COUNT(DISTINCT company_id) FROM companies) AS unique_company_ids,
    (SELECT COUNT(*) FROM job_skills) AS total_skill_records,
    (SELECT COUNT(DISTINCT job_id) FROM job_skills) AS jobs_with_skills,
    (SELECT COUNT(DISTINCT skill) FROM job_skills) AS unique_skills;
```

### Final Results

| Validation measure               |  Result |
| -------------------------------- | ------: |
| Total jobs                       |  58,775 |
| Unique job IDs                   |  58,775 |
| Total companies                  |  13,178 |
| Unique company IDs               |  13,178 |
| Job-skill relationships          | 190,002 |
| Jobs represented in `job_skills` |  46,560 |
| Standardized skills              |     125 |

Several reconciliations are particularly important:

**58,775 total jobs = 58,775 unique job IDs**

This confirms one record per `job_id`.

**13,178 companies = 13,178 unique company IDs**

This confirms one identifier per standardized company record.

And:

**46,560 jobs with skills + 12,215 jobs without skill tokens = 58,775 total jobs**

The skill population therefore reconciles exactly with the complete final job population.

Together with **0 duplicate job-skill relationships** and **0 unmatched company relationships**, these checks provide the final evidence that the principal relational structures are internally consistent.

---

# What I Learned

This project strengthened both my technical SQL skills and my approach to data-quality problems.

* **Cleaning begins with diagnosis, not instant modification.** I learned to establish what was actually wrong before conceiving changes for the data. Also, that values presented in different forms are not necessarily errors, and missing information should not automatically be discarded or replaced.

* **Deduplication requires a business rule.** Discovering repeated IDs was only the beginning. I still needed to determine what those repetitions represented and establish a safe rule for selecting the record to retain.

* **Validation should be part of the transformation itself.** Instead of cleaning everything first and checking the result at the end, I repeatedly used the pattern **inspect → transform → validate**. This made the workflow easier to analyze and reduced the risk of increasing errors.

* **Conservative cleaning can be more valuable than aggressive imputation.** The skill-recovery stage taught me that recovering fewer records with stronger evidence can produce more credible and reliable data than maximizing completeness with weaker assumptions.

* **Advanced SQL becomes meaningful when tied to a problem.** Functions and techniques such as `DISTINCT ON`, `FILTER`, `STRING_AGG()`, `CROSS JOIN LATERAL`, `regexp_split_to_table()`, regex matching, `ROW_NUMBER()`, `STRING_TO_ARRAY()`, and `UNNEST()` became practical tools rather than isolated syntax operations.

* **Database constraints are part of data quality.** Primary keys, foreign keys, and unique constraints allowed important classification to move beyond documentation into rules enforced by PostgreSQL itself.

* **AI-assisted problem solving still requires validation.** Using ChatGPT for some syntax brainstorming helped me to solidify the importance of understanding the proposed logic, adapting it to the actual data problem, testing it against real records, and validating the result rather than accepting generated SQL at face value.

---

# Conclusions

## Insights

The most important outcome of this project is actually not a claim about the job market, but the creation of a more trustworthy analytical foundation.

A predefined skill vocabulary and conservative text-matching strategy became a very powereful approach for recovering skill information for **597 additional jobs** without forcing unsupported matches into the remaining records.

Standardizing the company-name facilitated the creation of **13,178 unique company records**, with every final job successfully linked to a company.

Finally, the packed skill information was transformed into **190,002 unique job-skill relationships across 46,560 jobs and 125 standardized skills**, with no duplicate job-skill pairs detected.

The result is a three-table relational structure designed to make intended job-market analysis cleaner, more transparent, and easier to validate.

## Closing Thoughts

The biggest takeaway from this project was how it proves that data cleaning is beyond making a dataset look tidy.

Every transformation shapes what future analysis will treat as truth, so removing a record, merging two names, filling a missing value, detecting a skill, or defining a relationship can all affect later results. 

For that reason, I approached the workflow by requiring a clear reason for each meaningful transformation and a validation step wherever possible.

The project also showed how SQL can move beyond querying existing data and become a tool for **data-quality investigation, controlled recovery, structural modeling, and integrity enforcement**.

With the cleaning and relational modeling complete, the resulting `jobs`, `companies`, and `job_skills` tables now provide the foundation for a separate downstream analysis of the job-postings data.
