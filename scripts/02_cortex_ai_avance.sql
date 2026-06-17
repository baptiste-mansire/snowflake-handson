-- ============================================================================
-- MODULE 2 : CORTEX AI — L'IA qui lit 5000 avis pour vous
-- Durée : 25 min
-- Objectif : Montrer les fonctions IA avancées (au-delà du pipeline)
-- ============================================================================

USE DATABASE LAB_RETAIL_AI;
USE WAREHOUSE LAB_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. RÉSUMÉ EXÉCUTIF : "Résume les 100 pires avis en 5 bullet points"
-- Le brief que tout directeur retail rêve d'avoir chaque lundi matin.
-- ─────────────────────────────────────────────────────────────────────────────

WITH worst_reviews AS (
    SELECT REVIEW_TEXT
    FROM SILVER.REVIEWS_ENRICHED
    WHERE RATING <= 2
    ORDER BY SENTIMENT_SCORE ASC
    LIMIT 50
),
aggregated AS (
    SELECT LISTAGG(LEFT(REVIEW_TEXT, 200), ' | ') AS ALL_COMPLAINTS
    FROM worst_reviews
)
SELECT SNOWFLAKE.CORTEX.COMPLETE(
    'llama3.1-8b',
    'Tu es le directeur qualite d une marketplace. Voici 50 avis clients negatifs reels. Resume les en 5 points cles actionnables pour le comite de direction. Sois precis et donne des chiffres si possible.\n\nAvis:\n' || LEFT(ALL_COMPLAINTS, 3000)
) AS BRIEF_DIRECTION
FROM aggregated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. DÉTECTION DE FAUX AVIS : L'IA repère les patterns suspects
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    REVIEW_ID,
    RATING,
    REVIEW_TEXT,
    VERIFIED_PURCHASE,
    SENTIMENT_SCORE,
    SNOWFLAKE.CORTEX.COMPLETE(
        'llama3.1-8b',
        'Is this product review likely fake/spam? Consider: generic language, lack of specifics, overly positive without details, very short. Reply YES or NO then a brief reason.\n\nReview: ' || LEFT(REVIEW_TEXT, 300)
    ) AS FAKE_ANALYSIS
FROM SILVER.REVIEWS_ENRICHED
WHERE RATING = 5
  AND LENGTH(REVIEW_TEXT) < 100
LIMIT 10;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. GÉNÉRATION DE RÉPONSES CLIENT automatiques
-- "Générer une réponse empathique et professionnelle pour chaque avis négatif"
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    REVIEW_ID,
    RATING,
    LEFT(REVIEW_TEXT, 150) AS AVIS_CLIENT,
    SNOWFLAKE.CORTEX.COMPLETE(
        'llama3.1-8b',
        'Tu es un responsable service client bienveillant. Genere une reponse courte (3 phrases max), empathique et professionnelle a cet avis negatif. Propose une solution concrete.\n\nAvis client: ' || LEFT(REVIEW_TEXT, 500)
    ) AS REPONSE_GENEREE
FROM SILVER.REVIEWS_ENRICHED
WHERE RATING <= 2
LIMIT 5;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. EXTRACTION DE THÈMES : Qu'est-ce qui revient le plus ?
-- ─────────────────────────────────────────────────────────────────────────────

WITH sample_reviews AS (
    SELECT LISTAGG(LEFT(REVIEW_TEXT, 150), '\n') AS REVIEWS_BATCH
    FROM SILVER.REVIEWS_ENRICHED
    WHERE RATING <= 3
    LIMIT 30
)
SELECT SNOWFLAKE.CORTEX.COMPLETE(
    'llama3.1-8b',
    'Analyse these 30 customer reviews. Extract the TOP 5 recurring themes/complaints, ranked by frequency. For each theme, give: the theme name, approximate % of reviews mentioning it, and one representative quote.\n\nReviews:\n' || LEFT(REVIEWS_BATCH, 3000)
) AS TOP_THEMES
FROM sample_reviews;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. COMPARAISON : Avis vérifiés vs non-vérifiés
-- "Les acheteurs vérifiés sont-ils plus ou moins critiques ?"
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    VERIFIED_PURCHASE,
    COUNT(*) AS nb_avis,
    ROUND(AVG(RATING), 2) AS avg_rating,
    ROUND(AVG(SENTIMENT_SCORE), 3) AS avg_sentiment,
    SUM(CASE WHEN RATING <= 2 THEN 1 ELSE 0 END) AS nb_negatifs
FROM SILVER.REVIEWS_ENRICHED
GROUP BY VERIFIED_PURCHASE;

-- 💡 INSIGHT ATTENDU : Les non-verified ont un sentiment plus extrême
-- (soit très positif = fake, soit très négatif = trolls)
