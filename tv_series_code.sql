/* =========================================================
   VIEW 1: top_series_cast(series_id, series_title, cast)
   - One row per series with rating >= 4.00
   - cast = comma-separated list of DISTINCT actor names
   ========================================================= */

CREATE VIEW top_series_cast AS
SELECT
    s.series_id,
    s.series_title,
    GROUP_CONCAT(DISTINCT a.actor_name ORDER BY a.actor_name SEPARATOR ', ') AS cast
FROM
    series s
    JOIN episodes e       ON e.series_id = s.series_id
    JOIN actor_episode ae ON ae.episode_id = e.episode_id
    JOIN actors a         ON a.actor_id = ae.actor_id
WHERE
    s.rating >= 4.00
GROUP BY
    s.series_id,
    s.series_title;


/* =========================================================
   VIEW 2: actor_minutes(actor_id, actor_name, total_minutes_played)
   - Sum of minutes_played by all users on episodes featuring each actor
   ========================================================= */

CREATE VIEW actor_minutes AS
SELECT
    a.actor_id,
    a.actor_name,
    IFNULL(SUM(uh.minutes_played), 0) AS total_minutes_played
FROM
    actors a
    LEFT JOIN actor_episode ae ON ae.actor_id = a.actor_id
    LEFT JOIN user_history uh ON uh.episode_id = ae.episode_id
GROUP BY
    a.actor_id,
    a.actor_name;


/* =========================================================
   TRIGGER: AdjustRating
   BEFORE INSERT ON user_history
   - Clamp NEW.minutes_played to episode_length
   - Add 0.0001 * minutes_played to series.rating, capped at 5.00
   ========================================================= */

DELIMITER //

CREATE TRIGGER AdjustRating
BEFORE INSERT ON user_history
FOR EACH ROW
BEGIN
    DECLARE v_length    REAL;
    DECLARE v_series_id INT;

    /* Get episode_length and series_id for the episode being watched */
    SELECT e.episode_length, e.series_id
    INTO   v_length,       v_series_id
    FROM   episodes e
    WHERE  e.episode_id = NEW.episode_id;

    /* (a) Clamp minutes_played to the episode length */
    IF NEW.minutes_played > v_length THEN
        SET NEW.minutes_played = v_length;
    END IF;

    /* (b) Update the series rating, but not above 5.00 */
    UPDATE series s
    SET s.rating =
        CASE
            WHEN s.rating < 5.00 THEN LEAST(5.00, s.rating + 0.0001 * NEW.minutes_played)
            ELSE s.rating
        END
    WHERE s.series_id = v_series_id;
END//
/* End Trigger AdjustRating */


/* =========================================================
   PROCEDURE: AddEpisode(
       s_id, s_number, e_number, e_title, e_length
   )
   - Only insert if:
       1) series with s_id exists
       2) no existing episode with same (series_id, season_number, episode_number)
   - episode_id is auto-generated
   - date_of_release = current date
   ========================================================= */

CREATE PROCEDURE AddEpisode(
    IN s_id     INT,
    IN s_number TINYINT,
    IN e_number TINYINT,
    IN e_title  VARCHAR(128),
    IN e_length REAL
)
BEGIN
    /* Check that the series exists */
    IF EXISTS (SELECT 1 FROM series WHERE series_id = s_id) THEN

        /* Check that the episode for that season/number does NOT already exist */
        IF NOT EXISTS (
            SELECT 1
            FROM   episodes
            WHERE  series_id     = s_id
               AND season_number = s_number
               AND episode_number = e_number
        ) THEN

            /* Insert the new episode */
            INSERT INTO episodes (
                series_id,
                season_number,
                episode_number,
                episode_title,
                episode_length,
                date_of_release
            ) VALUES (
                s_id,
                s_number,
                e_number,
                e_title,
                e_length,
                CURDATE()
            );

        END IF;
    END IF;
END//
/* End Procedure AddEpisode */


/* =========================================================
   FUNCTION: GetEpisodeList(s_id, s_number)
   - Returns comma-separated list of episode titles
     for given series and season, ordered by episode_number
   ========================================================= */

CREATE FUNCTION GetEpisodeList(
    s_id     INT,
    s_number TINYINT
)
RETURNS TEXT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_list TEXT;

    SELECT
        GROUP_CONCAT(e.episode_title ORDER BY e.episode_number SEPARATOR ', ')
    INTO v_list
    FROM
        episodes e
    WHERE
        e.series_id     = s_id
        AND e.season_number = s_number;

    RETURN v_list;
END//
/* End Function GetEpisodeList */

DELIMITER ;
