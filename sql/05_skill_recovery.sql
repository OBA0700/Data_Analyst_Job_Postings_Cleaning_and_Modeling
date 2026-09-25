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