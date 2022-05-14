SET check_function_bodies = false;
CREATE SCHEMA auth;
CREATE SCHEMA extensions;
CREATE SCHEMA graphql_public;
CREATE SCHEMA launchpad;
CREATE SCHEMA realtime;
CREATE SCHEMA smartsell;
CREATE SCHEMA storage;
CREATE TYPE launchpad.meta_timer_challenges_rollback AS ENUM (
    'monthly',
    'weekly',
    'daily'
);
CREATE TYPE launchpad.vc_user_evaluation_score_publish AS ENUM (
    '1',
    '0'
);
CREATE TYPE smartsell.mapping_user_home_banner_carosel_type AS ENUM (
    'generic',
    'news',
    'leaderboard',
    'stock'
);
CREATE TYPE smartsell.meta_timer_challenges_rollback AS ENUM (
    'monthly',
    'weekly',
    'daily',
    ''
);
CREATE FUNCTION auth.email() RETURNS text
    LANGUAGE sql STABLE
    AS $$
  select 
  	coalesce(
		current_setting('request.jwt.claim.email', true),
		(current_setting('request.jwt.claims', true)::jsonb ->> 'email')
	)::text
$$;
CREATE FUNCTION auth.role() RETURNS text
    LANGUAGE sql STABLE
    AS $$
  select 
  	coalesce(
		current_setting('request.jwt.claim.role', true),
		(current_setting('request.jwt.claims', true)::jsonb ->> 'role')
	)::text
$$;
CREATE FUNCTION auth.uid() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  select 
  	coalesce(
		current_setting('request.jwt.claim.sub', true),
		(current_setting('request.jwt.claims', true)::jsonb ->> 'sub')
	)::uuid
$$;
CREATE FUNCTION extensions.grant_pg_cron_access() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  schema_is_cron bool;
BEGIN
  schema_is_cron = (
    SELECT n.nspname = 'cron'
    FROM pg_event_trigger_ddl_commands() AS ev
    LEFT JOIN pg_catalog.pg_namespace AS n
      ON ev.objid = n.oid
  );
  IF schema_is_cron
  THEN
    grant usage on schema cron to postgres with grant option;
    alter default privileges in schema cron grant all on tables to postgres with grant option;
    alter default privileges in schema cron grant all on functions to postgres with grant option;
    alter default privileges in schema cron grant all on sequences to postgres with grant option;
    alter default privileges for user supabase_admin in schema cron grant all
        on sequences to postgres with grant option;
    alter default privileges for user supabase_admin in schema cron grant all
        on tables to postgres with grant option;
    alter default privileges for user supabase_admin in schema cron grant all
        on functions to postgres with grant option;
    grant all privileges on all tables in schema cron to postgres with grant option; 
  END IF;
END;
$$;
COMMENT ON FUNCTION extensions.grant_pg_cron_access() IS 'Grants access to pg_cron';
CREATE FUNCTION extensions.grant_pg_graphql_access() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE
    func_is_graphql_resolve bool;
BEGIN
    func_is_graphql_resolve = (
        SELECT n.proname = 'resolve'
        FROM pg_event_trigger_ddl_commands() AS ev
        LEFT JOIN pg_catalog.pg_proc AS n
        ON ev.objid = n.oid
    );
    IF func_is_graphql_resolve
    THEN
        grant usage on schema graphql to postgres, anon, authenticated, service_role;
        grant all on function graphql.resolve to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on tables to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on functions to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on sequences to postgres, anon, authenticated, service_role;
        -- Update public wrapper to pass all arguments through to the pg_graphql resolve func
        create or replace function graphql_public.graphql(
            "operationName" text default null,
            query text default null,
            variables jsonb default null,
            extensions jsonb default null
        )
            returns jsonb
            language sql
        as $$
            select graphql.resolve(
                query := query,
                variables := coalesce(variables, '{}'),
                "operationName" := "operationName",
                extensions := extensions
            );
        $$;
        grant select on graphql.field, graphql.type, graphql.enum_value to postgres, anon, authenticated, service_role;
        grant execute on function graphql.resolve to postgres, anon, authenticated, service_role;
    END IF;
END;
$_$;
COMMENT ON FUNCTION extensions.grant_pg_graphql_access() IS 'Grants access to pg_graphql';
CREATE FUNCTION extensions.notify_api_restart() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NOTIFY pgrst, 'reload schema';
END;
$$;
COMMENT ON FUNCTION extensions.notify_api_restart() IS 'Sends a notification to the API to restart. If your database schema has changed, this is required so that Supabase can rebuild the relationships.';
CREATE FUNCTION extensions.set_graphql_placeholder() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $_$
    DECLARE
    graphql_is_dropped bool;
    BEGIN
    graphql_is_dropped = (
        SELECT ev.schema_name = 'graphql_public'
        FROM pg_event_trigger_dropped_objects() AS ev
        WHERE ev.schema_name = 'graphql_public'
    );
    IF graphql_is_dropped
    THEN
        create or replace function graphql_public.graphql(
            "operationName" text default null,
            query text default null,
            variables jsonb default null,
            extensions jsonb default null
        )
            returns jsonb
            language plpgsql
        as $$
            DECLARE
                server_version float;
            BEGIN
                server_version = (SELECT (SPLIT_PART((select version()), ' ', 2))::float);
                IF server_version >= 14 THEN
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql extension is not enabled.'
                            )
                        )
                    );
                ELSE
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql is only available on projects running Postgres 14 onwards.'
                            )
                        )
                    );
                END IF;
            END;
        $$;
    END IF;
    END;
$_$;
COMMENT ON FUNCTION extensions.set_graphql_placeholder() IS 'Reintroduces placeholder function for graphql_public.graphql';
CREATE FUNCTION launchpad.on_update_current_timestamp_admin_has_companies() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_admin_session() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_app_android_version() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_app_constants() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_app_ios_version() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_assets_data() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_auth_access_token() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_auth_refresh_token() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_batch() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_batch_has_course() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_batch_has_course_type() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_batch_has_db() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_batch_has_feedback_form() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_batch_has_onboard_quiz() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_batch_has_users() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_company() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_company_has_language() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_company_user_property() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_country() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_dashboard_activity_userscourse_quiz() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_dashboard_activity_usersskill_quizs() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_dashboard_activity_userssubtopic_qu() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_dashboard_learning_userscourse_quiz() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_dashboard_learning_usersskill_quizs() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_dashboard_learning_userssubtopic_qu() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_dashboard_user_courses_completion_r() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_dashboard_users_course_completion_a() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_dashboard_users_subtopic_completion() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_default_mapping_content_to_unit() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_default_mapping_sub_topic_to_topic() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_default_mapping_tags_to_subtopic() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_default_mapping_topic_to_course() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_default_mapping_unit_to_skill() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_default_mapping_unit_to_sub_topic() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_feedback_form() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_feedback_form_has_questions() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_feedback_form_language() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_feedback_questions() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_feedback_questions_language() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_filters() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_in_app_notification() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_logged_mobile_number() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_manager_levels() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_manager_session() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_manager_to_manager_mapping() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_manager_to_user_mapping() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_managers() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_mapping_challenge_to_evaluation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_mapping_content_to_unit() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_mapping_question_to_skill() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_mapping_sub_topic_to_topic() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_mapping_timer_challenges_to_company() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_mapping_topic_to_course() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_mapping_unit_to_skill() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_mapping_unit_to_sub_topic() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_mapping_user_to_reviewer() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_challenges() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_content_unit() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_content_unit_language() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_course() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_course_language() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_course_type() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_course_type_language() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_evaluation_params() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_gifs_language() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_glossary() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_language() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_live_streaming() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_pdfs_language() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_posters_language() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_quiz_questions() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_quiz_unit() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_quiz_unit_language() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_quiz_unit_temp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_skill() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_skill_language() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_speciality_page() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_speciality_page_language() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_spotlights() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_sub_topic() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_sub_topic_language() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_survey() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_survey_language() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_survey_questions() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_survey_questions_language() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_tags() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_timer_challenges() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_timer_challenges_language() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_timer_challenges_questions() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_topic() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_topic_language() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_video_language() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_videos() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_videos_language() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_web_link() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_meta_web_link_language() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_mile_stone() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_mile_stone_language() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_mile_stone_type() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_mile_stone_type_language() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_module() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_onboard_quiz() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_overall_completion() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_params_aggregate_score() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_quiz_type() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_reviewer_aggregate_score() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_reviewer_session() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_role() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_role_has_module() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_server_health() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_tiles_content_mapping() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_unit_completion() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_user_challenges() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_user_has_feedback_questions() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_user_has_quiz_has_question() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_user_has_survey_questions() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_user_push_notifications() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_users() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_users_certifications() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_users_contribution() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_users_lms_data() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_users_meta_properties() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_users_mile_stone() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_users_notifications() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_users_progress() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_users_rules() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_users_timer_challenges() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_users_timer_challenges_questions() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_users_tms_data() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_vc_batch_has_category() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_vc_batch_has_reviewer() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_vc_category() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_vc_category_has_reviewer() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_vc_challenges() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_vc_company_has_reviewers() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_vc_dashboard_categories_completion_() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_vc_dashboard_challenges_completion_() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_vc_dashboard_evaluation_param_compl() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_vc_evaluation_params() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_vc_groups() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_vc_mapping_challenge_to_category() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_vc_mapping_challenge_to_evaluation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_vc_mapping_user_to_reviewers() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_vc_params_aggregate_score() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_vc_reviewer_aggregate_score() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_vc_user_challenges() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION launchpad.on_update_current_timestamp_vc_users_groups() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_admin_session() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_app_constants() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_company() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_company_admins() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_company_branding() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_company_countries() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_company_groups() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_company_user_property() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_country() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_country_has_companies() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_group_cards() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_group_livestreams() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_group_presentations() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_group_products() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_group_users() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_lookup_mapping_page_to_section() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_lookup_mapping_product_section() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_lookup_mapping_section_to_presentat() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_lookup_page_master() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_lookup_presentation_category() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_lookup_presentation_master() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_lookup_product() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_lookup_product_benefit() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_lookup_product_benefit_category() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_lookup_product_bulletlist_collatera() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_lookup_product_bulletlist_multiple() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_lookup_product_category() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_lookup_product_faq() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_lookup_product_section() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_lookup_product_sectiontype() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_lookup_section_master() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_mapping_timer_challenges_to_user_gr() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_mapping_timer_challenges_to_user_ty() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_meta_cards() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_meta_cards_image_elements() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_meta_cards_text_elements() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_meta_configs() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_meta_livestream() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_meta_pdfs() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_meta_posters() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_meta_recognitions() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_meta_timer_challenges() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_meta_timer_challenges_language() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_meta_timer_challenges_questions() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_meta_videos() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_module() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_quiz_type() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_role_has_module() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_users_meta_properties() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_users_timer_challenges() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_users_timer_challenges_questions() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION smartsell.on_update_current_timestamp_video_library() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
CREATE FUNCTION storage.extension(name text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
_parts text[];
_filename text;
BEGIN
	select string_to_array(name, '/') into _parts;
	select _parts[array_length(_parts,1)] into _filename;
	-- @todo return the last part instead of 2
	return split_part(_filename, '.', 2);
END
$$;
CREATE FUNCTION storage.filename(name text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
_parts text[];
BEGIN
	select string_to_array(name, '/') into _parts;
	return _parts[array_length(_parts,1)];
END
$$;
CREATE FUNCTION storage.foldername(name text) RETURNS text[]
    LANGUAGE plpgsql
    AS $$
DECLARE
_parts text[];
BEGIN
	select string_to_array(name, '/') into _parts;
	return _parts[1:array_length(_parts,1)-1];
END
$$;
CREATE FUNCTION storage.search(prefix text, bucketname text, limits integer DEFAULT 100, levels integer DEFAULT 1, offsets integer DEFAULT 0) RETURNS TABLE(name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
_bucketId text;
BEGIN
    -- will be replaced by migrations when server starts
    -- saving space for cloud-init
END
$$;
CREATE TABLE auth.audit_log_entries (
    instance_id uuid,
    id uuid NOT NULL,
    payload json,
    created_at timestamp with time zone
);
COMMENT ON TABLE auth.audit_log_entries IS 'Auth: Audit trail for user actions.';
CREATE TABLE auth.instances (
    id uuid NOT NULL,
    uuid uuid,
    raw_base_config text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);
COMMENT ON TABLE auth.instances IS 'Auth: Manages users across multiple sites.';
CREATE TABLE auth.refresh_tokens (
    instance_id uuid,
    id bigint NOT NULL,
    token character varying(255),
    user_id character varying(255),
    revoked boolean,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);
COMMENT ON TABLE auth.refresh_tokens IS 'Auth: Store of tokens used to refresh JWT tokens once they expire.';
CREATE SEQUENCE auth.refresh_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE auth.refresh_tokens_id_seq OWNED BY auth.refresh_tokens.id;
CREATE TABLE auth.schema_migrations (
    version character varying(255) NOT NULL
);
COMMENT ON TABLE auth.schema_migrations IS 'Auth: Manages updates to the auth system.';
CREATE TABLE auth.users (
    instance_id uuid,
    id uuid NOT NULL,
    aud character varying(255),
    role character varying(255),
    email character varying(255),
    encrypted_password character varying(255),
    confirmed_at timestamp with time zone,
    invited_at timestamp with time zone,
    confirmation_token character varying(255),
    confirmation_sent_at timestamp with time zone,
    recovery_token character varying(255),
    recovery_sent_at timestamp with time zone,
    email_change_token character varying(255),
    email_change character varying(255),
    email_change_sent_at timestamp with time zone,
    last_sign_in_at timestamp with time zone,
    raw_app_meta_data jsonb,
    raw_user_meta_data jsonb,
    is_super_admin boolean,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);
COMMENT ON TABLE auth.users IS 'Auth: Stores user login data within a secure schema.';
CREATE TABLE launchpad.admin (
    id bigint NOT NULL,
    name character varying(100),
    username character varying(100) NOT NULL,
    password character varying(45),
    company_id_company integer DEFAULT 1 NOT NULL,
    parent_user smallint DEFAULT '1'::smallint NOT NULL,
    role_id_role smallint DEFAULT '2'::smallint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON COLUMN launchpad.admin.parent_user IS '0-enpUser,1-compnayUser';
COMMENT ON COLUMN launchpad.admin.role_id_role IS '1-CustomerSuccess,2-Content,3-ContentAdmin,4-ParentAdmin';
CREATE TABLE launchpad.admin_has_companies (
    admin_id integer NOT NULL,
    company_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE launchpad.admin_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.admin_id_seq OWNED BY launchpad.admin.id;
CREATE TABLE launchpad.admin_session (
    id bigint NOT NULL,
    token text,
    ip_address text,
    admin_agent text,
    last_login timestamp with time zone,
    last_logout timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.app_android_version (
    app_id integer NOT NULL,
    app_version integer NOT NULL,
    api_version integer NOT NULL,
    meta_db_path character varying(200),
    lookup_db_path character varying(200),
    killable smallint DEFAULT '0'::smallint,
    warnable smallint DEFAULT '0'::smallint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.app_constants (
    id bigint NOT NULL,
    batch_id integer,
    meta_content_version bigint,
    meta_content_flag integer DEFAULT 0,
    lookup_content_version bigint,
    lookup_content_flag integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    json_object text
);
CREATE SEQUENCE launchpad.app_constants_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.app_constants_id_seq OWNED BY launchpad.app_constants.id;
CREATE TABLE launchpad.app_ios_version (
    app_id integer NOT NULL,
    app_version integer NOT NULL,
    api_version integer NOT NULL,
    meta_db_path character varying(200),
    lookup_db_path character varying(200),
    killable smallint DEFAULT '0'::smallint,
    warnable smallint DEFAULT '0'::smallint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.assets_data (
    id bigint NOT NULL,
    aws_contents text,
    aws_contents_flag integer NOT NULL,
    pass_percentage integer DEFAULT 50 NOT NULL,
    signed_key character varying(255),
    android_app_link character varying(255),
    ios_app_link character varying(255),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.auth_access_token (
    access_token character varying(25) NOT NULL,
    user_id bigint NOT NULL,
    expiry_time timestamp with time zone,
    access_token_old character varying(25),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.auth_refresh_token (
    refresh_token character varying(25) NOT NULL,
    user_id bigint NOT NULL,
    expiry_time timestamp with time zone,
    refresh_token_old character varying(25),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.batch (
    batch_id bigint NOT NULL,
    company_id_company bigint DEFAULT '1'::bigint NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    start_time timestamp with time zone,
    end_time timestamp with time zone,
    test_batch smallint DEFAULT '0'::smallint NOT NULL,
    is_library smallint DEFAULT '0'::smallint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone,
    is_test_batch integer DEFAULT 0,
    pass_percentage integer DEFAULT 0,
    vc_enabled integer DEFAULT 0
);
COMMENT ON COLUMN launchpad.batch.test_batch IS '1-TestBatch,0-ClientBatches';
COMMENT ON COLUMN launchpad.batch.is_library IS '1-Library,0-NotALibrary';
CREATE SEQUENCE launchpad.batch_batch_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.batch_batch_id_seq OWNED BY launchpad.batch.batch_id;
CREATE TABLE launchpad.batch_has_course (
    batch_id integer NOT NULL,
    course_id integer NOT NULL,
    coursetype_id integer DEFAULT 1 NOT NULL,
    locked smallint DEFAULT '0'::smallint NOT NULL,
    sequence integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone,
    pass_percentage smallint DEFAULT '0'::smallint NOT NULL
);
COMMENT ON COLUMN launchpad.batch_has_course.locked IS '1-locked,0-unlocked';
COMMENT ON COLUMN launchpad.batch_has_course.pass_percentage IS '1-locked,0-unlocked';
CREATE TABLE launchpad.batch_has_course_type (
    batch_id bigint NOT NULL,
    coursetype_id bigint NOT NULL,
    sequence bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.batch_has_db (
    batch_id integer NOT NULL,
    meta_db_path text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.batch_has_feedback_form (
    id_feedback_form integer NOT NULL,
    batch_id integer NOT NULL,
    locked smallint DEFAULT '0'::smallint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN launchpad.batch_has_feedback_form.locked IS '1-locked,0-unlocked';
CREATE TABLE launchpad.batch_has_onboard_quiz (
    batch_id integer NOT NULL,
    quiz_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN launchpad.batch_has_onboard_quiz.batch_id IS 'refers to batch_id';
CREATE TABLE launchpad.batch_has_skills (
    batch_id integer NOT NULL,
    skill_id integer NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.batch_has_users (
    batch_id integer NOT NULL,
    user_id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.company (
    id_company bigint NOT NULL,
    name character varying(255),
    short_name character varying(128),
    address text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    app_configs text,
    company_unique_id text,
    company_default_batch integer,
    certificate_eligible_message character varying(255) NOT NULL
);
CREATE TABLE launchpad.company_certificate_image_elements (
    id bigint NOT NULL,
    certificate_id integer NOT NULL,
    on_by_default smallint NOT NULL,
    top_margin integer NOT NULL,
    left_margin integer NOT NULL,
    width integer NOT NULL,
    height integer NOT NULL,
    shape character varying(45) NOT NULL,
    keep_aspect_ratio smallint NOT NULL,
    profile_image smallint DEFAULT '1'::smallint NOT NULL,
    images text NOT NULL,
    bg_color character varying(255) NOT NULL,
    is_bg_color smallint DEFAULT '0'::smallint NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);
CREATE SEQUENCE launchpad.company_certificate_image_elements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.company_certificate_image_elements_id_seq OWNED BY launchpad.company_certificate_image_elements.id;
CREATE TABLE launchpad.company_certificate_templates (
    id bigint NOT NULL,
    company_id integer NOT NULL,
    name character varying(255) NOT NULL,
    description character varying(255) NOT NULL,
    share_text text NOT NULL,
    image_url text NOT NULL,
    thumbnail_url text NOT NULL,
    width integer NOT NULL,
    height integer NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);
CREATE SEQUENCE launchpad.company_certificate_templates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.company_certificate_templates_id_seq OWNED BY launchpad.company_certificate_templates.id;
CREATE TABLE launchpad.company_certificate_text_elements (
    id bigint NOT NULL,
    certificate_id integer NOT NULL,
    default_value text NOT NULL,
    on_by_default smallint NOT NULL,
    read_only smallint DEFAULT '1'::smallint NOT NULL,
    top_margin integer NOT NULL,
    left_margin integer NOT NULL,
    right_margin integer NOT NULL,
    text_alignment character varying(255) NOT NULL,
    font_family character varying(255) NOT NULL,
    font_size integer NOT NULL,
    font_color character varying(255) NOT NULL,
    font_style character varying(255) NOT NULL,
    font_weight character varying(255) NOT NULL,
    bg_color character varying(255) NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);
CREATE SEQUENCE launchpad.company_certificate_text_elements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.company_certificate_text_elements_id_seq OWNED BY launchpad.company_certificate_text_elements.id;
CREATE TABLE launchpad.company_has_language (
    company_id integer NOT NULL,
    id_language integer NOT NULL,
    is_default smallint DEFAULT '0'::smallint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE SEQUENCE launchpad.company_id_company_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.company_id_company_seq OWNED BY launchpad.company.id_company;
CREATE TABLE launchpad.company_user_property (
    id integer NOT NULL,
    id_company integer NOT NULL,
    meta_name character varying(128),
    display_name character varying(255),
    property_name character varying(255),
    status integer DEFAULT 1 NOT NULL,
    property_type character varying(255),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN launchpad.company_user_property.status IS '1-active,0-inactive';
CREATE TABLE launchpad.company_wise_manager_levels (
    id bigint NOT NULL,
    company_id integer NOT NULL,
    manager_id integer NOT NULL,
    level_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE SEQUENCE launchpad.company_wise_manager_levels_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.company_wise_manager_levels_id_seq OWNED BY launchpad.company_wise_manager_levels.id;
CREATE TABLE launchpad.const_active_content_image_tags (
    id integer NOT NULL,
    image_id integer,
    tag_name character varying(45),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE launchpad.const_active_content_images (
    id integer NOT NULL,
    name character varying(45),
    image_file_name character varying(45) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE launchpad.country (
    id integer NOT NULL,
    short_name character(2) NOT NULL,
    name character varying(45) NOT NULL,
    code character varying(11) DEFAULT ''::character varying,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    status smallint DEFAULT '0'::smallint NOT NULL,
    url text,
    min integer,
    max integer
);
CREATE SEQUENCE launchpad.country_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.country_id_seq OWNED BY launchpad.country.id;
CREATE TABLE launchpad.dashboard_activity_userscourse_quizscore (
    user_id bigint NOT NULL,
    course_id integer NOT NULL,
    course_name character varying(255),
    completion_percentage double precision DEFAULT '0'::double precision NOT NULL,
    latest_completion_percentage double precision DEFAULT '0'::double precision NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.dashboard_activity_usersskill_quizscore (
    user_id bigint NOT NULL,
    skill_id bigint NOT NULL,
    completion_percentage double precision DEFAULT '0'::double precision NOT NULL,
    latest_completion_percentage double precision DEFAULT '0'::double precision NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.dashboard_activity_userssubtopic_quizscore (
    user_id bigint NOT NULL,
    sub_topic_id bigint NOT NULL,
    completion_percentage double precision DEFAULT '0'::double precision NOT NULL,
    latest_completion_percentage double precision DEFAULT '0'::double precision NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.dashboard_learning_userscourse_quizscore (
    user_id bigint NOT NULL,
    course_id integer NOT NULL,
    course_name character varying(255),
    completion_percentage double precision DEFAULT '0'::double precision NOT NULL,
    latest_completion_percentage double precision DEFAULT '0'::double precision NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.dashboard_learning_usersskill_quizscore (
    user_id bigint NOT NULL,
    skill_id bigint NOT NULL,
    completion_percentage double precision DEFAULT '0'::double precision NOT NULL,
    latest_completion_percentage double precision DEFAULT '0'::double precision NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.dashboard_learning_userssubtopic_quizscore (
    user_id bigint NOT NULL,
    sub_topic_id bigint NOT NULL,
    completion_percentage double precision DEFAULT '0'::double precision NOT NULL,
    latest_completion_percentage double precision DEFAULT '0'::double precision NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.dashboard_user_courses_completion_rate (
    id integer NOT NULL,
    user_id bigint NOT NULL,
    course_id integer NOT NULL,
    completion_percentage double precision,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.dashboard_users_course_completion_avg (
    id integer NOT NULL,
    user_id bigint NOT NULL,
    completion_percentage text,
    created_at text NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.dashboard_users_subtopic_completion_avg (
    id integer NOT NULL,
    user_id bigint NOT NULL,
    completion_percentage text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.dashboard_users_subtopic_completion_rate (
    id integer NOT NULL,
    user_id bigint NOT NULL,
    subtopic_id bigint NOT NULL,
    completion_percentage double precision,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.default_mapping_content_to_unit (
    content_id bigint NOT NULL,
    content_type bigint NOT NULL,
    unit_id bigint NOT NULL,
    sequence bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN launchpad.default_mapping_content_to_unit.content_id IS 'PDF,Posters,Videos ID';
COMMENT ON COLUMN launchpad.default_mapping_content_to_unit.content_type IS '1-Poster, 2-Pdf ,3-Video';
COMMENT ON COLUMN launchpad.default_mapping_content_to_unit.unit_id IS 'This is foreign key to mapping_unit_to_sub_topic table';
CREATE TABLE launchpad.default_mapping_sub_topic_to_topic (
    sub_topic_id bigint NOT NULL,
    topic_id bigint NOT NULL,
    locked smallint DEFAULT '0'::smallint NOT NULL,
    replay smallint DEFAULT '1'::smallint NOT NULL,
    sequence bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN launchpad.default_mapping_sub_topic_to_topic.locked IS '1-locked,0-unlocked';
CREATE TABLE launchpad.default_mapping_tags_to_subtopic (
    tag_id integer NOT NULL,
    sub_topic_id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN launchpad.default_mapping_tags_to_subtopic.tag_id IS 'Tag Id';
COMMENT ON COLUMN launchpad.default_mapping_tags_to_subtopic.sub_topic_id IS 'This is subtopic id of meta_sub_topic';
CREATE TABLE launchpad.default_mapping_topic_to_course (
    topic_id bigint NOT NULL,
    course_id bigint NOT NULL,
    sequence bigint NOT NULL,
    locked integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN launchpad.default_mapping_topic_to_course.locked IS '0-unlocked, 1,locked';
CREATE TABLE launchpad.default_mapping_unit_to_skill (
    unit_id bigint NOT NULL,
    unit_type bigint NOT NULL,
    skill_id bigint NOT NULL,
    contribution bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.default_mapping_unit_to_sub_topic (
    unit_id bigint NOT NULL,
    sub_topic_id bigint NOT NULL,
    unit_type bigint NOT NULL,
    sequence bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN launchpad.default_mapping_unit_to_sub_topic.unit_id IS 'if unit_type==1 then mapping_content_to_unit   if unit_type===2 then meta_quiz_unit ';
COMMENT ON COLUMN launchpad.default_mapping_unit_to_sub_topic.unit_type IS '1-meta_content_unit, 2-meta_quiz_unit ';
CREATE TABLE launchpad.feedback_form (
    id_feedback_form integer NOT NULL,
    name character varying(255),
    description text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.feedback_form_has_questions (
    id_feedback_form integer NOT NULL,
    question_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.feedback_form_language (
    id_feedback_form integer NOT NULL,
    id_language integer DEFAULT 1 NOT NULL,
    name character varying(255),
    form_header text,
    form_description text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.feedback_questions (
    question_id bigint NOT NULL,
    id_feedback_form integer NOT NULL,
    question_type integer DEFAULT 1 NOT NULL,
    is_mandatory boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN launchpad.feedback_questions.question_type IS '1-MCQ,2-Rating,3-Text';
CREATE TABLE launchpad.feedback_questions_language (
    question_id bigint NOT NULL,
    id_feedback_form integer NOT NULL,
    id_language integer DEFAULT 1 NOT NULL,
    question text NOT NULL,
    options text,
    question_type integer NOT NULL,
    is_mandatory integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE launchpad.feedback_questions_language_question_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.feedback_questions_language_question_id_seq OWNED BY launchpad.feedback_questions_language.question_id;
CREATE SEQUENCE launchpad.feedback_questions_question_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.feedback_questions_question_id_seq OWNED BY launchpad.feedback_questions.question_id;
CREATE TABLE launchpad.filters (
    filter_id integer NOT NULL,
    manager_id integer NOT NULL,
    page character varying(180),
    filter_name character varying(180),
    filter_json text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.in_app_notification (
    id integer NOT NULL,
    batch_id integer NOT NULL,
    notification_time character varying(255) DEFAULT '8'::character varying,
    notifications text,
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN launchpad.in_app_notification.notification_time IS '1-24 hours time the notification comes';
COMMENT ON COLUMN launchpad.in_app_notification.enabled IS '1-all notifications enabled';
CREATE TABLE launchpad.logged_mobile_number (
    id integer NOT NULL,
    mobile_number character varying(100),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.logs (
    id bigint NOT NULL,
    event character varying(255),
    user_id integer NOT NULL
);
CREATE SEQUENCE launchpad.logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.logs_id_seq OWNED BY launchpad.logs.id;
CREATE TABLE launchpad.manager_levels (
    id integer NOT NULL,
    level_name character varying(150),
    "order" integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.manager_session (
    id bigint NOT NULL,
    manager_id integer NOT NULL,
    token text,
    ip_address text,
    manager_agent text,
    last_login timestamp with time zone,
    last_logout timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE launchpad.manager_session_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.manager_session_id_seq OWNED BY launchpad.manager_session.id;
CREATE TABLE launchpad.manager_to_manager_mapping (
    id integer NOT NULL,
    manager_id integer,
    sub_manager_id integer,
    parent_level integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.manager_to_user_mapping (
    id integer NOT NULL,
    manager_id integer,
    user_id bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.managers (
    id integer NOT NULL,
    name character varying(150),
    designation character varying(150),
    level_id integer DEFAULT 1,
    is_cockpit_accessible smallint DEFAULT '1'::smallint,
    user_name character varying(150),
    password character varying(255),
    email character varying(255),
    is_admin smallint DEFAULT '1'::smallint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.mapping_batch_has_live_streaming (
    batch_id bigint NOT NULL,
    live_streaming_id bigint NOT NULL,
    start_time timestamp with time zone,
    end_time timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.mapping_challenge_to_evaluation (
    id_challenge integer NOT NULL,
    id_evaluation integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.mapping_content_to_unit (
    content_id bigint NOT NULL,
    content_type bigint NOT NULL,
    unit_id bigint NOT NULL,
    sequence bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN launchpad.mapping_content_to_unit.content_id IS 'PDF,Posters,Videos ID';
COMMENT ON COLUMN launchpad.mapping_content_to_unit.content_type IS '1-Poster, 2-Pdf ,3-Video';
COMMENT ON COLUMN launchpad.mapping_content_to_unit.unit_id IS 'This is foreign key to mapping_unit_to_sub_topic table';
CREATE TABLE launchpad.mapping_question_to_skill (
    question_id bigint NOT NULL,
    skill_id integer NOT NULL,
    quiz_id integer NOT NULL,
    batch_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.mapping_sub_topic_to_topic (
    sub_topic_id bigint NOT NULL,
    topic_id bigint NOT NULL,
    batch_id integer NOT NULL,
    locked smallint DEFAULT '0'::smallint NOT NULL,
    replay smallint DEFAULT '1'::smallint NOT NULL,
    sequence bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN launchpad.mapping_sub_topic_to_topic.locked IS '1-locked,0-unlocked';
CREATE TABLE launchpad.mapping_timer_challenges_to_company (
    id bigint NOT NULL,
    id_company integer NOT NULL,
    id_batch integer DEFAULT 0 NOT NULL,
    quiz_id integer NOT NULL,
    sequence integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE SEQUENCE launchpad.mapping_timer_challenges_to_company_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.mapping_timer_challenges_to_company_id_seq OWNED BY launchpad.mapping_timer_challenges_to_company.id;
CREATE TABLE launchpad.mapping_topic_to_course (
    topic_id bigint NOT NULL,
    course_id bigint NOT NULL,
    sequence bigint NOT NULL,
    locked integer DEFAULT 0 NOT NULL,
    batch_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN launchpad.mapping_topic_to_course.locked IS '0-unlocked, 1,locked';
COMMENT ON COLUMN launchpad.mapping_topic_to_course.batch_id IS 'batch table mapping';
CREATE TABLE launchpad.mapping_unit_to_skill (
    unit_id bigint NOT NULL,
    unit_type bigint NOT NULL,
    skill_id bigint NOT NULL,
    contribution bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.mapping_unit_to_sub_topic (
    unit_id bigint NOT NULL,
    sub_topic_id bigint NOT NULL,
    unit_type bigint NOT NULL,
    batch_id integer NOT NULL,
    sequence bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN launchpad.mapping_unit_to_sub_topic.unit_id IS 'if unit_type==1 then mapping_content_to_unit   if unit_type===2 then meta_quiz_unit ';
COMMENT ON COLUMN launchpad.mapping_unit_to_sub_topic.unit_type IS '1-meta_content_unit, 2-meta_quiz_unit ';
CREATE TABLE launchpad.mapping_user_to_reviewer (
    id_user integer NOT NULL,
    id_reviewer integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.meta_active_content (
    id integer NOT NULL,
    name text,
    description text,
    template_type_id integer NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.meta_active_content_language (
    id integer NOT NULL,
    id_language integer NOT NULL,
    name text,
    description text,
    heading text,
    headline text,
    sub_heading text,
    text1 text,
    text2 text,
    text3 text,
    text4 text,
    text5 text,
    text6 text,
    text7 text,
    text8 text,
    text9 text,
    footer_text text,
    image1 text,
    image2 text,
    image3 text,
    image4 text,
    image5 text,
    disclaimer text,
    key_texts text,
    bullet_image text,
    company_logo text,
    background_type integer DEFAULT 0 NOT NULL,
    voice_url text,
    voice_version integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN launchpad.meta_active_content_language.voice_url IS 'audio url';
CREATE TABLE launchpad.meta_active_content_styles (
    id integer NOT NULL,
    name text NOT NULL,
    text_color text NOT NULL,
    highlight_text_color text NOT NULL,
    other_text_color text NOT NULL,
    font_family text NOT NULL,
    other_font_family text NOT NULL,
    bg_color text,
    bg_full_image text,
    bg_half_image text,
    bg_quarter_image text,
    image_base_url text NOT NULL,
    image_folder text NOT NULL
);
CREATE TABLE launchpad.meta_challenges (
    id_challenge integer NOT NULL,
    name character varying(100) NOT NULL,
    description character varying(200),
    status smallint DEFAULT '0'::smallint NOT NULL,
    expiry_time timestamp with time zone NOT NULL,
    duration_seconds integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    is_open smallint DEFAULT '0'::smallint
);
CREATE TABLE launchpad.meta_content_unit (
    id bigint NOT NULL,
    name character varying(255),
    description text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE SEQUENCE launchpad.meta_content_unit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.meta_content_unit_id_seq OWNED BY launchpad.meta_content_unit.id;
CREATE TABLE launchpad.meta_content_unit_language (
    id bigint NOT NULL,
    id_language integer NOT NULL,
    name character varying(255),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.meta_course (
    id integer NOT NULL,
    name character varying(255),
    description text,
    sequence bigint,
    course_type smallint DEFAULT '1'::smallint NOT NULL,
    intro_image text,
    intro_image_version integer DEFAULT 1 NOT NULL,
    client text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    test_course boolean DEFAULT false NOT NULL,
    is_freezed smallint DEFAULT '0'::smallint NOT NULL,
    is_certificate_active smallint DEFAULT '0'::smallint,
    is_certificate_based_on_trigger smallint DEFAULT '0'::smallint NOT NULL
);
COMMENT ON COLUMN launchpad.meta_course.course_type IS '1-BasicChallenges,2-OtherChallenges';
COMMENT ON COLUMN launchpad.meta_course.client IS 'client name if the same course name';
COMMENT ON COLUMN launchpad.meta_course.test_course IS '1-Test,0-Non Testing';
COMMENT ON COLUMN launchpad.meta_course.is_freezed IS '0-not freezed, 1,freezed';
CREATE TABLE launchpad.meta_course_language (
    id integer NOT NULL,
    id_language integer NOT NULL,
    name character varying(255),
    description text,
    duration text,
    image_name text,
    intro_text text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    client character varying(255)
);
COMMENT ON COLUMN launchpad.meta_course_language.client IS 'client name if the same course name';
CREATE TABLE launchpad.meta_course_type (
    id_course_type integer NOT NULL,
    name character varying(255),
    description text,
    title character varying(255) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.meta_course_type_language (
    id_course_type integer NOT NULL,
    id_language integer NOT NULL,
    title character varying(255) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    short_name character varying(255) DEFAULT ''::character varying
);
CREATE TABLE launchpad.meta_evaluation_params (
    id integer NOT NULL,
    name character varying(40) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.meta_faq (
    question_no integer NOT NULL,
    question_icon character varying(200),
    question character varying(200),
    question_type smallint DEFAULT '0'::smallint NOT NULL,
    answer_image character varying(200),
    answer_topline character varying(200),
    answer1_icon character varying(200),
    answer1 text,
    answer2_icon character varying(200),
    answer2 text,
    answer3_icon character varying(200),
    answer3 text,
    answer4_icon character varying(200),
    answer4 text,
    answer_bottomline text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.meta_faq_language (
    question_no integer NOT NULL,
    id_language integer NOT NULL,
    question_icon character varying(200),
    question character varying(200),
    question_type smallint DEFAULT '0'::smallint NOT NULL,
    answer_image character varying(200),
    answer_topline character varying(200),
    answer1_icon character varying(200),
    answer1 text,
    answer2_icon character varying(200),
    answer2 text,
    answer3_icon character varying(200),
    answer3 text,
    answer4_icon character varying(200),
    answer4 text,
    answer_bottomline text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.meta_featured_items (
    id bigint NOT NULL,
    title text,
    sub_title text,
    sub_topic_id bigint,
    topic_id bigint,
    course_id bigint,
    image text,
    sequence bigint NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);
CREATE SEQUENCE launchpad.meta_featured_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.meta_featured_items_id_seq OWNED BY launchpad.meta_featured_items.id;
CREATE TABLE launchpad.meta_gifs (
    id bigint NOT NULL,
    name character varying(255),
    description text,
    is_downloadable boolean NOT NULL,
    display integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);
CREATE SEQUENCE launchpad.meta_gifs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.meta_gifs_id_seq OWNED BY launchpad.meta_gifs.id;
CREATE TABLE launchpad.meta_gifs_language (
    id bigint NOT NULL,
    id_language integer NOT NULL,
    name character varying(45),
    description character varying(300),
    image_url character varying(300),
    voice_url text,
    image_md5_hash character varying(45),
    image_version integer DEFAULT 1,
    voice_version integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN launchpad.meta_gifs_language.voice_url IS 'audio url';
CREATE TABLE launchpad.meta_glossary (
    id bigint NOT NULL,
    batch_id bigint NOT NULL,
    word text,
    meaning text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE SEQUENCE launchpad.meta_glossary_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.meta_glossary_id_seq OWNED BY launchpad.meta_glossary.id;
CREATE TABLE launchpad.meta_language (
    id_language integer NOT NULL,
    name_english character varying(255),
    name character varying(255),
    short_name character varying(128),
    status smallint DEFAULT '1'::smallint NOT NULL,
    is_default smallint DEFAULT '1'::smallint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN launchpad.meta_language.status IS '1-active; 0-inactive';
CREATE TABLE launchpad.meta_live_streaming (
    id bigint NOT NULL,
    title character varying(255) NOT NULL,
    video text NOT NULL,
    start_time timestamp with time zone,
    end_time timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE SEQUENCE launchpad.meta_live_streaming_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.meta_live_streaming_id_seq OWNED BY launchpad.meta_live_streaming.id;
CREATE TABLE launchpad.meta_pdfs (
    id bigint NOT NULL,
    name character varying(255),
    description text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);
CREATE SEQUENCE launchpad.meta_pdfs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.meta_pdfs_id_seq OWNED BY launchpad.meta_pdfs.id;
CREATE TABLE launchpad.meta_pdfs_language (
    id bigint NOT NULL,
    id_language integer NOT NULL,
    name character varying(45),
    description character varying(300),
    share_text character varying(300),
    thumbnail_url character varying(200),
    thumbnail_md5_hash character varying(45),
    image_version integer DEFAULT 1,
    pdf_url character varying(200),
    pdf_md5_hash character varying(45),
    pdf_version integer DEFAULT 1,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.meta_posters (
    id bigint NOT NULL,
    name character varying(255),
    description text,
    is_downloadable boolean DEFAULT false NOT NULL,
    display integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON COLUMN launchpad.meta_posters.is_downloadable IS 'if 1 then app able to download';
CREATE SEQUENCE launchpad.meta_posters_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.meta_posters_id_seq OWNED BY launchpad.meta_posters.id;
CREATE TABLE launchpad.meta_posters_language (
    id bigint NOT NULL,
    id_language integer NOT NULL,
    name character varying(45),
    description character varying(300),
    image_url character varying(300),
    voice_url text,
    image_md5_hash character varying(45),
    image_version integer DEFAULT 1,
    voice_version integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN launchpad.meta_posters_language.voice_url IS 'audio url';
CREATE TABLE launchpad.meta_quiz_questions (
    id_meta_quiz_questions integer NOT NULL,
    question_id integer NOT NULL,
    quiz_id integer NOT NULL,
    id_language integer NOT NULL,
    skill_id integer NOT NULL,
    question text,
    short_question text,
    answer integer,
    answer_line text,
    explanation text,
    choices text,
    choice_type integer DEFAULT 0 NOT NULL,
    image_url text,
    select_count integer DEFAULT 0 NOT NULL,
    bucket_1_text character varying(255),
    bucket_2_text character varying(255),
    contribution integer DEFAULT 10 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.meta_quiz_unit (
    id bigint NOT NULL,
    name character varying(255),
    quiz_type integer,
    description text,
    question_json text,
    json_updated_flag boolean DEFAULT false NOT NULL,
    contribution integer DEFAULT 0 NOT NULL,
    url character varying(255),
    json_url_version integer DEFAULT 1 NOT NULL,
    pass_failed_enabled boolean DEFAULT false NOT NULL,
    show_score boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    answer_result integer DEFAULT 0,
    show_explanation integer DEFAULT 0
);
COMMENT ON COLUMN launchpad.meta_quiz_unit.contribution IS 'this is userd for storing quiz score for future reference';
COMMENT ON COLUMN launchpad.meta_quiz_unit.pass_failed_enabled IS '0-Not Enabled,1-Enabled';
COMMENT ON COLUMN launchpad.meta_quiz_unit.show_score IS '1-show,0-dontshow';
CREATE SEQUENCE launchpad.meta_quiz_unit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.meta_quiz_unit_id_seq OWNED BY launchpad.meta_quiz_unit.id;
CREATE TABLE launchpad.meta_quiz_unit_language (
    id bigint NOT NULL,
    id_language integer NOT NULL,
    name character varying(255),
    description text,
    question_json text,
    question_topic text,
    video_url text,
    intro text,
    intro_heading text,
    passage text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.meta_quiz_unit_temp (
    id bigint NOT NULL,
    name character varying(255),
    quiz_type integer,
    description text,
    url character varying(255),
    json_url_version integer DEFAULT 1 NOT NULL,
    question_json text,
    json_updated_flag boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.meta_skill (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    skill_type_id integer DEFAULT 1,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE SEQUENCE launchpad.meta_skill_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.meta_skill_id_seq OWNED BY launchpad.meta_skill.id;
CREATE TABLE launchpad.meta_skill_language (
    id bigint NOT NULL,
    id_language integer NOT NULL,
    name character varying(255),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.meta_skill_type (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE SEQUENCE launchpad.meta_skill_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.meta_skill_type_id_seq OWNED BY launchpad.meta_skill_type.id;
CREATE TABLE launchpad.meta_speciality_page (
    id bigint NOT NULL,
    name character varying(255),
    description text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE SEQUENCE launchpad.meta_speciality_page_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.meta_speciality_page_id_seq OWNED BY launchpad.meta_speciality_page.id;
CREATE TABLE launchpad.meta_speciality_page_language (
    id bigint NOT NULL,
    id_language integer NOT NULL,
    name character varying(255),
    url text,
    url_image_version bigint DEFAULT '1'::bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.meta_spotlights (
    id_meta_spotlights integer NOT NULL,
    batch_id integer NOT NULL,
    sub_topic_id integer NOT NULL,
    topic_id integer NOT NULL,
    course_id integer NOT NULL,
    start_time timestamp with time zone,
    end_time timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    sequence bigint DEFAULT '1'::bigint
);
CREATE TABLE launchpad.meta_sub_topic (
    id bigint NOT NULL,
    name character varying(255),
    description text,
    image_name text,
    image_version integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    test_sub_topic boolean DEFAULT false NOT NULL,
    style_id integer DEFAULT 1,
    pass_failed_enabled smallint DEFAULT '0'::smallint NOT NULL,
    pass_percentage bigint DEFAULT '0'::bigint NOT NULL,
    show_score smallint DEFAULT '1'::smallint NOT NULL,
    answer_result smallint DEFAULT '0'::smallint NOT NULL,
    show_explanation smallint DEFAULT '0'::smallint NOT NULL
);
COMMENT ON COLUMN launchpad.meta_sub_topic.test_sub_topic IS '1-Test,0-Non Testing';
CREATE SEQUENCE launchpad.meta_sub_topic_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.meta_sub_topic_id_seq OWNED BY launchpad.meta_sub_topic.id;
CREATE TABLE launchpad.meta_sub_topic_language (
    id bigint NOT NULL,
    id_language integer NOT NULL,
    name character varying(255),
    description text,
    notification_text text,
    notification_image_url text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.meta_survey (
    id_survey integer NOT NULL,
    name character varying(255),
    description text,
    expiry_time bigint DEFAULT '0'::bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.meta_survey_language (
    id_survey integer NOT NULL,
    id_language integer DEFAULT 1 NOT NULL,
    name character varying(255),
    header text,
    description text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.meta_survey_questions (
    question_id bigint NOT NULL,
    id_survey integer NOT NULL,
    question_type integer DEFAULT 1 NOT NULL,
    is_mandatory boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN launchpad.meta_survey_questions.question_type IS '1-MCQ,2-Rating,3-Text';
CREATE TABLE launchpad.meta_survey_questions_language (
    question_id bigint NOT NULL,
    id_language integer DEFAULT 1 NOT NULL,
    id_survey integer NOT NULL,
    question text NOT NULL,
    options text,
    question_type integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE launchpad.meta_survey_questions_language_question_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.meta_survey_questions_language_question_id_seq OWNED BY launchpad.meta_survey_questions_language.question_id;
CREATE SEQUENCE launchpad.meta_survey_questions_question_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.meta_survey_questions_question_id_seq OWNED BY launchpad.meta_survey_questions.question_id;
CREATE TABLE launchpad.meta_tags (
    id_meta_tags integer NOT NULL,
    name character varying(255),
    description text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.meta_template_type (
    id integer NOT NULL,
    type text NOT NULL,
    image_url text NOT NULL,
    sub_heading boolean DEFAULT false NOT NULL,
    heading boolean DEFAULT false NOT NULL,
    headline boolean DEFAULT false NOT NULL,
    text1 boolean DEFAULT false NOT NULL,
    text2 boolean DEFAULT false NOT NULL,
    text3 boolean DEFAULT false NOT NULL,
    text4 boolean DEFAULT false NOT NULL,
    text5 boolean DEFAULT false NOT NULL,
    text6 boolean DEFAULT false NOT NULL,
    text7 boolean DEFAULT false NOT NULL,
    text8 boolean DEFAULT false NOT NULL,
    text9 boolean DEFAULT false NOT NULL,
    "footer-text" boolean DEFAULT false NOT NULL,
    image1 boolean DEFAULT false NOT NULL,
    image2 boolean DEFAULT false NOT NULL,
    image3 boolean DEFAULT false NOT NULL,
    image4 boolean DEFAULT false NOT NULL,
    image5 boolean DEFAULT false NOT NULL,
    disclaimer boolean DEFAULT false NOT NULL,
    key_texts boolean DEFAULT false NOT NULL,
    bullet_image boolean DEFAULT false NOT NULL,
    company_logo boolean DEFAULT false NOT NULL
);
CREATE TABLE launchpad.meta_timer_challenges (
    id bigint NOT NULL,
    name character varying(255),
    quiz_type integer,
    url character varying(255),
    json_url_version bigint DEFAULT '1'::bigint NOT NULL,
    pass_failed_enabled boolean DEFAULT false NOT NULL,
    show_score bigint DEFAULT '1'::bigint NOT NULL,
    description text,
    question_json text,
    json_updated_flag boolean DEFAULT false NOT NULL,
    time_expired boolean DEFAULT false NOT NULL,
    start_time timestamp with time zone,
    end_time timestamp with time zone NOT NULL,
    contribution integer DEFAULT 10 NOT NULL,
    rollback launchpad.meta_timer_challenges_rollback,
    leaderboard_flag boolean DEFAULT false NOT NULL,
    leaderboard_type integer DEFAULT 1,
    leaderboard_winner integer DEFAULT 1,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    answer_result integer DEFAULT 0 NOT NULL,
    show_explanation integer DEFAULT 0 NOT NULL,
    is_freezed smallint DEFAULT '0'::smallint,
    max_duration integer DEFAULT 0
);
CREATE SEQUENCE launchpad.meta_timer_challenges_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.meta_timer_challenges_id_seq OWNED BY launchpad.meta_timer_challenges.id;
CREATE TABLE launchpad.meta_timer_challenges_language (
    id bigint NOT NULL,
    id_language integer NOT NULL,
    name character varying(255),
    description text,
    question_json text,
    question_topic text,
    video_url text,
    intro text,
    intro_heading text,
    passage text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    points text
);
CREATE SEQUENCE launchpad.meta_timer_challenges_language_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.meta_timer_challenges_language_id_seq OWNED BY launchpad.meta_timer_challenges_language.id;
CREATE TABLE launchpad.meta_timer_challenges_questions (
    id_meta_timer_challenges_questions bigint NOT NULL,
    question_id integer NOT NULL,
    quiz_id integer NOT NULL,
    id_language integer NOT NULL,
    skill_id integer DEFAULT 0 NOT NULL,
    question text,
    answer integer NOT NULL,
    answer_line text,
    explanation text,
    choices text,
    choice_type integer DEFAULT 0 NOT NULL,
    image_url text,
    select_count integer DEFAULT 0 NOT NULL,
    bucket_1_text character varying(255),
    bucket_2_text character varying(255),
    contribution integer DEFAULT 10 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE SEQUENCE launchpad.meta_timer_challenges_questio_id_meta_timer_challenges_ques_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.meta_timer_challenges_questio_id_meta_timer_challenges_ques_seq OWNED BY launchpad.meta_timer_challenges_questions.id_meta_timer_challenges_questions;
CREATE TABLE launchpad.meta_topic (
    id bigint NOT NULL,
    name character varying(255),
    show_name smallint DEFAULT '0'::smallint NOT NULL,
    description text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    test_topic boolean DEFAULT false NOT NULL
);
COMMENT ON COLUMN launchpad.meta_topic.show_name IS 'name will be shown in app if it is set';
COMMENT ON COLUMN launchpad.meta_topic.test_topic IS '1-Test,0-Non Testing';
CREATE SEQUENCE launchpad.meta_topic_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.meta_topic_id_seq OWNED BY launchpad.meta_topic.id;
CREATE TABLE launchpad.meta_topic_language (
    id bigint NOT NULL,
    id_language integer NOT NULL,
    name character varying(255),
    description text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.meta_video (
    id bigint NOT NULL,
    name character varying(255),
    description text,
    url character varying(200),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);
CREATE SEQUENCE launchpad.meta_video_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.meta_video_id_seq OWNED BY launchpad.meta_video.id;
CREATE TABLE launchpad.meta_video_language (
    id integer NOT NULL,
    id_language integer NOT NULL,
    name character varying(255) NOT NULL,
    url text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.meta_videos (
    id bigint NOT NULL,
    name character varying(255),
    description text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE SEQUENCE launchpad.meta_videos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.meta_videos_id_seq OWNED BY launchpad.meta_videos.id;
CREATE TABLE launchpad.meta_videos_language (
    id bigint NOT NULL,
    id_language integer NOT NULL,
    name character varying(255),
    url text,
    url_image_version bigint DEFAULT '1'::bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.meta_web_link (
    id integer NOT NULL,
    name character varying(255),
    description text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.meta_web_link_language (
    id integer NOT NULL,
    id_language integer NOT NULL,
    name character varying(255),
    link text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.migrations (
    id bigint NOT NULL,
    migration character varying(255) NOT NULL,
    batch integer NOT NULL
);
CREATE SEQUENCE launchpad.migrations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.migrations_id_seq OWNED BY launchpad.migrations.id;
CREATE TABLE launchpad.mile_stone (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    show_status boolean DEFAULT true,
    sequence integer,
    milestone_type integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE launchpad.mile_stone_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.mile_stone_id_seq OWNED BY launchpad.mile_stone.id;
CREATE TABLE launchpad.mile_stone_language (
    id bigint NOT NULL,
    id_language integer NOT NULL,
    image_name character varying(255),
    image_url character varying(255),
    title character varying(255),
    constant_label character varying(255),
    constant_value integer NOT NULL,
    description text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.mile_stone_type (
    id_type integer NOT NULL,
    name character varying(255),
    description text,
    sequence integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.mile_stone_type_language (
    id_type bigint NOT NULL,
    id_language integer NOT NULL,
    title character varying(255),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.module (
    id_module bigint NOT NULL,
    name character varying(255) NOT NULL,
    name_duplicate character varying(255) NOT NULL,
    status integer DEFAULT 1 NOT NULL,
    module_group character varying(255),
    module_group_sequence bigint DEFAULT '100'::bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone,
    description text
);
COMMENT ON COLUMN launchpad.module.name IS 'batch_create';
COMMENT ON COLUMN launchpad.module.name_duplicate IS 'Batch Create';
COMMENT ON COLUMN launchpad.module.status IS '1-active; 0-inactive';
COMMENT ON COLUMN launchpad.module.description IS 'short description about the module';
CREATE SEQUENCE launchpad.module_id_module_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.module_id_module_seq OWNED BY launchpad.module.id_module;
CREATE TABLE launchpad.onboard_quiz (
    id bigint NOT NULL,
    name character varying(255),
    quiz_type integer,
    url character varying(255),
    question_json text,
    json_updated_flag boolean DEFAULT false NOT NULL,
    recommended_course integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE launchpad.onboard_quiz_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.onboard_quiz_id_seq OWNED BY launchpad.onboard_quiz.id;
CREATE TABLE launchpad.overall_completion (
    user_id bigint NOT NULL,
    item_id bigint NOT NULL,
    item_type bigint NOT NULL,
    completed_at timestamp with time zone,
    latest_pass_status smallint DEFAULT '1'::smallint NOT NULL,
    best_pass_status smallint DEFAULT '1'::smallint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.params_aggregate_score (
    id_user integer NOT NULL,
    id_challenge integer NOT NULL,
    id_evaluation integer NOT NULL,
    aggregate_score numeric(10,2) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.push_notification_targets (
    id integer NOT NULL,
    title character varying(255),
    value character varying(255),
    show_status integer DEFAULT 1
);
CREATE TABLE launchpad.quiz_type (
    id_quiz_type integer NOT NULL,
    name character varying(255),
    status smallint DEFAULT '1'::smallint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.reviewer_aggregate_score (
    id_reviewer integer NOT NULL,
    id_user integer NOT NULL,
    id_challenge integer NOT NULL,
    aggregate_score numeric(10,2) NOT NULL,
    feedback character varying(300),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.reviewer_session (
    id bigint NOT NULL,
    token text,
    ip_address text,
    admin_agent text,
    last_login timestamp with time zone,
    last_logout timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.role (
    id_role bigint NOT NULL,
    name character varying(255),
    roles text,
    status integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN launchpad.role.status IS '1-active; 0-inactive';
CREATE TABLE launchpad.role_has_module (
    id_role_has_module integer NOT NULL,
    role_id_role bigint NOT NULL,
    module_id_module bigint NOT NULL,
    status boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE SEQUENCE launchpad.role_has_module_id_role_has_module_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.role_has_module_id_role_has_module_seq OWNED BY launchpad.role_has_module.id_role_has_module;
CREATE SEQUENCE launchpad.role_id_role_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.role_id_role_seq OWNED BY launchpad.role.id_role;
CREATE TABLE launchpad.server_health (
    id integer NOT NULL,
    health bigint DEFAULT '0'::bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.testing (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);
CREATE SEQUENCE launchpad.testing_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.testing_id_seq OWNED BY launchpad.testing.id;
CREATE TABLE launchpad.tiles_content_mapping (
    tile_id integer NOT NULL,
    tile_type_id integer NOT NULL,
    item_type integer,
    item_json text,
    id_batch bigint NOT NULL,
    heading character varying(145),
    sequence integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.unit_completion (
    user_id bigint NOT NULL,
    unit_id bigint NOT NULL,
    unit_type bigint NOT NULL,
    score bigint,
    latest_score smallint DEFAULT '0'::smallint NOT NULL,
    total bigint,
    completed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.user_challenges (
    id_user integer NOT NULL,
    id_challenge integer NOT NULL,
    status smallint DEFAULT '0'::smallint NOT NULL,
    file_name character varying(20),
    video_mp4_url character varying(2000),
    video_m3u8_url character varying(500),
    thumbnail_url character varying(500),
    duration_seconds integer NOT NULL,
    overall_score double precision DEFAULT '0'::double precision NOT NULL,
    recorded_on timestamp with time zone NOT NULL,
    uploaded_at timestamp with time zone,
    converted_at timestamp with time zone,
    reviewed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.user_dublicate_uids (
    id integer NOT NULL,
    unique_id character varying(255) NOT NULL,
    uid_by_saroj character varying(255) NOT NULL
);
CREATE TABLE launchpad.user_evaluation_score (
    id_user integer NOT NULL,
    id_challenge integer NOT NULL,
    id_evaluation integer NOT NULL,
    id_reviewer integer NOT NULL,
    score numeric(10,2) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.user_has_feedback_questions (
    user_id bigint NOT NULL,
    question_id integer NOT NULL,
    id_feedback_form integer NOT NULL,
    sub_topic_id integer,
    topic_id integer,
    course_id integer,
    answer text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.user_has_quiz_has_question (
    user_id bigint NOT NULL,
    quiz_id bigint NOT NULL,
    question_id integer NOT NULL,
    no_of_options_correct integer DEFAULT 0,
    latest_no_of_options_correct integer DEFAULT 0 NOT NULL,
    option_selected integer,
    latest_option_selected integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN launchpad.user_has_quiz_has_question.no_of_options_correct IS 'No of options correct';
CREATE TABLE launchpad.user_has_survey_questions (
    user_id bigint NOT NULL,
    question_id integer NOT NULL,
    id_survey integer NOT NULL,
    answer text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.user_lms_logs (
    id integer NOT NULL,
    operation_type character varying(255),
    user_id integer
);
CREATE TABLE launchpad.user_logs (
    id integer NOT NULL,
    operation_type character varying(255),
    user_id integer
);
CREATE TABLE launchpad.user_parameters (
    user_id bigint NOT NULL,
    location character varying(200),
    facilitator character varying(200),
    manager character varying(200),
    department character varying(200),
    role character varying(200),
    geography character varying(200)
);
CREATE TABLE launchpad.user_push_notifications (
    id bigint NOT NULL,
    topic character varying(200),
    title character varying(100),
    message character varying(200),
    action_target character varying(45),
    action_text character varying(45),
    extra_data text,
    batch_ids text,
    image_url character varying(300),
    scheduled_date timestamp with time zone,
    scheduled_status integer DEFAULT 0,
    sent_status integer DEFAULT 0,
    is_leaderboard integer DEFAULT 0,
    sync integer DEFAULT 0,
    force_data_sync boolean DEFAULT false NOT NULL,
    block_status boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    topic_type character varying(200)
);
COMMENT ON COLUMN launchpad.user_push_notifications.force_data_sync IS '0-defaultnotblocked,1-blocked';
COMMENT ON COLUMN launchpad.user_push_notifications.block_status IS '0-defaultnotblocked,1-blocked';
CREATE SEQUENCE launchpad.user_push_notifications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.user_push_notifications_id_seq OWNED BY launchpad.user_push_notifications.id;
CREATE TABLE launchpad.user_quiz_history (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    quiz_id integer NOT NULL,
    question_id integer NOT NULL,
    option_selected integer NOT NULL,
    status character varying(255) NOT NULL,
    attempted_at timestamp with time zone,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);
CREATE SEQUENCE launchpad.user_quiz_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.user_quiz_history_id_seq OWNED BY launchpad.user_quiz_history.id;
CREATE TABLE launchpad.user_tms_logs (
    id integer NOT NULL,
    operation_type character varying(255),
    user_id integer
);
CREATE TABLE launchpad.users (
    user_id bigint NOT NULL,
    admin_id integer DEFAULT 0 NOT NULL,
    updated_by integer DEFAULT 0 NOT NULL,
    mobile_number character varying(10) DEFAULT ''::character varying,
    name_encrypted text,
    username character varying(255),
    password character varying(255),
    name text,
    email character varying(255),
    email_encrypted text,
    location text,
    location_encrypted text,
    date_of_birth date,
    security_key character varying(8),
    user_type_id integer DEFAULT 0,
    activation_status smallint DEFAULT '0'::smallint,
    registered_status smallint DEFAULT '0'::smallint,
    signature character varying(300),
    fcm character varying(255),
    apn character varying(255),
    profile_img_url character varying(200),
    otp character varying(6),
    otp_expiry_time timestamp with time zone,
    android_user smallint DEFAULT '0'::smallint,
    ios_user smallint DEFAULT '0'::smallint,
    encrypted_status boolean DEFAULT false,
    device_id text,
    onboard_status bigint DEFAULT '0'::bigint NOT NULL,
    recommended_course integer DEFAULT 0 NOT NULL,
    latest_course integer DEFAULT 0 NOT NULL,
    pass_percentage integer DEFAULT 0 NOT NULL,
    registered_date timestamp with time zone,
    test_user boolean DEFAULT false NOT NULL,
    blocked smallint DEFAULT '0'::smallint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone,
    unique_id character varying(512) DEFAULT ''::character varying,
    last_app_open_time timestamp with time zone,
    id_language integer,
    meta1 character varying(255),
    meta2 character varying(255),
    meta3 character varying(255),
    meta4 character varying(255),
    meta5 character varying(255),
    meta6 character varying(255),
    meta7 character varying(255),
    meta8 character varying(255),
    meta9 character varying(255),
    meta10 character varying(255),
    meta11 character varying(255),
    meta12 character varying(255),
    meta13 character varying(255),
    meta14 character varying(255),
    meta15 character varying(255),
    meta16 character varying(255),
    meta17 character varying(255),
    meta18 date,
    meta19 character varying(255),
    meta20 character varying(255),
    activated_at timestamp with time zone,
    deactivated_at timestamp with time zone,
    disabled_at timestamp with time zone,
    requested_at timestamp with time zone,
    rejected_at timestamp with time zone,
    distinct_id text,
    designation text,
    country_code character varying(45) DEFAULT '+91'::character varying NOT NULL,
    verify_otp_attempts smallint,
    verify_otp_block_time timestamp with time zone,
    verify_otp_start_time timestamp with time zone
);
COMMENT ON COLUMN launchpad.users.test_user IS '0-notestaccount,1-testaccount';
COMMENT ON COLUMN launchpad.users.blocked IS '0-not blocked,1-blocked,2-blockconfirmed';
CREATE TABLE launchpad.users_certifications (
    user_id bigint NOT NULL,
    course_id integer NOT NULL,
    completed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.users_contribution (
    user_id bigint NOT NULL,
    skill_id bigint NOT NULL,
    contribution bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.users_details (
    user_id bigint NOT NULL,
    gender character varying(45),
    l1_manager_name text,
    l1_manager_code text,
    l1_manager_email text,
    l2_manager_name text,
    l2_manager_code text,
    l2_manager_email text,
    trainer_name text,
    trainer_email text,
    dob date,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE launchpad.users_lms_data (
    unique_id integer NOT NULL,
    course_id integer NOT NULL,
    module_id integer,
    user_id bigint NOT NULL,
    employee_full_name character varying(255),
    employee_id character varying(255),
    employee_adid character varying(255),
    official_email_id character varying(255),
    gadget_name character varying(255),
    course_name character varying(255),
    final_course_completion_status character varying(255),
    course_completion_date timestamp with time zone,
    course_start_time timestamp with time zone,
    user_type character varying(255),
    agent_code character varying(255),
    applicant_id character varying(255),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.users_meta_properties (
    id integer NOT NULL,
    name character varying(255),
    type character varying(255),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.users_mile_stone (
    user_id integer NOT NULL,
    mile_stone_id integer NOT NULL,
    achieved_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.users_notifications (
    id bigint NOT NULL,
    manager_id bigint NOT NULL,
    type integer,
    topic text,
    condition text,
    sent_status integer DEFAULT 0,
    title text,
    message text,
    scheduled_date timestamp with time zone,
    scheduled_status integer DEFAULT 0,
    extra_data text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    image_url character varying(300),
    number_of_users integer,
    number_of_users_it_sent integer
);
COMMENT ON COLUMN launchpad.users_notifications.type IS '1-Push,2-Email,3-SMS';
COMMENT ON COLUMN launchpad.users_notifications.topic IS 'Mobile,Email';
COMMENT ON COLUMN launchpad.users_notifications.condition IS 'Users with 50% completion';
COMMENT ON COLUMN launchpad.users_notifications.title IS 'Title of notification';
CREATE SEQUENCE launchpad.users_notifications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.users_notifications_id_seq OWNED BY launchpad.users_notifications.id;
CREATE TABLE launchpad.users_progress (
    user_id bigint NOT NULL,
    item_id bigint NOT NULL,
    item_type bigint NOT NULL,
    start_time timestamp with time zone,
    end_time timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.users_rules (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    rule_type smallint DEFAULT '0'::smallint,
    batch_id integer DEFAULT 0 NOT NULL,
    filter_data text,
    send_status smallint DEFAULT '0'::smallint NOT NULL,
    scheduled_date timestamp with time zone NOT NULL,
    company_id bigint NOT NULL,
    number_of_users integer,
    number_of_users_added integer,
    is_active integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN launchpad.users_rules.rule_type IS '0-usermetafilter,1-lms,2-tms';
COMMENT ON COLUMN launchpad.users_rules.filter_data IS 'store default value';
COMMENT ON COLUMN launchpad.users_rules.send_status IS '0-rule created, 1-rule applied to batch, 2-rule deactivated';
CREATE SEQUENCE launchpad.users_rules_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.users_rules_id_seq OWNED BY launchpad.users_rules.id;
CREATE TABLE launchpad.users_timer_challenges (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    quiz_id integer NOT NULL,
    start_time timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    submission_time timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    time_seconds integer DEFAULT 0 NOT NULL
);
CREATE SEQUENCE launchpad.users_timer_challenges_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.users_timer_challenges_id_seq OWNED BY launchpad.users_timer_challenges.id;
CREATE TABLE launchpad.users_timer_challenges_questions (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    question_id integer NOT NULL,
    no_of_options_correct integer NOT NULL,
    start_time timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    submission_time timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    time_seconds timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    quiz_id integer NOT NULL
);
CREATE SEQUENCE launchpad.users_timer_challenges_questions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.users_timer_challenges_questions_id_seq OWNED BY launchpad.users_timer_challenges_questions.id;
CREATE TABLE launchpad.users_tms_data (
    unique_id integer NOT NULL,
    program_id integer NOT NULL,
    user_id bigint,
    status character varying(255),
    batch_no character varying(255),
    batch_name character varying(255),
    program_name character varying(255),
    category_id character varying(255),
    category_name character varying(255),
    batch_completion_date timestamp with time zone,
    start_date_time timestamp with time zone,
    end_date_time timestamp with time zone,
    trainer_code character varying(255),
    trainer_name character varying(255),
    learner_code character varying(255),
    learner_name character varying(255),
    learner_email character varying(255),
    learner_mobile character varying(45),
    learner_agent_code character varying(255),
    learner_application_no character varying(255),
    designation character varying(255),
    business_designation character varying(255),
    user_type character varying(255),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE launchpad.users_user_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.users_user_id_seq OWNED BY launchpad.users.user_id;
CREATE TABLE launchpad.vc_batch_has_category (
    id_batch bigint NOT NULL,
    id_category bigint NOT NULL,
    is_open smallint DEFAULT '0'::smallint,
    sequence bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.vc_batch_has_reviewer (
    id_batch bigint NOT NULL,
    id_reviewer bigint NOT NULL,
    id_category bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.vc_category (
    id_category bigint NOT NULL,
    name character varying(255) NOT NULL,
    description text NOT NULL,
    image_url text,
    is_open smallint DEFAULT '0'::smallint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    last_updated_by integer
);
CREATE TABLE launchpad.vc_category_has_reviewer (
    id_category bigint NOT NULL,
    id_reviewer bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    last_updated_at integer NOT NULL
);
CREATE SEQUENCE launchpad.vc_category_id_category_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.vc_category_id_category_seq OWNED BY launchpad.vc_category.id_category;
CREATE TABLE launchpad.vc_challenges (
    id_challenge bigint NOT NULL,
    name character varying(255) DEFAULT ''::character varying NOT NULL,
    description text,
    status smallint DEFAULT '0'::smallint NOT NULL,
    start_time timestamp with time zone NOT NULL,
    expiry_time timestamp with time zone NOT NULL,
    duration_seconds integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    sample_video_url text,
    keywords text,
    keywords_to_use text,
    keywords_not_use text,
    keywords_not_to_use text,
    ai_enabled boolean DEFAULT false
);
CREATE SEQUENCE launchpad.vc_challenges_id_challenge_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.vc_challenges_id_challenge_seq OWNED BY launchpad.vc_challenges.id_challenge;
CREATE TABLE launchpad.vc_company_has_reviewers (
    id_company bigint NOT NULL,
    id_reviewer bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.vc_dashboard_categories_completion_rate (
    user_id bigint NOT NULL,
    category_id bigint,
    completion_percentage double precision DEFAULT '0'::double precision,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.vc_dashboard_challenges_completion_rate (
    user_id bigint NOT NULL,
    challenge_id bigint,
    completion_percentage double precision DEFAULT '0'::double precision,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.vc_dashboard_evaluation_param_completion_rate (
    user_id bigint NOT NULL,
    id_evaluation bigint,
    completion_percentage double precision DEFAULT '0'::double precision,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.vc_evaluation_params (
    id bigint NOT NULL,
    name character varying(40) NOT NULL,
    description character varying(100),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE SEQUENCE launchpad.vc_evaluation_params_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.vc_evaluation_params_id_seq OWNED BY launchpad.vc_evaluation_params.id;
CREATE TABLE launchpad.vc_groups (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    batch_id integer DEFAULT 0 NOT NULL,
    filter_data text,
    send_status smallint DEFAULT '0'::smallint NOT NULL,
    scheduled_date timestamp with time zone NOT NULL,
    company_id bigint NOT NULL,
    number_of_users integer,
    number_of_users_added integer,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN launchpad.vc_groups.filter_data IS 'store default value';
COMMENT ON COLUMN launchpad.vc_groups.send_status IS '0-rule created, 1-rule applied to batch, 2-rule deactivated';
CREATE SEQUENCE launchpad.vc_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.vc_groups_id_seq OWNED BY launchpad.vc_groups.id;
CREATE TABLE launchpad.vc_mapping_challenge_to_category (
    id_category bigint NOT NULL,
    id_challenge bigint NOT NULL,
    sequence bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    last_updated_by integer
);
CREATE TABLE launchpad.vc_mapping_challenge_to_evaluation (
    id_challenge bigint NOT NULL,
    id_evaluation bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.vc_mapping_user_to_reviewers (
    user_id bigint NOT NULL,
    id_reviewer bigint NOT NULL,
    is_active integer DEFAULT 1 NOT NULL,
    sequence integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.vc_params_aggregate_score (
    id_user bigint NOT NULL,
    id_challenge bigint NOT NULL,
    id_evaluation bigint NOT NULL,
    aggregate_score numeric(10,2) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE launchpad.vc_review_suggestions (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    status boolean,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE SEQUENCE launchpad.vc_review_suggestions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.vc_review_suggestions_id_seq OWNED BY launchpad.vc_review_suggestions.id;
CREATE TABLE launchpad.vc_reviewer_aggregate_score (
    id_reviewer bigint NOT NULL,
    id_user bigint NOT NULL,
    id_challenge bigint NOT NULL,
    aggregate_score numeric(10,2) NOT NULL,
    feedback character varying(300),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    suggestions text,
    frequency text
);
CREATE TABLE launchpad.vc_reviewers (
    id_reviewer bigint NOT NULL,
    name character varying(255) NOT NULL,
    password character varying(255),
    email character varying(255) NOT NULL,
    designation character varying(255) NOT NULL,
    role integer NOT NULL,
    is_active integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE SEQUENCE launchpad.vc_reviewers_id_reviewer_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE launchpad.vc_reviewers_id_reviewer_seq OWNED BY launchpad.vc_reviewers.id_reviewer;
CREATE TABLE launchpad.vc_user_challenges (
    id_user bigint NOT NULL,
    id_challenge bigint NOT NULL,
    status smallint DEFAULT '0'::smallint NOT NULL,
    file_name character varying(20),
    video_mp4_url character varying(2000),
    video_m3u8_url character varying(500),
    thumbnail_url character varying(500),
    duration_seconds integer NOT NULL,
    overall_score double precision DEFAULT '0'::double precision NOT NULL,
    recorded_on timestamp with time zone NOT NULL,
    uploaded_at timestamp with time zone,
    converted_at timestamp with time zone,
    reviewed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    md5_checksum character varying(255),
    output text
);
CREATE TABLE launchpad.vc_user_evaluation_score (
    id_user bigint NOT NULL,
    id_challenge bigint NOT NULL,
    id_evaluation bigint NOT NULL,
    id_reviewer bigint NOT NULL,
    score numeric(10,2) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    publish launchpad.vc_user_evaluation_score_publish DEFAULT '0'::launchpad.vc_user_evaluation_score_publish NOT NULL
);
CREATE TABLE launchpad.vc_users_groups (
    id integer NOT NULL,
    user_id integer NOT NULL,
    group_id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.admin (
    id bigint NOT NULL,
    name character varying(100),
    username character varying(100) NOT NULL,
    password character varying(45),
    id_role integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone,
    parent_user integer DEFAULT 1 NOT NULL,
    failed_attempts smallint DEFAULT '0'::smallint,
    failed_at date,
    account_status smallint DEFAULT '1'::smallint,
    account_block_till timestamp with time zone,
    account_block_at timestamp with time zone,
    csrf_token text
);
COMMENT ON COLUMN smartsell.admin.account_status IS '1-active,2-blocked';
CREATE SEQUENCE smartsell.admin_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.admin_id_seq OWNED BY smartsell.admin.id;
CREATE TABLE smartsell.admin_session (
    id bigint NOT NULL,
    token text,
    ip_address text,
    admin_agent text,
    last_login timestamp with time zone,
    last_logout timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.app_android (
    app_version integer NOT NULL,
    api_version integer NOT NULL,
    meta_db_path character varying(200),
    lookup_db_path character varying(200),
    killable smallint DEFAULT '0'::smallint,
    warnable smallint DEFAULT '0'::smallint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.app_android_version (
    id integer NOT NULL,
    app_id integer NOT NULL,
    app_version integer NOT NULL,
    api_version integer NOT NULL,
    company_id bigint NOT NULL,
    meta_db_path character varying(200),
    lookup_db_path character varying(200),
    killable smallint DEFAULT '0'::smallint,
    warnable smallint DEFAULT '0'::smallint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    admin_id smallint,
    meta_json_path character varying(255)
);
CREATE TABLE smartsell.app_constants (
    id bigint NOT NULL,
    company_id bigint NOT NULL,
    meta_content_version bigint,
    meta_content_flag integer DEFAULT 0,
    lookup_content_version bigint,
    lookup_content_flag integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    meta_json_path text,
    json_object text,
    lookup_json_object text
);
CREATE SEQUENCE smartsell.app_constants_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.app_constants_id_seq OWNED BY smartsell.app_constants.id;
CREATE TABLE smartsell.app_ios (
    app_version integer NOT NULL,
    api_version integer NOT NULL,
    meta_db_path character varying(200),
    lookup_db_path character varying(200),
    killable smallint DEFAULT '0'::smallint,
    warnable smallint DEFAULT '0'::smallint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.app_ios_version (
    id integer NOT NULL,
    app_id integer NOT NULL,
    app_version integer NOT NULL,
    api_version integer NOT NULL,
    company_id bigint NOT NULL,
    meta_db_path character varying(200),
    lookup_db_path character varying(200),
    killable smallint DEFAULT '0'::smallint,
    warnable smallint DEFAULT '0'::smallint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    admin_id smallint
);
CREATE TABLE smartsell.assets (
    id integer NOT NULL,
    content text NOT NULL,
    value text NOT NULL,
    value_ios text NOT NULL,
    text_info text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    user_type_id integer,
    status integer
);
CREATE TABLE smartsell.auth_access_token (
    access_token character varying(25) NOT NULL,
    user_id bigint NOT NULL,
    expiry_time timestamp with time zone,
    access_token_old character varying(25),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.auth_refresh_token (
    refresh_token character varying(25) NOT NULL,
    user_id bigint NOT NULL,
    expiry_time timestamp with time zone,
    refresh_token_old character varying(25),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.company (
    id_company bigint NOT NULL,
    name character varying(255),
    short_name character varying(128),
    address text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    app_configs text,
    signatures text,
    signatureformat text,
    unique_id text,
    launchpad_api_url text,
    launchpad_admin_api_url text
);
CREATE TABLE smartsell.company_admins (
    admin_id integer NOT NULL,
    company_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.company_branding (
    id integer NOT NULL,
    company_id bigint NOT NULL,
    primary_dark character varying(128),
    primary_light character varying(128),
    accent_dark character varying(128),
    accent_light character varying(128),
    secondary_dark character varying(128),
    font_color_dark character varying(128) DEFAULT '#1D1D1D'::character varying,
    font_color_light character varying(128) DEFAULT '#FFFFFF'::character varying,
    secondary_light character varying(128),
    font_family_primary character varying(128) DEFAULT 'Zilla Slab'::character varying,
    font_family_secondary character varying(128) DEFAULT 'Nunito'::character varying,
    heading1_font text,
    heading2_font text,
    heading3_font text,
    heading4_font text,
    heading5_font text,
    paragraph1_font text,
    paragraph2_font text,
    paragraph3_font text,
    icon_mcolletral text,
    icon_ppresentation text,
    icon_potd text,
    icon_dvc text,
    icon_qlinks text,
    icon_timerchallenge text,
    icon_back text,
    icon_search text,
    icon_share text,
    icon_filter text,
    text_configurations text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    icon_profile text,
    icon_sync text,
    icon_timer_challenges_duration text,
    icon_timer_challenges_end_time text,
    icon_timer_challenges_score text,
    icon_timer_challenges_question text,
    icon_company text,
    icon_launchpad text,
    icon_leadgen text,
    poster_signature text,
    poster_salutation text,
    icon_roleplay text,
    homepage_configs text,
    home_screen_layout text
);
CREATE TABLE smartsell.company_countries (
    country_id integer NOT NULL,
    company_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.company_groups (
    id bigint NOT NULL,
    company_id bigint NOT NULL,
    name character varying(255) NOT NULL,
    rule_type smallint DEFAULT '0'::smallint,
    filter_data text,
    send_status smallint DEFAULT '0'::smallint NOT NULL,
    scheduled_date timestamp with time zone,
    number_of_users integer,
    number_of_users_added integer,
    is_active integer DEFAULT 1 NOT NULL,
    last_run_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN smartsell.company_groups.rule_type IS '0-Content,1-Others';
COMMENT ON COLUMN smartsell.company_groups.filter_data IS 'store default value';
COMMENT ON COLUMN smartsell.company_groups.send_status IS '0-rule created, 1-rule applied to batch, 2-rule deactivated';
CREATE SEQUENCE smartsell.company_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.company_groups_id_seq OWNED BY smartsell.company_groups.id;
CREATE SEQUENCE smartsell.company_id_company_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.company_id_company_seq OWNED BY smartsell.company.id_company;
CREATE TABLE smartsell.company_user_group_configs (
    company_id bigint NOT NULL,
    user_group_id bigint NOT NULL,
    home_screen_config json NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.company_user_property (
    id integer NOT NULL,
    company_id bigint NOT NULL,
    meta_name character varying(128),
    display_name character varying(255),
    property_name character varying(255),
    status integer DEFAULT 1 NOT NULL,
    property_type character varying(255),
    is_unique smallint DEFAULT '0'::smallint,
    is_mandatory smallint DEFAULT '0'::smallint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN smartsell.company_user_property.status IS '1-active,0-inactive';
CREATE TABLE smartsell.country (
    id integer NOT NULL,
    short_name character(2) NOT NULL,
    name character varying(45) NOT NULL,
    code character varying(11) DEFAULT ''::character varying,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    status smallint DEFAULT '0'::smallint NOT NULL,
    url text,
    min integer,
    max integer
);
CREATE TABLE smartsell.country_has_companies (
    country_id integer NOT NULL,
    company_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.country_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.country_id_seq OWNED BY smartsell.country.id;
CREATE TABLE smartsell.daily_sync_time (
    id integer NOT NULL,
    user_id integer NOT NULL,
    sync_scheduled_time timestamp with time zone,
    sync_run_time timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.default_mapping_specific_user_directory_content (
    id bigint NOT NULL,
    user_type_id bigint,
    company_id bigint NOT NULL,
    directory_id bigint,
    content_id bigint,
    content_type_id bigint,
    sequence integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone,
    version bigint
);
CREATE TABLE smartsell.group_cards (
    id bigint NOT NULL,
    group_id bigint,
    card_id bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.group_cards_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.group_cards_id_seq OWNED BY smartsell.group_cards.id;
CREATE TABLE smartsell.group_livestreams (
    group_id bigint NOT NULL,
    livestream_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.group_presentations (
    group_id bigint NOT NULL,
    presentation_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.group_products (
    group_id bigint NOT NULL,
    product_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.group_quick_links (
    group_id bigint NOT NULL,
    quick_link_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE TABLE smartsell.group_users (
    group_id bigint NOT NULL,
    user_id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.lookup_mapping_page_to_section (
    page_id integer NOT NULL,
    section_id integer NOT NULL,
    position_in_section integer NOT NULL,
    parameter1 text,
    parameter2 text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.lookup_mapping_product_section (
    product_id integer NOT NULL,
    section_id integer NOT NULL,
    sequence integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    id bigint NOT NULL
);
CREATE SEQUENCE smartsell.lookup_mapping_product_section_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.lookup_mapping_product_section_id_seq OWNED BY smartsell.lookup_mapping_product_section.id;
CREATE TABLE smartsell.lookup_mapping_section_to_presentation (
    presentation_id integer,
    section_id integer,
    default_position integer,
    mandatory integer,
    selected_by_default integer,
    position_fixed integer,
    parameter1 text,
    parameter2 text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.lookup_page_master (
    id integer NOT NULL,
    name character varying(200),
    bg_image text,
    data_set_id integer DEFAULT 0,
    page_type integer,
    parameter1 text,
    parameter2 text,
    version integer DEFAULT 1,
    company_id bigint NOT NULL,
    height integer,
    width integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.lookup_page_master_image_elements (
    id bigint NOT NULL,
    page_id bigint,
    on_by_default smallint,
    top_margin integer,
    left_margin integer,
    width integer,
    height integer,
    shape character varying(45),
    keep_aspect_ratio smallint,
    version_renewed_from integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone,
    profile_image smallint DEFAULT '1'::smallint
);
CREATE SEQUENCE smartsell.lookup_page_master_image_elements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.lookup_page_master_image_elements_id_seq OWNED BY smartsell.lookup_page_master_image_elements.id;
CREATE TABLE smartsell.lookup_page_master_text_elements (
    id bigint NOT NULL,
    page_id bigint,
    default_value character varying(100),
    on_by_default smallint,
    top_margin integer,
    left_margin integer,
    right_margin integer,
    text_alignment character varying(10),
    font_family character varying(45),
    font_size integer,
    font_color character varying(9),
    font_style character varying(45),
    version_renewed_from integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.lookup_page_master_text_elements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.lookup_page_master_text_elements_id_seq OWNED BY smartsell.lookup_page_master_text_elements.id;
CREATE TABLE smartsell.lookup_page_types (
    id integer NOT NULL,
    name character varying(255)
);
CREATE TABLE smartsell.lookup_presentation_category (
    id integer NOT NULL,
    company_id integer NOT NULL,
    name character varying(45),
    description character varying(45),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone,
    sequence integer DEFAULT 0 NOT NULL
);
CREATE TABLE smartsell.lookup_presentation_dataset (
    id integer NOT NULL,
    name character varying(255),
    data text
);
CREATE TABLE smartsell.lookup_presentation_display_data (
    general_presentation_top_image1 character varying(500),
    presentation_page2_disclaimer character varying(500),
    presentation_page3_disclaimer character varying(500),
    presentation_page2_heading character varying(500),
    presentation_page3_heading character varying(500),
    tenure_icon character varying(500),
    liquidity_icon character varying(500),
    product_label_icon character varying(500),
    selection_page1_disclaimer character varying(500),
    selection_page2_disclaimer character varying(500),
    selection_page3_disclaimer character varying(500),
    tenure_heading character varying(500),
    tenure_intro character varying(500),
    liquidity_heading character varying(500),
    liquidity_intro character varying(500),
    suggestion_heading character varying(500)
);
CREATE TABLE smartsell.lookup_presentation_master (
    id integer NOT NULL,
    company_id bigint NOT NULL,
    category_id integer,
    name character varying(200),
    element1_display integer DEFAULT 1 NOT NULL,
    element1_label character varying(200),
    element1_mandatory integer DEFAULT 1 NOT NULL,
    element2_display integer DEFAULT 1 NOT NULL,
    element2_label character varying(200),
    element2_mandatory integer,
    element3_display integer DEFAULT 1 NOT NULL,
    element3_mandatory smallint DEFAULT '1'::smallint,
    element3_label character varying(200),
    element1_hint character varying(200),
    element2_hint character varying(200),
    element3_hint character varying(200),
    element1_readonly character varying(200),
    element2_readonly character varying(200),
    element3_readonly character varying(200),
    share_text_subject character varying(300),
    share_text_body character varying(300),
    sequence integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone,
    element_customer_number character varying(200)
);
CREATE TABLE smartsell.lookup_product (
    id integer NOT NULL,
    category_id integer NOT NULL,
    name character varying(255),
    short_name character varying(128),
    icon character varying(128),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    company_id bigint NOT NULL,
    sequence integer NOT NULL,
    description character varying(255),
    discription text
);
CREATE TABLE smartsell.lookup_product_benefit (
    id integer NOT NULL,
    benefit_category_id integer NOT NULL,
    name text,
    sequence integer,
    section_id integer NOT NULL,
    parameter1_value text,
    parameter2_value text,
    parameter3_value text,
    parameter4_value text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.lookup_product_benefit_category (
    id integer NOT NULL,
    section_id integer NOT NULL,
    name text,
    description text,
    benefits_header text,
    benefits_row_header text,
    disclaimer text,
    parameter1 text,
    parameter2 text,
    parameter3 text,
    parameter4 text,
    sequence integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone,
    parameter_header text
);
CREATE TABLE smartsell.lookup_product_bulletlist_collateral (
    id integer NOT NULL,
    section_id integer NOT NULL,
    bulletlist_header text,
    bulletlist_points json,
    bulletlist_disclaimer text,
    video_name character varying(255),
    video_description text,
    video_button_name character varying(255),
    video_url text,
    video_thumbnail_url text,
    onepager_button_name character varying(255),
    onepager_header text,
    onepager_url text,
    brochure_button_name character varying(255),
    brochure_link text,
    is_video smallint DEFAULT '0'::smallint,
    is_bullet smallint DEFAULT '0'::smallint,
    is_onepager smallint DEFAULT '0'::smallint,
    is_brochure smallint DEFAULT '0'::smallint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    is_sharing_bulletlist smallint DEFAULT '0'::smallint,
    is_sharing_onepager smallint DEFAULT '0'::smallint,
    is_sharing_video smallint DEFAULT '0'::smallint,
    is_sharing_brochure smallint DEFAULT '1'::smallint
);
COMMENT ON COLUMN smartsell.lookup_product_bulletlist_collateral.video_thumbnail_url IS 'Video Thumbnail';
CREATE TABLE smartsell.lookup_product_bulletlist_multiple (
    id integer NOT NULL,
    section_id integer NOT NULL,
    header text,
    header_description text,
    points json,
    disclaimer text,
    sequence integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.lookup_product_category (
    id integer NOT NULL,
    name character varying(255),
    sequence integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    company_id bigint NOT NULL,
    description text
);
CREATE TABLE smartsell.lookup_product_faq (
    id integer NOT NULL,
    section_id integer NOT NULL,
    question text,
    answer text,
    video_name character varying(255),
    video_url text,
    video_thumbnail_url text,
    video_description text,
    sequence integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN smartsell.lookup_product_faq.video_thumbnail_url IS 'Video Thumbnail';
CREATE TABLE smartsell.lookup_product_section (
    id integer NOT NULL,
    sectiontype_id integer NOT NULL,
    name character varying(255),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    company_id bigint NOT NULL
);
CREATE TABLE smartsell.lookup_product_sectiontype (
    id integer NOT NULL,
    name character varying(255),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.lookup_quick_links (
    quick_link_id integer NOT NULL,
    company_id bigint NOT NULL,
    quick_link_title character varying(256),
    quick_link_message text,
    quick_link_action_text character varying(256),
    quick_link_url text,
    sequence integer
);
CREATE TABLE smartsell.lookup_section_master (
    id integer NOT NULL,
    name character varying(200),
    overview_name character varying(200),
    parameter1 character varying(200),
    parameter2 character varying(200),
    company_id bigint NOT NULL,
    sequence integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.mapping_channel_to_presentation (
    channel_name character varying(45) NOT NULL,
    presentation_category_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.mapping_new_items (
    id bigint NOT NULL,
    user_type_id bigint,
    content_id bigint,
    content_type_id bigint,
    sequence integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.mapping_new_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.mapping_new_items_id_seq OWNED BY smartsell.mapping_new_items.id;
CREATE TABLE smartsell.mapping_specific_user_directory_content (
    id bigint NOT NULL,
    user_type_id bigint,
    company_id bigint NOT NULL,
    directory_id bigint,
    content_id bigint,
    content_type_id bigint,
    sequence integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.mapping_specific_user_directory_content_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.mapping_specific_user_directory_content_id_seq OWNED BY smartsell.mapping_specific_user_directory_content.id;
CREATE TABLE smartsell.mapping_timer_challenges_to_user_group (
    id bigint NOT NULL,
    user_group_id bigint,
    quiz_id integer NOT NULL,
    sequence integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.mapping_timer_challenges_to_user_group_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.mapping_timer_challenges_to_user_group_id_seq OWNED BY smartsell.mapping_timer_challenges_to_user_group.id;
CREATE TABLE smartsell.mapping_timer_challenges_to_user_type (
    id bigint NOT NULL,
    user_type_id bigint,
    quiz_id integer NOT NULL,
    sequence integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.mapping_timer_challenges_to_user_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.mapping_timer_challenges_to_user_type_id_seq OWNED BY smartsell.mapping_timer_challenges_to_user_type.id;
CREATE TABLE smartsell.mapping_user_directory_content (
    id bigint NOT NULL,
    company_id bigint NOT NULL,
    user_type_id bigint,
    directory_id bigint,
    content_id bigint,
    content_type_id bigint,
    sequence integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.mapping_user_directory_content_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.mapping_user_directory_content_id_seq OWNED BY smartsell.mapping_user_directory_content.id;
CREATE TABLE smartsell.mapping_user_home_banner (
    item_id bigint NOT NULL,
    company_id bigint NOT NULL,
    user_type_id bigint NOT NULL,
    item_type smallint,
    carosel_type smartsell.mapping_user_home_banner_carosel_type,
    title text,
    description text,
    action_target character varying(127),
    action_text text,
    extra_data text,
    image_url text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.mapping_user_home_banner_item_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.mapping_user_home_banner_item_id_seq OWNED BY smartsell.mapping_user_home_banner.item_id;
CREATE TABLE smartsell.mapping_user_home_content (
    id bigint NOT NULL,
    company_id bigint NOT NULL,
    user_type_id bigint,
    content_id bigint,
    content_type_id bigint,
    sequence integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.mapping_user_home_content_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.mapping_user_home_content_id_seq OWNED BY smartsell.mapping_user_home_content.id;
CREATE TABLE smartsell.mapping_user_home_directory_content (
    id bigint NOT NULL,
    user_type_id bigint DEFAULT '1'::bigint NOT NULL,
    company_id bigint NOT NULL,
    content_id bigint,
    content_type_id bigint,
    sequence integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.mapping_user_home_directory_content_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.mapping_user_home_directory_content_id_seq OWNED BY smartsell.mapping_user_home_directory_content.id;
CREATE TABLE smartsell.mapping_user_home_page (
    id bigint NOT NULL,
    user_type_id bigint NOT NULL,
    item_type bigint NOT NULL,
    item_id bigint,
    sequence bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.mapping_user_home_page_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.mapping_user_home_page_id_seq OWNED BY smartsell.mapping_user_home_page.id;
CREATE TABLE smartsell.mapping_user_home_top_slider (
    id bigint NOT NULL,
    user_type_id bigint,
    title text,
    action_target text,
    action_text text,
    extra_data integer,
    image_url text,
    sequence smallint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.mapping_user_home_top_slider_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.mapping_user_home_top_slider_id_seq OWNED BY smartsell.mapping_user_home_top_slider.id;
CREATE TABLE smartsell.mapping_user_types (
    id integer NOT NULL,
    channel_code character varying(45),
    sub_channel_code character varying(45),
    ingenium_code character varying(45),
    designation_code character varying(45),
    user_type_name character varying(125) NOT NULL,
    user_type_id integer NOT NULL
);
CREATE TABLE smartsell.meta_cards (
    id bigint NOT NULL,
    company_id bigint NOT NULL,
    name character varying(128),
    description character varying(300),
    share_text character varying(300),
    reg_name character varying(128),
    reg_description character varying(300),
    reg_share_text character varying(300),
    thumbnail_url character varying(300),
    image_url character varying(300),
    image_md5_hash character varying(128),
    image_version integer DEFAULT 1,
    language_id integer DEFAULT 1 NOT NULL,
    card_width integer,
    card_height integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.meta_cards_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_cards_id_seq OWNED BY smartsell.meta_cards.id;
CREATE TABLE smartsell.meta_cards_image_elements (
    id bigint NOT NULL,
    card_id bigint,
    on_by_default smallint,
    top_margin integer,
    left_margin integer,
    width integer,
    height integer,
    shape character varying(45),
    keep_aspect_ratio smallint,
    profile_image smallint DEFAULT '1'::smallint,
    images text,
    bg_color character varying(9),
    is_bg_color integer DEFAULT 0,
    star_rating smallint DEFAULT '0'::smallint,
    qr_code integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN smartsell.meta_cards_image_elements.images IS '  [{
"id":1,
"sequence":1,
"image":"https://url.jpg",
"updated_at":"2020-08-17 10:10:10"
},
{
"id":2,
"sequence":2,
"image":"https://url.jpg",
"updated_at":"2020-08-17 10:10:10"
}]';
CREATE SEQUENCE smartsell.meta_cards_image_elements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_cards_image_elements_id_seq OWNED BY smartsell.meta_cards_image_elements.id;
CREATE TABLE smartsell.meta_cards_text_elements (
    id bigint NOT NULL,
    card_id bigint,
    default_value character varying(255),
    on_by_default smallint,
    read_only smallint DEFAULT '1'::smallint,
    top_margin integer,
    left_margin integer,
    right_margin integer,
    text_alignment character varying(10),
    font_family character varying(45),
    font_size integer,
    font_color character varying(9),
    is_recognition integer DEFAULT 0,
    font_style character varying(45),
    font_weight character varying(45),
    bg_color character varying(9),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.meta_cards_text_elements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_cards_text_elements_id_seq OWNED BY smartsell.meta_cards_text_elements.id;
CREATE TABLE smartsell.meta_channel (
    channel_id integer NOT NULL,
    channel character varying(45),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.meta_channels (
    id integer NOT NULL,
    channel_code character varying(255) NOT NULL,
    channel_name character varying(255) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE TABLE smartsell.meta_configs (
    id integer NOT NULL,
    field_name character varying(255) NOT NULL,
    app_field_name character varying(255),
    status integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.meta_content_types (
    id bigint NOT NULL,
    content_type character varying(45),
    content_type_constant integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.meta_content_types_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_content_types_id_seq OWNED BY smartsell.meta_content_types.id;
CREATE TABLE smartsell.meta_daily_posters (
    id_meta_daily_poster bigint NOT NULL,
    id bigint NOT NULL,
    poster_date timestamp with time zone,
    version bigint DEFAULT '1'::bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone,
    company_id bigint NOT NULL
);
CREATE SEQUENCE smartsell.meta_daily_posters_id_meta_daily_poster_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_daily_posters_id_meta_daily_poster_seq OWNED BY smartsell.meta_daily_posters.id_meta_daily_poster;
CREATE TABLE smartsell.meta_directories (
    id bigint NOT NULL,
    company_id bigint NOT NULL,
    name character varying(45),
    description character varying(300),
    thumbnail_url character varying(300),
    thumbnail_md5_hash character varying(45),
    image_version integer DEFAULT 1,
    display_type_id bigint,
    confidential integer DEFAULT 0,
    screenshot smallint DEFAULT '1'::smallint NOT NULL,
    version_renewed_from integer DEFAULT 1,
    uploaded_by integer,
    updated_by integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone,
    only_folder_allowed smallint
);
COMMENT ON COLUMN smartsell.meta_directories.screenshot IS '1-enable,0-disable';
CREATE SEQUENCE smartsell.meta_directories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_directories_id_seq OWNED BY smartsell.meta_directories.id;
CREATE TABLE smartsell.meta_directories_language (
    directory_id integer NOT NULL,
    language_id integer NOT NULL,
    name character varying(100) NOT NULL,
    description character varying(300),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.meta_directories_versions (
    id bigint NOT NULL,
    name character varying(45),
    description character varying(300),
    thumbnail_url character varying(300),
    thumbnail_md5_hash character varying(45),
    image_version integer DEFAULT 1,
    display_type_id bigint,
    confidential integer DEFAULT 0,
    screenshot smallint DEFAULT '1'::smallint NOT NULL,
    directory_id bigint NOT NULL,
    version integer DEFAULT 1,
    version_restored_from integer,
    version_timestamp timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    uploaded_by integer,
    updated_by integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN smartsell.meta_directories_versions.screenshot IS '1-enable,0-disable';
CREATE SEQUENCE smartsell.meta_directories_versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_directories_versions_id_seq OWNED BY smartsell.meta_directories_versions.id;
CREATE TABLE smartsell.meta_directory_display_types (
    id bigint NOT NULL,
    display_type character varying(45),
    display_type_constant integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.meta_directory_display_types_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_directory_display_types_id_seq OWNED BY smartsell.meta_directory_display_types.id;
CREATE TABLE smartsell.meta_fs_achievements (
    id integer NOT NULL,
    level integer,
    fs_item_count integer,
    fs_achievement character varying(45),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.meta_home_page_item_types (
    id bigint NOT NULL,
    item_type bigint NOT NULL,
    name character varying(255),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.meta_home_page_item_types_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_home_page_item_types_id_seq OWNED BY smartsell.meta_home_page_item_types.id;
CREATE TABLE smartsell.meta_languages (
    id bigint NOT NULL,
    language character varying(45),
    reg_language character varying(100),
    short_language character varying(20),
    sequence smallint NOT NULL,
    required smallint DEFAULT '0'::smallint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.meta_languages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_languages_id_seq OWNED BY smartsell.meta_languages.id;
CREATE TABLE smartsell.meta_livestream (
    id integer NOT NULL,
    company_id bigint NOT NULL,
    content text NOT NULL,
    value text NOT NULL,
    value_ios text NOT NULL,
    text_info text,
    status integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.meta_mm_achievements (
    id integer NOT NULL,
    level integer,
    mm_item_count integer,
    mm_achievement character varying(45),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.meta_page_master (
    id integer NOT NULL,
    name character varying(255),
    bg_image character varying(255),
    data_set_id character varying(255),
    page_type character varying(255),
    parameter1 character varying(255),
    parameter2 character varying(255),
    version integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.meta_page_types (
    id integer NOT NULL,
    name character varying(255),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.meta_pdfs (
    id bigint NOT NULL,
    company_id bigint NOT NULL,
    name character varying(128),
    description character varying(300),
    share_text character varying(300),
    reg_name character varying(128),
    reg_description character varying(300),
    reg_share_text character varying(300),
    thumbnail_url character varying(200),
    thumbnail_md5_hash character varying(128),
    image_version integer DEFAULT 1,
    pdf_url character varying(200),
    pdf_md5_hash character varying(128),
    pdf_version integer DEFAULT 1,
    language_id integer DEFAULT 1 NOT NULL,
    version_renewed_from integer,
    uploaded_by integer,
    updated_by integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.meta_pdfs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_pdfs_id_seq OWNED BY smartsell.meta_pdfs.id;
CREATE TABLE smartsell.meta_pdfs_tags (
    id bigint NOT NULL,
    pdf_id bigint NOT NULL,
    tag_id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.meta_pdfs_tags_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_pdfs_tags_id_seq OWNED BY smartsell.meta_pdfs_tags.id;
CREATE TABLE smartsell.meta_pdfs_versions (
    id bigint NOT NULL,
    name character varying(128),
    description character varying(300),
    share_text character varying(300),
    reg_name character varying(128),
    reg_description character varying(300),
    reg_share_text character varying(300),
    thumbnail_url character varying(200),
    thumbnail_md5_hash character varying(128),
    image_version integer DEFAULT 1,
    pdf_url character varying(200),
    pdf_md5_hash character varying(128),
    pdf_version integer DEFAULT 1,
    language_id integer DEFAULT 1 NOT NULL,
    pdf_id bigint NOT NULL,
    version integer,
    version_restored_from integer,
    version_timestamp timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    uploaded_by integer,
    updated_by integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.meta_pdfs_versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_pdfs_versions_id_seq OWNED BY smartsell.meta_pdfs_versions.id;
CREATE TABLE smartsell.meta_posters (
    id bigint NOT NULL,
    company_id bigint NOT NULL,
    name character varying(128),
    description character varying(300),
    share_text character varying(300),
    reg_name character varying(128),
    reg_description character varying(300),
    reg_share_text character varying(300),
    thumbnail_url character varying(300),
    image_url character varying(300),
    image_md5_hash character varying(128),
    image_version integer DEFAULT 1,
    language_id integer DEFAULT 1 NOT NULL,
    version_renewed_from integer,
    uploaded_by integer,
    updated_by integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.meta_posters_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_posters_id_seq OWNED BY smartsell.meta_posters.id;
CREATE TABLE smartsell.meta_posters_image_elements (
    id bigint NOT NULL,
    poster_id bigint,
    on_by_default smallint,
    top_margin integer,
    left_margin integer,
    width integer,
    height integer,
    shape character varying(45),
    keep_aspect_ratio smallint,
    version_renewed_from integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.meta_posters_image_elements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_posters_image_elements_id_seq OWNED BY smartsell.meta_posters_image_elements.id;
CREATE TABLE smartsell.meta_posters_image_elements_versions (
    id bigint NOT NULL,
    poster_id bigint,
    on_by_default smallint,
    top_margin integer,
    left_margin integer,
    width integer,
    height integer,
    shape character varying(45),
    keep_aspect_ratio smallint,
    image_element_id bigint NOT NULL,
    version integer,
    version_restored_from integer,
    version_timestamp timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.meta_posters_image_elements_versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_posters_image_elements_versions_id_seq OWNED BY smartsell.meta_posters_image_elements_versions.id;
CREATE TABLE smartsell.meta_posters_tags (
    id bigint NOT NULL,
    poster_id bigint NOT NULL,
    tag_id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.meta_posters_tags_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_posters_tags_id_seq OWNED BY smartsell.meta_posters_tags.id;
CREATE TABLE smartsell.meta_posters_text_elements (
    id bigint NOT NULL,
    poster_id bigint,
    default_value character varying(100),
    on_by_default smallint,
    top_margin integer,
    left_margin integer,
    right_margin integer,
    text_alignment character varying(10),
    font_family character varying(45),
    font_size integer,
    font_color character varying(9),
    version_renewed_from integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.meta_posters_text_elements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_posters_text_elements_id_seq OWNED BY smartsell.meta_posters_text_elements.id;
CREATE TABLE smartsell.meta_posters_text_elements_versions (
    id bigint NOT NULL,
    poster_id bigint,
    default_value character varying(100),
    on_by_default smallint,
    top_margin integer,
    left_margin integer,
    right_margin integer,
    text_alignment character varying(10),
    font_family character varying(45),
    font_size integer,
    font_color character varying(9),
    text_element_id bigint NOT NULL,
    version integer,
    version_restored_from integer,
    version_timestamp timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.meta_posters_text_elements_versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_posters_text_elements_versions_id_seq OWNED BY smartsell.meta_posters_text_elements_versions.id;
CREATE TABLE smartsell.meta_posters_versions (
    id bigint NOT NULL,
    name character varying(128),
    description character varying(300),
    share_text character varying(300),
    reg_name character varying(128),
    reg_description character varying(300),
    reg_share_text character varying(300),
    thumbnail_url character varying(300),
    image_url character varying(300),
    image_md5_hash character varying(128),
    image_version integer DEFAULT 1,
    language_id integer DEFAULT 1 NOT NULL,
    poster_id bigint NOT NULL,
    version integer DEFAULT 1,
    version_restored_from integer,
    version_timestamp timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    uploaded_by integer,
    updated_by integer,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.meta_posters_versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_posters_versions_id_seq OWNED BY smartsell.meta_posters_versions.id;
CREATE TABLE smartsell.meta_presentation_category_master (
    id integer NOT NULL,
    name character varying(255),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.meta_presentation_dataset (
    id integer NOT NULL,
    data text,
    name character varying(40) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.meta_presentation_master (
    id integer NOT NULL,
    name text,
    parameter1 text,
    parameter2 text,
    target_id integer,
    presentation_category_id integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.meta_push_targets (
    target_id integer NOT NULL,
    target_name character varying(45) NOT NULL,
    target_value character varying(45) NOT NULL,
    target_extra_type integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.meta_recognitions (
    id bigint NOT NULL,
    company_id bigint NOT NULL,
    name character varying(255) NOT NULL,
    url character varying(255) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.meta_recognitions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_recognitions_id_seq OWNED BY smartsell.meta_recognitions.id;
CREATE TABLE smartsell.meta_section_master (
    id integer NOT NULL,
    name text,
    overview_name text,
    parameter1 text,
    parameter2 text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.meta_sub_channels (
    id integer NOT NULL,
    channel_code character varying(255) NOT NULL,
    sub_channel_code character varying(255) NOT NULL,
    sub_channel_name character varying(255) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE TABLE smartsell.meta_tags (
    id bigint NOT NULL,
    name character varying(128),
    description character varying(300),
    status integer DEFAULT 1,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.meta_tags_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_tags_id_seq OWNED BY smartsell.meta_tags.id;
CREATE TABLE smartsell.meta_target_group_master (
    id integer NOT NULL,
    name text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.meta_timer_challenges (
    id bigint NOT NULL,
    name character varying(255),
    quiz_type integer DEFAULT 1,
    url character varying(255),
    pass_failed_enabled boolean DEFAULT false NOT NULL,
    show_score bigint DEFAULT '1'::bigint NOT NULL,
    leaderboard_flag bigint DEFAULT '1'::bigint NOT NULL,
    leaderboard_type bigint DEFAULT '1'::bigint NOT NULL,
    leaderboard_winner bigint DEFAULT '1'::bigint NOT NULL,
    description text,
    question_json text,
    answer_result integer DEFAULT 0 NOT NULL,
    show_explanation integer DEFAULT 0 NOT NULL,
    json_updated_flag boolean DEFAULT false NOT NULL,
    max_duration integer DEFAULT 0,
    start_time timestamp with time zone NOT NULL,
    end_time timestamp with time zone NOT NULL,
    contribution integer DEFAULT 10 NOT NULL,
    rollback smartsell.meta_timer_challenges_rollback DEFAULT ''::smartsell.meta_timer_challenges_rollback,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    is_freezed smallint DEFAULT '0'::smallint NOT NULL,
    company_id bigint NOT NULL
);
COMMENT ON COLUMN smartsell.meta_timer_challenges.is_freezed IS '0-not freezed, 1,freezed';
CREATE SEQUENCE smartsell.meta_timer_challenges_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_timer_challenges_id_seq OWNED BY smartsell.meta_timer_challenges.id;
CREATE TABLE smartsell.meta_timer_challenges_language (
    id bigint NOT NULL,
    id_language integer NOT NULL,
    name character varying(255),
    description text,
    question_json text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    points text
);
CREATE SEQUENCE smartsell.meta_timer_challenges_language_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_timer_challenges_language_id_seq OWNED BY smartsell.meta_timer_challenges_language.id;
CREATE TABLE smartsell.meta_timer_challenges_questions (
    id_meta_timer_challenges_questions integer NOT NULL,
    question_id integer NOT NULL,
    quiz_id integer NOT NULL,
    id_language integer NOT NULL,
    skill_id integer DEFAULT 0 NOT NULL,
    question text,
    answer integer NOT NULL,
    answer_line text,
    explanation text,
    choices text,
    choice_type integer DEFAULT 0 NOT NULL,
    image_url text,
    select_count integer DEFAULT 0 NOT NULL,
    bucket_1_text character varying(255),
    bucket_2_text character varying(255),
    contribution integer DEFAULT 10 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.meta_user_types (
    id bigint NOT NULL,
    user_type character varying(45),
    user_type_constant integer,
    channel_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.meta_user_types_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_user_types_id_seq OWNED BY smartsell.meta_user_types.id;
CREATE TABLE smartsell.meta_videos (
    id bigint NOT NULL,
    company_id bigint NOT NULL,
    name character varying(128),
    description character varying(300),
    share_text character varying(300),
    reg_name character varying(128),
    reg_description character varying(300),
    reg_share_text character varying(300),
    thumbnail_url character varying(200),
    thumbnail_md5_hash character varying(128),
    language_id integer DEFAULT 1 NOT NULL,
    video_url character varying(200),
    is_public integer DEFAULT 0,
    image_version integer DEFAULT 1,
    version_renewed_from integer,
    uploaded_by integer,
    updated_by integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN smartsell.meta_videos.is_public IS '0-Youtube,1-AWS library';
CREATE SEQUENCE smartsell.meta_videos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_videos_id_seq OWNED BY smartsell.meta_videos.id;
CREATE TABLE smartsell.meta_videos_tags (
    id bigint NOT NULL,
    video_id bigint NOT NULL,
    tag_id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.meta_videos_tags_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_videos_tags_id_seq OWNED BY smartsell.meta_videos_tags.id;
CREATE TABLE smartsell.meta_videos_versions (
    id bigint NOT NULL,
    name character varying(128),
    description character varying(300),
    share_text character varying(300),
    reg_name character varying(128),
    reg_description character varying(300),
    reg_share_text character varying(300),
    thumbnail_url character varying(200),
    thumbnail_md5_hash character varying(128),
    language_id integer DEFAULT 1,
    video_url character varying(200),
    image_version integer DEFAULT 1,
    video_id bigint NOT NULL,
    version integer,
    version_restored_from integer,
    version_timestamp timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    uploaded_by integer,
    updated_by integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.meta_videos_versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.meta_videos_versions_id_seq OWNED BY smartsell.meta_videos_versions.id;
CREATE TABLE smartsell.migrations (
    id bigint NOT NULL,
    migration character varying(255) NOT NULL,
    batch integer NOT NULL
);
CREATE SEQUENCE smartsell.migrations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.migrations_id_seq OWNED BY smartsell.migrations.id;
CREATE TABLE smartsell.module (
    id_module bigint NOT NULL,
    name character varying(255) NOT NULL,
    name_duplicate character varying(255) NOT NULL,
    status integer DEFAULT 1 NOT NULL,
    module_group character varying(255),
    module_group_sequence bigint DEFAULT '100'::bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone,
    description text
);
COMMENT ON COLUMN smartsell.module.name IS 'batch_create';
COMMENT ON COLUMN smartsell.module.name_duplicate IS 'Batch Create';
COMMENT ON COLUMN smartsell.module.status IS '1-active; 0-inactive';
COMMENT ON COLUMN smartsell.module.description IS 'short description about the module';
CREATE SEQUENCE smartsell.module_id_module_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.module_id_module_seq OWNED BY smartsell.module.id_module;
CREATE TABLE smartsell.old_mapping_page_to_section (
    page_id integer,
    section_id integer,
    position_in_section integer,
    parameter1 text,
    parameter2 text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.old_mapping_presentation_category_to_target (
    id integer NOT NULL,
    target_id integer,
    presentation_category_id integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.old_mapping_presentation_to_section (
    presentation_id integer,
    section_id integer,
    default_position integer,
    mandatory integer,
    selected_by_default integer,
    position_fixed integer,
    parameter1 text,
    parameter2 text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.old_users_groups (
    id integer NOT NULL,
    name character varying(255),
    description character varying(255),
    is_active integer DEFAULT 1 NOT NULL,
    channel_code character varying(255) NOT NULL,
    sub_channel_code character varying(255) NOT NULL,
    ingenium_channel_code character varying(45) NOT NULL,
    designation text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE smartsell.push_sync_time (
    id integer NOT NULL,
    user_id integer NOT NULL,
    sync_scheduled_time timestamp with time zone,
    sync_run_time timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.quiz_challenge (
    id_quiz bigint NOT NULL,
    title character varying(255) NOT NULL,
    info text,
    reward text,
    status boolean DEFAULT true NOT NULL,
    time_text_normal text,
    time_text_later text,
    quiz_type text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN smartsell.quiz_challenge.status IS '1-active,0-Inactive';
CREATE SEQUENCE smartsell.quiz_challenge_id_quiz_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.quiz_challenge_id_quiz_seq OWNED BY smartsell.quiz_challenge.id_quiz;
CREATE TABLE smartsell.quiz_question (
    id_question bigint NOT NULL,
    id_quiz bigint NOT NULL,
    question text NOT NULL,
    options text NOT NULL,
    marks bigint DEFAULT '1'::bigint NOT NULL,
    status smallint DEFAULT '1'::smallint NOT NULL,
    answer bigint NOT NULL,
    answer_line text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN smartsell.quiz_question.options IS '{ 	"options": [{ 		"option": "A" 	}, { 		"option": "B" 	}, { 		"option": "C" 	}, { 		"option": "D" 	}] }';
COMMENT ON COLUMN smartsell.quiz_question.status IS '1-active,0-inactive';
CREATE SEQUENCE smartsell.quiz_question_id_question_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.quiz_question_id_question_seq OWNED BY smartsell.quiz_question.id_question;
CREATE TABLE smartsell.quiz_type (
    id_quiz_type integer NOT NULL,
    name character varying(255),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.role (
    id_role bigint NOT NULL,
    name character varying(255),
    roles text,
    status integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
COMMENT ON COLUMN smartsell.role.status IS '1-active; 0-inactive';
CREATE TABLE smartsell.role_has_module (
    id_role_has_module integer NOT NULL,
    role_id_role bigint NOT NULL,
    module_id_module bigint NOT NULL,
    status boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    module_name character varying(100),
    extra_data character varying(40)
);
CREATE SEQUENCE smartsell.role_has_module_id_role_has_module_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.role_has_module_id_role_has_module_seq OWNED BY smartsell.role_has_module.id_role_has_module;
CREATE SEQUENCE smartsell.role_id_role_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.role_id_role_seq OWNED BY smartsell.role.id_role;
CREATE TABLE smartsell.server_health (
    id integer NOT NULL,
    health bigint DEFAULT '0'::bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.testing (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.testing_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.testing_id_seq OWNED BY smartsell.testing.id;
CREATE TABLE smartsell.user_achievements (
    user_id bigint NOT NULL,
    achievement_level integer NOT NULL,
    achieved_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.user_announcements (
    id bigint NOT NULL,
    user_type_id bigint NOT NULL,
    title character varying(100),
    message character varying(200),
    action_target character varying(45),
    action_text character varying(45),
    extra_data character varying(300),
    show_again smallint,
    frequency integer,
    start_date date,
    end_date date,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.user_announcements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.user_announcements_id_seq OWNED BY smartsell.user_announcements.id;
CREATE TABLE smartsell.user_excel (
    user_id bigint NOT NULL,
    company_id bigint NOT NULL,
    mobile_number character varying(10),
    name character varying(100),
    username character varying(45),
    email character varying(100),
    user_group_id bigint,
    activation_status smallint DEFAULT '0'::smallint,
    registered_status smallint DEFAULT '0'::smallint,
    country_code character varying(15) DEFAULT '+91'::character varying,
    status character varying(100),
    message character varying(100),
    meta1 character varying(255),
    meta2 character varying(255),
    meta3 character varying(255),
    meta4 character varying(255),
    meta5 character varying(255),
    meta6 bigint,
    meta7 bigint,
    meta8 bigint,
    meta9 date,
    meta10 date,
    meta11 character varying(255),
    meta12 character varying(255),
    meta13 character varying(255),
    meta14 character varying(255),
    meta15 character varying(255),
    meta16 character varying(255),
    meta17 character varying(255),
    meta18 character varying(255),
    meta19 character varying(255),
    meta20 character varying(255),
    operation_type character varying(100) NOT NULL,
    uploaded_at timestamp with time zone
);
CREATE SEQUENCE smartsell.user_excel_user_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.user_excel_user_id_seq OWNED BY smartsell.user_excel.user_id;
CREATE TABLE smartsell.user_favorites (
    user_id bigint NOT NULL,
    content_id bigint NOT NULL,
    content_type_id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.user_feedback (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    message text NOT NULL,
    app_version integer,
    mobile character varying(10),
    meta_db_version integer,
    email character varying(100),
    name character varying(100),
    user_type_id bigint,
    custom_field1 character varying(255),
    custom_field2 character varying(255),
    device_id character varying(100),
    feedback_screen_source character varying(255),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone,
    device_model character varying(100),
    os_version character varying(100),
    screen_size character varying(100),
    mail_sent integer DEFAULT 0,
    agent_code character varying(45)
);
CREATE SEQUENCE smartsell.user_feedback_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.user_feedback_id_seq OWNED BY smartsell.user_feedback.id;
CREATE TABLE smartsell.user_push_notifications (
    id bigint NOT NULL,
    company_id bigint NOT NULL,
    topic character varying(200),
    title character varying(100),
    message character varying(512),
    action_target character varying(45),
    action_text character varying(45),
    extra_data character varying(300),
    image_url character varying(300),
    scheduled_date timestamp with time zone,
    scheduled_status integer DEFAULT 0,
    sent_status integer DEFAULT 0,
    is_leaderboard integer DEFAULT 0,
    sync integer DEFAULT 0,
    potd_sync integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone,
    user_group_id character varying(45),
    is_mobile integer,
    is_user_id integer,
    is_email integer
);
CREATE SEQUENCE smartsell.user_push_notifications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.user_push_notifications_id_seq OWNED BY smartsell.user_push_notifications.id;
CREATE TABLE smartsell.user_share_data (
    user_id bigint NOT NULL,
    posters_shared integer DEFAULT 0,
    videos_shared integer DEFAULT 0,
    pdfs_shared integer DEFAULT 0,
    presentations_shared integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.user_timer_challenge_question_history (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    quiz_id integer NOT NULL,
    question_id integer NOT NULL,
    option_selected integer NOT NULL,
    status character varying(255) NOT NULL,
    start_time timestamp with time zone NOT NULL,
    submission_time timestamp with time zone NOT NULL,
    time_taken timestamp with time zone,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);
CREATE SEQUENCE smartsell.user_timer_challenge_question_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.user_timer_challenge_question_history_id_seq OWNED BY smartsell.user_timer_challenge_question_history.id;
CREATE TABLE smartsell.users (
    user_id bigint NOT NULL,
    company_id bigint NOT NULL,
    mobile_number character varying(10),
    name character varying(100),
    username character varying(45),
    password character varying(500),
    email character varying(100),
    designation text,
    location text,
    language_id integer,
    security_key character varying(8),
    user_type_id bigint,
    activation_status smallint DEFAULT '0'::smallint,
    registered_status smallint DEFAULT '0'::smallint,
    signature character varying(300),
    fcm character varying(255),
    apn character varying(255),
    profile_img_url character varying(200),
    otp character varying(6),
    otp_expiry_time timestamp with time zone,
    android_user smallint DEFAULT '0'::smallint,
    ios_user smallint DEFAULT '0'::smallint,
    restore_id character varying(128),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone,
    encrypted_status integer DEFAULT 0,
    registered_date timestamp with time zone,
    name_encrypted character varying(1000),
    email_encrypted character varying(1000),
    test_user integer DEFAULT 0,
    meta1 character varying(255),
    meta2 character varying(255),
    meta3 character varying(255),
    meta4 character varying(255),
    meta5 character varying(255),
    meta6 bigint,
    meta7 bigint,
    meta8 bigint,
    meta9 date,
    meta10 date,
    meta11 character varying(255),
    meta12 character varying(255),
    meta13 character varying(255),
    meta14 character varying(255),
    meta15 character varying(255),
    meta16 character varying(255),
    meta17 character varying(255),
    meta18 character varying(255),
    meta19 character varying(255),
    meta20 character varying(255),
    la_code character varying(45),
    agent_code character varying(45),
    agent_staff_code character varying(45),
    first_name character varying(100),
    middle_name character varying(100),
    last_name character varying(100),
    gender character varying(45),
    city_name character varying(100),
    state character varying(100),
    date_of_joining timestamp with time zone,
    channel_name character varying(100),
    channel_code character varying(100),
    subchannel_name character varying(100),
    subchannel_code character varying(100),
    ulip_flag smallint,
    agent_category character varying(100),
    agency_type character varying(100),
    license_type character varying(100),
    agent_status character varying(100),
    user_details text,
    ingenium_channel_code character varying(45),
    login_attempts integer,
    login_block_start_time timestamp with time zone,
    login_block_end_time timestamp with time zone,
    country_code character varying(15) DEFAULT '+91'::character varying,
    user_unique_id character varying(255)
);
COMMENT ON COLUMN smartsell.users.restore_id IS 'fresh_chat_restore_id';
CREATE TABLE smartsell.users_details (
    user_id bigint NOT NULL,
    branch_code character varying(128),
    state character varying(128),
    city character varying(128),
    channel_name text,
    location_head text,
    area_manager text,
    regional_manager text,
    zonal_manager text,
    managing_partner text,
    business_head text,
    unique_id character varying(255),
    agent_type character varying(255)
);
CREATE TABLE smartsell.users_has_quiz (
    id_user_has_quiz integer NOT NULL,
    id_quiz bigint,
    user_id bigint,
    score bigint,
    duration double precision,
    completed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.users_log (
    id integer NOT NULL,
    agent_code character varying(45) NOT NULL,
    user_details text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.users_meta_properties (
    id integer NOT NULL,
    name character varying(255),
    type character varying(255),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone
);
CREATE TABLE smartsell.users_timer_challenges (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    quiz_id bigint NOT NULL,
    start_time timestamp with time zone NOT NULL,
    submission_time timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    time_seconds integer DEFAULT 0 NOT NULL
);
CREATE SEQUENCE smartsell.users_timer_challenges_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.users_timer_challenges_id_seq OWNED BY smartsell.users_timer_challenges.id;
CREATE TABLE smartsell.users_timer_challenges_questions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    quiz_id bigint NOT NULL,
    question_id integer NOT NULL,
    no_of_options_correct integer NOT NULL,
    option_selected integer NOT NULL,
    start_time timestamp with time zone,
    submission_time timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    time_seconds integer DEFAULT 0 NOT NULL
);
CREATE SEQUENCE smartsell.users_timer_challenges_questions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.users_timer_challenges_questions_id_seq OWNED BY smartsell.users_timer_challenges_questions.id;
CREATE SEQUENCE smartsell.users_user_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.users_user_id_seq OWNED BY smartsell.users.user_id;
CREATE TABLE smartsell.video_library (
    id bigint NOT NULL,
    company_id bigint NOT NULL,
    filename text,
    original_filename text,
    presigned_url text,
    readable_url text,
    is_active integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    video_mp4_url text,
    video_thumbnail_url text,
    mediaconvert_job_id text,
    video_m3u8_url text
);
CREATE SEQUENCE smartsell.video_library_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE smartsell.video_library_id_seq OWNED BY smartsell.video_library.id;
CREATE TABLE storage.buckets (
    id text NOT NULL,
    name text NOT NULL,
    owner uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
CREATE TABLE storage.migrations (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    hash character varying(40) NOT NULL,
    executed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE storage.objects (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    bucket_id text,
    name text,
    owner uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    last_accessed_at timestamp with time zone DEFAULT now(),
    metadata jsonb
);
ALTER TABLE ONLY auth.refresh_tokens ALTER COLUMN id SET DEFAULT nextval('auth.refresh_tokens_id_seq'::regclass);
ALTER TABLE ONLY launchpad.admin ALTER COLUMN id SET DEFAULT nextval('launchpad.admin_id_seq'::regclass);
ALTER TABLE ONLY launchpad.app_constants ALTER COLUMN id SET DEFAULT nextval('launchpad.app_constants_id_seq'::regclass);
ALTER TABLE ONLY launchpad.batch ALTER COLUMN batch_id SET DEFAULT nextval('launchpad.batch_batch_id_seq'::regclass);
ALTER TABLE ONLY launchpad.company ALTER COLUMN id_company SET DEFAULT nextval('launchpad.company_id_company_seq'::regclass);
ALTER TABLE ONLY launchpad.company_certificate_image_elements ALTER COLUMN id SET DEFAULT nextval('launchpad.company_certificate_image_elements_id_seq'::regclass);
ALTER TABLE ONLY launchpad.company_certificate_templates ALTER COLUMN id SET DEFAULT nextval('launchpad.company_certificate_templates_id_seq'::regclass);
ALTER TABLE ONLY launchpad.company_certificate_text_elements ALTER COLUMN id SET DEFAULT nextval('launchpad.company_certificate_text_elements_id_seq'::regclass);
ALTER TABLE ONLY launchpad.company_wise_manager_levels ALTER COLUMN id SET DEFAULT nextval('launchpad.company_wise_manager_levels_id_seq'::regclass);
ALTER TABLE ONLY launchpad.country ALTER COLUMN id SET DEFAULT nextval('launchpad.country_id_seq'::regclass);
ALTER TABLE ONLY launchpad.feedback_questions ALTER COLUMN question_id SET DEFAULT nextval('launchpad.feedback_questions_question_id_seq'::regclass);
ALTER TABLE ONLY launchpad.feedback_questions_language ALTER COLUMN question_id SET DEFAULT nextval('launchpad.feedback_questions_language_question_id_seq'::regclass);
ALTER TABLE ONLY launchpad.logs ALTER COLUMN id SET DEFAULT nextval('launchpad.logs_id_seq'::regclass);
ALTER TABLE ONLY launchpad.manager_session ALTER COLUMN id SET DEFAULT nextval('launchpad.manager_session_id_seq'::regclass);
ALTER TABLE ONLY launchpad.mapping_timer_challenges_to_company ALTER COLUMN id SET DEFAULT nextval('launchpad.mapping_timer_challenges_to_company_id_seq'::regclass);
ALTER TABLE ONLY launchpad.meta_content_unit ALTER COLUMN id SET DEFAULT nextval('launchpad.meta_content_unit_id_seq'::regclass);
ALTER TABLE ONLY launchpad.meta_featured_items ALTER COLUMN id SET DEFAULT nextval('launchpad.meta_featured_items_id_seq'::regclass);
ALTER TABLE ONLY launchpad.meta_gifs ALTER COLUMN id SET DEFAULT nextval('launchpad.meta_gifs_id_seq'::regclass);
ALTER TABLE ONLY launchpad.meta_glossary ALTER COLUMN id SET DEFAULT nextval('launchpad.meta_glossary_id_seq'::regclass);
ALTER TABLE ONLY launchpad.meta_live_streaming ALTER COLUMN id SET DEFAULT nextval('launchpad.meta_live_streaming_id_seq'::regclass);
ALTER TABLE ONLY launchpad.meta_pdfs ALTER COLUMN id SET DEFAULT nextval('launchpad.meta_pdfs_id_seq'::regclass);
ALTER TABLE ONLY launchpad.meta_posters ALTER COLUMN id SET DEFAULT nextval('launchpad.meta_posters_id_seq'::regclass);
ALTER TABLE ONLY launchpad.meta_quiz_unit ALTER COLUMN id SET DEFAULT nextval('launchpad.meta_quiz_unit_id_seq'::regclass);
ALTER TABLE ONLY launchpad.meta_skill ALTER COLUMN id SET DEFAULT nextval('launchpad.meta_skill_id_seq'::regclass);
ALTER TABLE ONLY launchpad.meta_skill_type ALTER COLUMN id SET DEFAULT nextval('launchpad.meta_skill_type_id_seq'::regclass);
ALTER TABLE ONLY launchpad.meta_speciality_page ALTER COLUMN id SET DEFAULT nextval('launchpad.meta_speciality_page_id_seq'::regclass);
ALTER TABLE ONLY launchpad.meta_sub_topic ALTER COLUMN id SET DEFAULT nextval('launchpad.meta_sub_topic_id_seq'::regclass);
ALTER TABLE ONLY launchpad.meta_survey_questions ALTER COLUMN question_id SET DEFAULT nextval('launchpad.meta_survey_questions_question_id_seq'::regclass);
ALTER TABLE ONLY launchpad.meta_survey_questions_language ALTER COLUMN question_id SET DEFAULT nextval('launchpad.meta_survey_questions_language_question_id_seq'::regclass);
ALTER TABLE ONLY launchpad.meta_timer_challenges ALTER COLUMN id SET DEFAULT nextval('launchpad.meta_timer_challenges_id_seq'::regclass);
ALTER TABLE ONLY launchpad.meta_timer_challenges_language ALTER COLUMN id SET DEFAULT nextval('launchpad.meta_timer_challenges_language_id_seq'::regclass);
ALTER TABLE ONLY launchpad.meta_timer_challenges_questions ALTER COLUMN id_meta_timer_challenges_questions SET DEFAULT nextval('launchpad.meta_timer_challenges_questio_id_meta_timer_challenges_ques_seq'::regclass);
ALTER TABLE ONLY launchpad.meta_topic ALTER COLUMN id SET DEFAULT nextval('launchpad.meta_topic_id_seq'::regclass);
ALTER TABLE ONLY launchpad.meta_video ALTER COLUMN id SET DEFAULT nextval('launchpad.meta_video_id_seq'::regclass);
ALTER TABLE ONLY launchpad.meta_videos ALTER COLUMN id SET DEFAULT nextval('launchpad.meta_videos_id_seq'::regclass);
ALTER TABLE ONLY launchpad.migrations ALTER COLUMN id SET DEFAULT nextval('launchpad.migrations_id_seq'::regclass);
ALTER TABLE ONLY launchpad.mile_stone ALTER COLUMN id SET DEFAULT nextval('launchpad.mile_stone_id_seq'::regclass);
ALTER TABLE ONLY launchpad.module ALTER COLUMN id_module SET DEFAULT nextval('launchpad.module_id_module_seq'::regclass);
ALTER TABLE ONLY launchpad.onboard_quiz ALTER COLUMN id SET DEFAULT nextval('launchpad.onboard_quiz_id_seq'::regclass);
ALTER TABLE ONLY launchpad.role ALTER COLUMN id_role SET DEFAULT nextval('launchpad.role_id_role_seq'::regclass);
ALTER TABLE ONLY launchpad.role_has_module ALTER COLUMN id_role_has_module SET DEFAULT nextval('launchpad.role_has_module_id_role_has_module_seq'::regclass);
ALTER TABLE ONLY launchpad.testing ALTER COLUMN id SET DEFAULT nextval('launchpad.testing_id_seq'::regclass);
ALTER TABLE ONLY launchpad.user_push_notifications ALTER COLUMN id SET DEFAULT nextval('launchpad.user_push_notifications_id_seq'::regclass);
ALTER TABLE ONLY launchpad.user_quiz_history ALTER COLUMN id SET DEFAULT nextval('launchpad.user_quiz_history_id_seq'::regclass);
ALTER TABLE ONLY launchpad.users ALTER COLUMN user_id SET DEFAULT nextval('launchpad.users_user_id_seq'::regclass);
ALTER TABLE ONLY launchpad.users_notifications ALTER COLUMN id SET DEFAULT nextval('launchpad.users_notifications_id_seq'::regclass);
ALTER TABLE ONLY launchpad.users_rules ALTER COLUMN id SET DEFAULT nextval('launchpad.users_rules_id_seq'::regclass);
ALTER TABLE ONLY launchpad.users_timer_challenges ALTER COLUMN id SET DEFAULT nextval('launchpad.users_timer_challenges_id_seq'::regclass);
ALTER TABLE ONLY launchpad.users_timer_challenges_questions ALTER COLUMN id SET DEFAULT nextval('launchpad.users_timer_challenges_questions_id_seq'::regclass);
ALTER TABLE ONLY launchpad.vc_category ALTER COLUMN id_category SET DEFAULT nextval('launchpad.vc_category_id_category_seq'::regclass);
ALTER TABLE ONLY launchpad.vc_challenges ALTER COLUMN id_challenge SET DEFAULT nextval('launchpad.vc_challenges_id_challenge_seq'::regclass);
ALTER TABLE ONLY launchpad.vc_evaluation_params ALTER COLUMN id SET DEFAULT nextval('launchpad.vc_evaluation_params_id_seq'::regclass);
ALTER TABLE ONLY launchpad.vc_groups ALTER COLUMN id SET DEFAULT nextval('launchpad.vc_groups_id_seq'::regclass);
ALTER TABLE ONLY launchpad.vc_review_suggestions ALTER COLUMN id SET DEFAULT nextval('launchpad.vc_review_suggestions_id_seq'::regclass);
ALTER TABLE ONLY launchpad.vc_reviewers ALTER COLUMN id_reviewer SET DEFAULT nextval('launchpad.vc_reviewers_id_reviewer_seq'::regclass);
ALTER TABLE ONLY smartsell.admin ALTER COLUMN id SET DEFAULT nextval('smartsell.admin_id_seq'::regclass);
ALTER TABLE ONLY smartsell.app_constants ALTER COLUMN id SET DEFAULT nextval('smartsell.app_constants_id_seq'::regclass);
ALTER TABLE ONLY smartsell.company ALTER COLUMN id_company SET DEFAULT nextval('smartsell.company_id_company_seq'::regclass);
ALTER TABLE ONLY smartsell.company_groups ALTER COLUMN id SET DEFAULT nextval('smartsell.company_groups_id_seq'::regclass);
ALTER TABLE ONLY smartsell.country ALTER COLUMN id SET DEFAULT nextval('smartsell.country_id_seq'::regclass);
ALTER TABLE ONLY smartsell.group_cards ALTER COLUMN id SET DEFAULT nextval('smartsell.group_cards_id_seq'::regclass);
ALTER TABLE ONLY smartsell.lookup_mapping_product_section ALTER COLUMN id SET DEFAULT nextval('smartsell.lookup_mapping_product_section_id_seq'::regclass);
ALTER TABLE ONLY smartsell.lookup_page_master_image_elements ALTER COLUMN id SET DEFAULT nextval('smartsell.lookup_page_master_image_elements_id_seq'::regclass);
ALTER TABLE ONLY smartsell.lookup_page_master_text_elements ALTER COLUMN id SET DEFAULT nextval('smartsell.lookup_page_master_text_elements_id_seq'::regclass);
ALTER TABLE ONLY smartsell.mapping_new_items ALTER COLUMN id SET DEFAULT nextval('smartsell.mapping_new_items_id_seq'::regclass);
ALTER TABLE ONLY smartsell.mapping_specific_user_directory_content ALTER COLUMN id SET DEFAULT nextval('smartsell.mapping_specific_user_directory_content_id_seq'::regclass);
ALTER TABLE ONLY smartsell.mapping_timer_challenges_to_user_group ALTER COLUMN id SET DEFAULT nextval('smartsell.mapping_timer_challenges_to_user_group_id_seq'::regclass);
ALTER TABLE ONLY smartsell.mapping_timer_challenges_to_user_type ALTER COLUMN id SET DEFAULT nextval('smartsell.mapping_timer_challenges_to_user_type_id_seq'::regclass);
ALTER TABLE ONLY smartsell.mapping_user_directory_content ALTER COLUMN id SET DEFAULT nextval('smartsell.mapping_user_directory_content_id_seq'::regclass);
ALTER TABLE ONLY smartsell.mapping_user_home_banner ALTER COLUMN item_id SET DEFAULT nextval('smartsell.mapping_user_home_banner_item_id_seq'::regclass);
ALTER TABLE ONLY smartsell.mapping_user_home_content ALTER COLUMN id SET DEFAULT nextval('smartsell.mapping_user_home_content_id_seq'::regclass);
ALTER TABLE ONLY smartsell.mapping_user_home_directory_content ALTER COLUMN id SET DEFAULT nextval('smartsell.mapping_user_home_directory_content_id_seq'::regclass);
ALTER TABLE ONLY smartsell.mapping_user_home_page ALTER COLUMN id SET DEFAULT nextval('smartsell.mapping_user_home_page_id_seq'::regclass);
ALTER TABLE ONLY smartsell.mapping_user_home_top_slider ALTER COLUMN id SET DEFAULT nextval('smartsell.mapping_user_home_top_slider_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_cards ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_cards_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_cards_image_elements ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_cards_image_elements_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_cards_text_elements ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_cards_text_elements_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_content_types ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_content_types_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_daily_posters ALTER COLUMN id_meta_daily_poster SET DEFAULT nextval('smartsell.meta_daily_posters_id_meta_daily_poster_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_directories ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_directories_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_directories_versions ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_directories_versions_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_directory_display_types ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_directory_display_types_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_home_page_item_types ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_home_page_item_types_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_languages ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_languages_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_pdfs ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_pdfs_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_pdfs_tags ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_pdfs_tags_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_pdfs_versions ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_pdfs_versions_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_posters ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_posters_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_posters_image_elements ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_posters_image_elements_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_posters_image_elements_versions ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_posters_image_elements_versions_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_posters_tags ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_posters_tags_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_posters_text_elements ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_posters_text_elements_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_posters_text_elements_versions ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_posters_text_elements_versions_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_posters_versions ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_posters_versions_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_recognitions ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_recognitions_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_tags ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_tags_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_timer_challenges ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_timer_challenges_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_timer_challenges_language ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_timer_challenges_language_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_user_types ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_user_types_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_videos ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_videos_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_videos_tags ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_videos_tags_id_seq'::regclass);
ALTER TABLE ONLY smartsell.meta_videos_versions ALTER COLUMN id SET DEFAULT nextval('smartsell.meta_videos_versions_id_seq'::regclass);
ALTER TABLE ONLY smartsell.migrations ALTER COLUMN id SET DEFAULT nextval('smartsell.migrations_id_seq'::regclass);
ALTER TABLE ONLY smartsell.module ALTER COLUMN id_module SET DEFAULT nextval('smartsell.module_id_module_seq'::regclass);
ALTER TABLE ONLY smartsell.quiz_challenge ALTER COLUMN id_quiz SET DEFAULT nextval('smartsell.quiz_challenge_id_quiz_seq'::regclass);
ALTER TABLE ONLY smartsell.quiz_question ALTER COLUMN id_question SET DEFAULT nextval('smartsell.quiz_question_id_question_seq'::regclass);
ALTER TABLE ONLY smartsell.role ALTER COLUMN id_role SET DEFAULT nextval('smartsell.role_id_role_seq'::regclass);
ALTER TABLE ONLY smartsell.role_has_module ALTER COLUMN id_role_has_module SET DEFAULT nextval('smartsell.role_has_module_id_role_has_module_seq'::regclass);
ALTER TABLE ONLY smartsell.testing ALTER COLUMN id SET DEFAULT nextval('smartsell.testing_id_seq'::regclass);
ALTER TABLE ONLY smartsell.user_announcements ALTER COLUMN id SET DEFAULT nextval('smartsell.user_announcements_id_seq'::regclass);
ALTER TABLE ONLY smartsell.user_excel ALTER COLUMN user_id SET DEFAULT nextval('smartsell.user_excel_user_id_seq'::regclass);
ALTER TABLE ONLY smartsell.user_feedback ALTER COLUMN id SET DEFAULT nextval('smartsell.user_feedback_id_seq'::regclass);
ALTER TABLE ONLY smartsell.user_push_notifications ALTER COLUMN id SET DEFAULT nextval('smartsell.user_push_notifications_id_seq'::regclass);
ALTER TABLE ONLY smartsell.user_timer_challenge_question_history ALTER COLUMN id SET DEFAULT nextval('smartsell.user_timer_challenge_question_history_id_seq'::regclass);
ALTER TABLE ONLY smartsell.users ALTER COLUMN user_id SET DEFAULT nextval('smartsell.users_user_id_seq'::regclass);
ALTER TABLE ONLY smartsell.users_timer_challenges ALTER COLUMN id SET DEFAULT nextval('smartsell.users_timer_challenges_id_seq'::regclass);
ALTER TABLE ONLY smartsell.users_timer_challenges_questions ALTER COLUMN id SET DEFAULT nextval('smartsell.users_timer_challenges_questions_id_seq'::regclass);
ALTER TABLE ONLY smartsell.video_library ALTER COLUMN id SET DEFAULT nextval('smartsell.video_library_id_seq'::regclass);
ALTER TABLE ONLY auth.audit_log_entries
    ADD CONSTRAINT audit_log_entries_pkey PRIMARY KEY (id);
ALTER TABLE ONLY auth.instances
    ADD CONSTRAINT instances_pkey PRIMARY KEY (id);
ALTER TABLE ONLY auth.refresh_tokens
    ADD CONSTRAINT refresh_tokens_pkey PRIMARY KEY (id);
ALTER TABLE ONLY auth.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);
ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_email_key UNIQUE (email);
ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.admin
    ADD CONSTRAINT idx_24472_primary PRIMARY KEY (username);
ALTER TABLE ONLY launchpad.app_ios_version
    ADD CONSTRAINT idx_24507_primary PRIMARY KEY (app_version);
ALTER TABLE ONLY launchpad.assets_data
    ADD CONSTRAINT idx_24513_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.auth_access_token
    ADD CONSTRAINT idx_24520_primary PRIMARY KEY (access_token);
ALTER TABLE ONLY launchpad.auth_refresh_token
    ADD CONSTRAINT idx_24524_primary PRIMARY KEY (refresh_token);
ALTER TABLE ONLY launchpad.batch
    ADD CONSTRAINT idx_24529_primary PRIMARY KEY (batch_id);
ALTER TABLE ONLY launchpad.batch_has_db
    ADD CONSTRAINT idx_24553_primary PRIMARY KEY (batch_id);
ALTER TABLE ONLY launchpad.batch_has_onboard_quiz
    ADD CONSTRAINT idx_24564_primary PRIMARY KEY (batch_id);
ALTER TABLE ONLY launchpad.batch_has_skills
    ADD CONSTRAINT idx_24568_primary PRIMARY KEY (batch_id, skill_id);
ALTER TABLE ONLY launchpad.company
    ADD CONSTRAINT idx_24576_primary PRIMARY KEY (id_company);
ALTER TABLE ONLY launchpad.company_certificate_image_elements
    ADD CONSTRAINT idx_24584_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.company_certificate_templates
    ADD CONSTRAINT idx_24593_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.company_certificate_text_elements
    ADD CONSTRAINT idx_24600_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.company_user_property
    ADD CONSTRAINT idx_24612_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.company_wise_manager_levels
    ADD CONSTRAINT idx_24620_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.const_active_content_image_tags
    ADD CONSTRAINT idx_24626_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.const_active_content_images
    ADD CONSTRAINT idx_24631_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.country
    ADD CONSTRAINT idx_24637_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.dashboard_user_courses_completion_rate
    ADD CONSTRAINT idx_24681_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.dashboard_users_course_completion_avg
    ADD CONSTRAINT idx_24685_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.dashboard_users_subtopic_completion_avg
    ADD CONSTRAINT idx_24690_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.dashboard_users_subtopic_completion_rate
    ADD CONSTRAINT idx_24696_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.feedback_form
    ADD CONSTRAINT idx_24727_primary PRIMARY KEY (id_feedback_form);
ALTER TABLE ONLY launchpad.feedback_questions
    ADD CONSTRAINT idx_24745_primary PRIMARY KEY (question_id);
ALTER TABLE ONLY launchpad.filters
    ADD CONSTRAINT idx_24762_primary PRIMARY KEY (filter_id);
ALTER TABLE ONLY launchpad.in_app_notification
    ADD CONSTRAINT idx_24768_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.logged_mobile_number
    ADD CONSTRAINT idx_24776_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.logs
    ADD CONSTRAINT idx_24781_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.manager_levels
    ADD CONSTRAINT idx_24785_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.manager_session
    ADD CONSTRAINT idx_24790_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.manager_to_manager_mapping
    ADD CONSTRAINT idx_24797_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.manager_to_user_mapping
    ADD CONSTRAINT idx_24802_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.managers
    ADD CONSTRAINT idx_24806_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.mapping_batch_has_live_streaming
    ADD CONSTRAINT idx_24815_primary PRIMARY KEY (batch_id, live_streaming_id);
ALTER TABLE ONLY launchpad.mapping_question_to_skill
    ADD CONSTRAINT idx_24827_primary PRIMARY KEY (question_id, quiz_id, batch_id);
ALTER TABLE ONLY launchpad.meta_active_content
    ADD CONSTRAINT idx_24861_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.meta_active_content_styles
    ADD CONSTRAINT idx_24873_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.meta_content_unit
    ADD CONSTRAINT idx_24885_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.meta_course
    ADD CONSTRAINT idx_24896_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.meta_course_type
    ADD CONSTRAINT idx_24914_primary PRIMARY KEY (id_course_type);
ALTER TABLE ONLY launchpad.meta_evaluation_params
    ADD CONSTRAINT idx_24927_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.meta_faq
    ADD CONSTRAINT idx_24931_primary PRIMARY KEY (question_no);
ALTER TABLE ONLY launchpad.meta_faq_language
    ADD CONSTRAINT idx_24937_primary PRIMARY KEY (question_no);
ALTER TABLE ONLY launchpad.meta_featured_items
    ADD CONSTRAINT idx_24944_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.meta_gifs
    ADD CONSTRAINT idx_24951_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.meta_glossary
    ADD CONSTRAINT idx_24969_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.meta_language
    ADD CONSTRAINT idx_24976_primary PRIMARY KEY (id_language);
ALTER TABLE ONLY launchpad.meta_live_streaming
    ADD CONSTRAINT idx_24985_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.meta_pdfs
    ADD CONSTRAINT idx_24993_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.meta_posters
    ADD CONSTRAINT idx_25010_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.meta_quiz_questions
    ADD CONSTRAINT idx_25028_primary PRIMARY KEY (id_meta_quiz_questions);
ALTER TABLE ONLY launchpad.meta_quiz_unit
    ADD CONSTRAINT idx_25038_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.meta_quiz_unit_temp
    ADD CONSTRAINT idx_25058_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.meta_skill
    ADD CONSTRAINT idx_25067_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.meta_skill_type
    ADD CONSTRAINT idx_25080_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.meta_speciality_page
    ADD CONSTRAINT idx_25087_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.meta_spotlights
    ADD CONSTRAINT idx_25101_primary PRIMARY KEY (id_meta_spotlights);
ALTER TABLE ONLY launchpad.meta_sub_topic
    ADD CONSTRAINT idx_25107_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.meta_survey
    ADD CONSTRAINT idx_25128_primary PRIMARY KEY (id_survey);
ALTER TABLE ONLY launchpad.meta_tags
    ADD CONSTRAINT idx_25159_primary PRIMARY KEY (id_meta_tags);
ALTER TABLE ONLY launchpad.meta_template_type
    ADD CONSTRAINT idx_25165_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.meta_timer_challenges
    ADD CONSTRAINT idx_25193_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.meta_timer_challenges_questions
    ADD CONSTRAINT idx_25222_primary PRIMARY KEY (id_meta_timer_challenges_questions);
ALTER TABLE ONLY launchpad.meta_topic
    ADD CONSTRAINT idx_25234_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.meta_video
    ADD CONSTRAINT idx_25250_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.meta_videos
    ADD CONSTRAINT idx_25265_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.meta_web_link
    ADD CONSTRAINT idx_25279_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.migrations
    ADD CONSTRAINT idx_25292_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.mile_stone
    ADD CONSTRAINT idx_25297_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.mile_stone_type
    ADD CONSTRAINT idx_25312_primary PRIMARY KEY (id_type);
ALTER TABLE ONLY launchpad.module
    ADD CONSTRAINT idx_25323_primary PRIMARY KEY (id_module);
ALTER TABLE ONLY launchpad.onboard_quiz
    ADD CONSTRAINT idx_25333_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.quiz_type
    ADD CONSTRAINT idx_25357_primary PRIMARY KEY (id_quiz_type);
ALTER TABLE ONLY launchpad.role
    ADD CONSTRAINT idx_25373_primary PRIMARY KEY (id_role);
ALTER TABLE ONLY launchpad.role_has_module
    ADD CONSTRAINT idx_25382_primary PRIMARY KEY (id_role_has_module);
ALTER TABLE ONLY launchpad.server_health
    ADD CONSTRAINT idx_25388_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.testing
    ADD CONSTRAINT idx_25394_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.tiles_content_mapping
    ADD CONSTRAINT idx_25398_primary PRIMARY KEY (tile_id);
ALTER TABLE ONLY launchpad.user_dublicate_uids
    ADD CONSTRAINT idx_25417_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.user_lms_logs
    ADD CONSTRAINT idx_25445_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.user_logs
    ADD CONSTRAINT idx_25448_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.user_parameters
    ADD CONSTRAINT idx_25451_primary PRIMARY KEY (user_id);
ALTER TABLE ONLY launchpad.user_push_notifications
    ADD CONSTRAINT idx_25457_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.user_quiz_history
    ADD CONSTRAINT idx_25471_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.user_tms_logs
    ADD CONSTRAINT idx_25475_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.users
    ADD CONSTRAINT idx_25479_primary PRIMARY KEY (user_id);
ALTER TABLE ONLY launchpad.users_details
    ADD CONSTRAINT idx_25511_primary PRIMARY KEY (user_id);
ALTER TABLE ONLY launchpad.users_meta_properties
    ADD CONSTRAINT idx_25524_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.users_notifications
    ADD CONSTRAINT idx_25535_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.users_rules
    ADD CONSTRAINT idx_25549_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.users_timer_challenges
    ADD CONSTRAINT idx_25560_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.users_timer_challenges_questions
    ADD CONSTRAINT idx_25568_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.users_tms_data
    ADD CONSTRAINT idx_25576_primary PRIMARY KEY (unique_id, program_id);
ALTER TABLE ONLY launchpad.vc_category
    ADD CONSTRAINT idx_25592_primary PRIMARY KEY (id_category);
ALTER TABLE ONLY launchpad.vc_challenges
    ADD CONSTRAINT idx_25605_primary PRIMARY KEY (id_challenge);
ALTER TABLE ONLY launchpad.vc_evaluation_params
    ADD CONSTRAINT idx_25635_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.vc_groups
    ADD CONSTRAINT idx_25641_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.vc_review_suggestions
    ADD CONSTRAINT idx_25667_primary PRIMARY KEY (id);
ALTER TABLE ONLY launchpad.vc_reviewers
    ADD CONSTRAINT idx_25680_primary PRIMARY KEY (id_reviewer);
ALTER TABLE ONLY launchpad.vc_users_groups
    ADD CONSTRAINT idx_25701_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.admin
    ADD CONSTRAINT idx_17080_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.app_android
    ADD CONSTRAINT idx_17096_primary PRIMARY KEY (app_version);
ALTER TABLE ONLY smartsell.app_android_version
    ADD CONSTRAINT idx_17102_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.app_constants
    ADD CONSTRAINT idx_17112_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.app_ios
    ADD CONSTRAINT idx_17121_primary PRIMARY KEY (app_version);
ALTER TABLE ONLY smartsell.app_ios_version
    ADD CONSTRAINT idx_17127_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.assets
    ADD CONSTRAINT idx_17134_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.auth_access_token
    ADD CONSTRAINT idx_17140_primary PRIMARY KEY (access_token);
ALTER TABLE ONLY smartsell.auth_refresh_token
    ADD CONSTRAINT idx_17144_primary PRIMARY KEY (refresh_token);
ALTER TABLE ONLY smartsell.company
    ADD CONSTRAINT idx_17149_primary PRIMARY KEY (id_company);
ALTER TABLE ONLY smartsell.company_branding
    ADD CONSTRAINT idx_17160_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.company_groups
    ADD CONSTRAINT idx_17175_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.company_user_group_configs
    ADD CONSTRAINT idx_17185_primary PRIMARY KEY (company_id, user_group_id);
ALTER TABLE ONLY smartsell.company_user_property
    ADD CONSTRAINT idx_17190_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.country
    ADD CONSTRAINT idx_17200_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.default_mapping_specific_user_directory_content
    ADD CONSTRAINT idx_17216_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.group_cards
    ADD CONSTRAINT idx_17221_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.group_livestreams
    ADD CONSTRAINT idx_17226_primary PRIMARY KEY (group_id, livestream_id);
ALTER TABLE ONLY smartsell.group_presentations
    ADD CONSTRAINT idx_17230_primary PRIMARY KEY (group_id, presentation_id);
ALTER TABLE ONLY smartsell.group_products
    ADD CONSTRAINT idx_17234_primary PRIMARY KEY (group_id, product_id);
ALTER TABLE ONLY smartsell.group_quick_links
    ADD CONSTRAINT idx_17238_primary PRIMARY KEY (group_id, quick_link_id);
ALTER TABLE ONLY smartsell.group_users
    ADD CONSTRAINT idx_17243_primary PRIMARY KEY (group_id, user_id);
ALTER TABLE ONLY smartsell.lookup_mapping_product_section
    ADD CONSTRAINT idx_17254_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.lookup_page_master
    ADD CONSTRAINT idx_17265_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.lookup_page_master_image_elements
    ADD CONSTRAINT idx_17274_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.lookup_page_master_text_elements
    ADD CONSTRAINT idx_17281_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.lookup_page_types
    ADD CONSTRAINT idx_17286_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.lookup_presentation_category
    ADD CONSTRAINT idx_17289_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.lookup_presentation_dataset
    ADD CONSTRAINT idx_17294_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.lookup_presentation_master
    ADD CONSTRAINT idx_17304_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.lookup_product
    ADD CONSTRAINT idx_17315_primary PRIMARY KEY (id, category_id);
ALTER TABLE ONLY smartsell.lookup_product_benefit
    ADD CONSTRAINT idx_17321_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.lookup_product_benefit_category
    ADD CONSTRAINT idx_17327_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.lookup_product_bulletlist_collateral
    ADD CONSTRAINT idx_17333_primary PRIMARY KEY (section_id);
ALTER TABLE ONLY smartsell.lookup_product_bulletlist_multiple
    ADD CONSTRAINT idx_17347_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.lookup_product_category
    ADD CONSTRAINT idx_17353_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.lookup_product_faq
    ADD CONSTRAINT idx_17359_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.lookup_product_section
    ADD CONSTRAINT idx_17365_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.lookup_product_sectiontype
    ADD CONSTRAINT idx_17369_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.lookup_quick_links
    ADD CONSTRAINT idx_17373_primary PRIMARY KEY (quick_link_id);
ALTER TABLE ONLY smartsell.lookup_section_master
    ADD CONSTRAINT idx_17378_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.mapping_new_items
    ADD CONSTRAINT idx_17389_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.mapping_specific_user_directory_content
    ADD CONSTRAINT idx_17395_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.mapping_timer_challenges_to_user_group
    ADD CONSTRAINT idx_17401_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.mapping_timer_challenges_to_user_type
    ADD CONSTRAINT idx_17407_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.mapping_user_directory_content
    ADD CONSTRAINT idx_17413_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.mapping_user_home_banner
    ADD CONSTRAINT idx_17419_primary PRIMARY KEY (item_id);
ALTER TABLE ONLY smartsell.mapping_user_home_content
    ADD CONSTRAINT idx_17427_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.mapping_user_home_directory_content
    ADD CONSTRAINT idx_17433_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.mapping_user_home_page
    ADD CONSTRAINT idx_17440_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.mapping_user_home_top_slider
    ADD CONSTRAINT idx_17446_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.mapping_user_types
    ADD CONSTRAINT idx_17453_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_cards
    ADD CONSTRAINT idx_17457_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_cards_image_elements
    ADD CONSTRAINT idx_17467_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_cards_text_elements
    ADD CONSTRAINT idx_17479_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_channel
    ADD CONSTRAINT idx_17486_primary PRIMARY KEY (channel_id);
ALTER TABLE ONLY smartsell.meta_channels
    ADD CONSTRAINT idx_17490_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_configs
    ADD CONSTRAINT idx_17496_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_content_types
    ADD CONSTRAINT idx_17503_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_daily_posters
    ADD CONSTRAINT idx_17509_primary PRIMARY KEY (id_meta_daily_poster);
ALTER TABLE ONLY smartsell.meta_directories
    ADD CONSTRAINT idx_17516_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_directories_versions
    ADD CONSTRAINT idx_17532_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_directory_display_types
    ADD CONSTRAINT idx_17545_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_fs_achievements
    ADD CONSTRAINT idx_17550_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_home_page_item_types
    ADD CONSTRAINT idx_17555_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_languages
    ADD CONSTRAINT idx_17561_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_livestream
    ADD CONSTRAINT idx_17567_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_mm_achievements
    ADD CONSTRAINT idx_17573_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_page_master
    ADD CONSTRAINT idx_17577_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_page_types
    ADD CONSTRAINT idx_17584_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_pdfs
    ADD CONSTRAINT idx_17589_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_pdfs_tags
    ADD CONSTRAINT idx_17600_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_pdfs_versions
    ADD CONSTRAINT idx_17606_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_posters
    ADD CONSTRAINT idx_17618_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_posters_image_elements
    ADD CONSTRAINT idx_17628_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_posters_image_elements_versions
    ADD CONSTRAINT idx_17634_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_posters_tags
    ADD CONSTRAINT idx_17641_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_posters_text_elements
    ADD CONSTRAINT idx_17647_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_posters_text_elements_versions
    ADD CONSTRAINT idx_17653_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_posters_versions
    ADD CONSTRAINT idx_17660_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_presentation_category_master
    ADD CONSTRAINT idx_17670_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_presentation_dataset
    ADD CONSTRAINT idx_17674_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_presentation_master
    ADD CONSTRAINT idx_17680_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_push_targets
    ADD CONSTRAINT idx_17686_primary PRIMARY KEY (target_id);
ALTER TABLE ONLY smartsell.meta_recognitions
    ADD CONSTRAINT idx_17692_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_section_master
    ADD CONSTRAINT idx_17699_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_sub_channels
    ADD CONSTRAINT idx_17705_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_tags
    ADD CONSTRAINT idx_17712_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_target_group_master
    ADD CONSTRAINT idx_17718_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_timer_challenges
    ADD CONSTRAINT idx_17725_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_timer_challenges_questions
    ADD CONSTRAINT idx_17753_primary PRIMARY KEY (id_meta_timer_challenges_questions);
ALTER TABLE ONLY smartsell.meta_user_types
    ADD CONSTRAINT idx_17764_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_videos
    ADD CONSTRAINT idx_17770_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_videos_tags
    ADD CONSTRAINT idx_17781_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.meta_videos_versions
    ADD CONSTRAINT idx_17787_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.migrations
    ADD CONSTRAINT idx_17798_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.module
    ADD CONSTRAINT idx_17803_primary PRIMARY KEY (id_module);
ALTER TABLE ONLY smartsell.old_mapping_presentation_category_to_target
    ADD CONSTRAINT idx_17818_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.old_users_groups
    ADD CONSTRAINT idx_17828_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.quiz_challenge
    ADD CONSTRAINT idx_17841_primary PRIMARY KEY (id_quiz);
ALTER TABLE ONLY smartsell.quiz_question
    ADD CONSTRAINT idx_17850_primary PRIMARY KEY (id_question);
ALTER TABLE ONLY smartsell.quiz_type
    ADD CONSTRAINT idx_17859_primary PRIMARY KEY (id_quiz_type);
ALTER TABLE ONLY smartsell.role
    ADD CONSTRAINT idx_17864_primary PRIMARY KEY (id_role);
ALTER TABLE ONLY smartsell.role_has_module
    ADD CONSTRAINT idx_17873_primary PRIMARY KEY (id_role_has_module);
ALTER TABLE ONLY smartsell.server_health
    ADD CONSTRAINT idx_17879_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.testing
    ADD CONSTRAINT idx_17885_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.user_achievements
    ADD CONSTRAINT idx_17889_primary PRIMARY KEY (user_id, achievement_level);
ALTER TABLE ONLY smartsell.user_announcements
    ADD CONSTRAINT idx_17894_primary PRIMARY KEY (id, user_type_id);
ALTER TABLE ONLY smartsell.user_excel
    ADD CONSTRAINT idx_17902_primary PRIMARY KEY (user_id);
ALTER TABLE ONLY smartsell.user_favorites
    ADD CONSTRAINT idx_17911_primary PRIMARY KEY (user_id, content_id, content_type_id);
ALTER TABLE ONLY smartsell.user_feedback
    ADD CONSTRAINT idx_17916_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.user_push_notifications
    ADD CONSTRAINT idx_17925_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.user_share_data
    ADD CONSTRAINT idx_17937_primary PRIMARY KEY (user_id);
ALTER TABLE ONLY smartsell.user_timer_challenge_question_history
    ADD CONSTRAINT idx_17946_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.users
    ADD CONSTRAINT idx_17951_primary PRIMARY KEY (user_id);
ALTER TABLE ONLY smartsell.users_has_quiz
    ADD CONSTRAINT idx_17970_primary PRIMARY KEY (id_user_has_quiz);
ALTER TABLE ONLY smartsell.users_log
    ADD CONSTRAINT idx_17974_primary PRIMARY KEY (id, agent_code);
ALTER TABLE ONLY smartsell.users_meta_properties
    ADD CONSTRAINT idx_17980_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.users_timer_challenges
    ADD CONSTRAINT idx_17987_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.users_timer_challenges_questions
    ADD CONSTRAINT idx_17994_primary PRIMARY KEY (id);
ALTER TABLE ONLY smartsell.video_library
    ADD CONSTRAINT idx_18001_primary PRIMARY KEY (id);
ALTER TABLE ONLY storage.buckets
    ADD CONSTRAINT buckets_pkey PRIMARY KEY (id);
ALTER TABLE ONLY storage.migrations
    ADD CONSTRAINT migrations_name_key UNIQUE (name);
ALTER TABLE ONLY storage.migrations
    ADD CONSTRAINT migrations_pkey PRIMARY KEY (id);
ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT objects_pkey PRIMARY KEY (id);
CREATE INDEX audit_logs_instance_id_idx ON auth.audit_log_entries USING btree (instance_id);
CREATE INDEX refresh_tokens_instance_id_idx ON auth.refresh_tokens USING btree (instance_id);
CREATE INDEX refresh_tokens_instance_id_user_id_idx ON auth.refresh_tokens USING btree (instance_id, user_id);
CREATE INDEX refresh_tokens_token_idx ON auth.refresh_tokens USING btree (token);
CREATE INDEX users_instance_id_email_idx ON auth.users USING btree (instance_id, email);
CREATE INDEX users_instance_id_idx ON auth.users USING btree (instance_id);
CREATE UNIQUE INDEX idx_24472_id_unique ON launchpad.admin USING btree (id);
CREATE UNIQUE INDEX idx_24481_admin_id_company_id_unique ON launchpad.admin_has_companies USING btree (admin_id, company_id);
CREATE INDEX idx_24481_company_id ON launchpad.admin_has_companies USING btree (company_id);
CREATE UNIQUE INDEX idx_24485_admin_index ON launchpad.admin_session USING btree (id);
CREATE UNIQUE INDEX idx_24491_app_version_unique ON launchpad.app_android_version USING btree (app_version, app_id);
CREATE UNIQUE INDEX idx_24498_id ON launchpad.app_constants USING btree (id, batch_id);
CREATE UNIQUE INDEX idx_24507_app_version_unique ON launchpad.app_ios_version USING btree (app_version);
CREATE UNIQUE INDEX idx_24520_access_token_unique ON launchpad.auth_access_token USING btree (access_token);
CREATE UNIQUE INDEX idx_24524_auth_refresh_token ON launchpad.auth_refresh_token USING btree (refresh_token);
CREATE INDEX idx_24529_batch_batchid_index ON launchpad.batch USING btree (batch_id);
CREATE INDEX idx_24529_batch_company_id_company_index ON launchpad.batch USING btree (company_id_company);
CREATE INDEX idx_24542_batch_has_course_batchid_index ON launchpad.batch_has_course USING btree (batch_id);
CREATE INDEX idx_24542_batch_has_course_sequence_index ON launchpad.batch_has_course USING btree (sequence);
CREATE UNIQUE INDEX idx_24542_batch_id ON launchpad.batch_has_course USING btree (batch_id, course_id, coursetype_id);
CREATE INDEX idx_24542_coursetype_id ON launchpad.batch_has_course USING btree (coursetype_id);
CREATE UNIQUE INDEX idx_24549_batch_has_course_type_mapping ON launchpad.batch_has_course_type USING btree (batch_id, coursetype_id);
CREATE UNIQUE INDEX idx_24559_id_feedback_form ON launchpad.batch_has_feedback_form USING btree (id_feedback_form, batch_id);
CREATE INDEX idx_24568_batch_has_skills_batchid_index ON launchpad.batch_has_skills USING btree (batch_id);
CREATE INDEX idx_24568_batch_has_skills_skillid_index ON launchpad.batch_has_skills USING btree (skill_id);
CREATE INDEX idx_24571_batch_has_users_userid_index ON launchpad.batch_has_users USING btree (user_id);
CREATE UNIQUE INDEX idx_24571_batch_id ON launchpad.batch_has_users USING btree (batch_id, user_id);
CREATE UNIQUE INDEX idx_24607_id_company ON launchpad.company_has_language USING btree (company_id, id_language);
CREATE INDEX idx_24612_id_company ON launchpad.company_user_property USING btree (id_company);
CREATE INDEX idx_24626_fk_image_id_idx ON launchpad.const_active_content_image_tags USING btree (image_id);
CREATE UNIQUE INDEX idx_24637_id_country_unique ON launchpad.country USING btree (id);
CREATE INDEX idx_24645_acourse_id_idx ON launchpad.dashboard_activity_userscourse_quizscore USING btree (course_id);
CREATE INDEX idx_24645_acourse_user_index ON launchpad.dashboard_activity_userscourse_quizscore USING btree (user_id, course_id);
CREATE UNIQUE INDEX idx_24645_uniq_acourse_users ON launchpad.dashboard_activity_userscourse_quizscore USING btree (user_id, course_id);
CREATE INDEX idx_24645_user_id_idx ON launchpad.dashboard_activity_userscourse_quizscore USING btree (user_id);
CREATE INDEX idx_24651_akmgr_user_id_idx ON launchpad.dashboard_activity_usersskill_quizscore USING btree (user_id);
CREATE INDEX idx_24651_aksubtopic_id_idx ON launchpad.dashboard_activity_usersskill_quizscore USING btree (skill_id);
CREATE INDEX idx_24651_aksubtopic_user_index ON launchpad.dashboard_activity_usersskill_quizscore USING btree (user_id, skill_id);
CREATE UNIQUE INDEX idx_24651_uniq_subtopic_users ON launchpad.dashboard_activity_usersskill_quizscore USING btree (user_id, skill_id);
CREATE INDEX idx_24657_amgr_user_id_idx ON launchpad.dashboard_activity_userssubtopic_quizscore USING btree (user_id);
CREATE INDEX idx_24657_asubtopic_id_idx ON launchpad.dashboard_activity_userssubtopic_quizscore USING btree (sub_topic_id);
CREATE INDEX idx_24657_asubtopic_user_index ON launchpad.dashboard_activity_userssubtopic_quizscore USING btree (user_id, sub_topic_id);
CREATE UNIQUE INDEX idx_24657_uniq_subtopic_users ON launchpad.dashboard_activity_userssubtopic_quizscore USING btree (user_id, sub_topic_id);
CREATE INDEX idx_24663_course_id_idx ON launchpad.dashboard_learning_userscourse_quizscore USING btree (course_id);
CREATE INDEX idx_24663_course_user_index ON launchpad.dashboard_learning_userscourse_quizscore USING btree (user_id, course_id);
CREATE UNIQUE INDEX idx_24663_uniq_course_users ON launchpad.dashboard_learning_userscourse_quizscore USING btree (user_id, course_id);
CREATE INDEX idx_24663_user_id_idx ON launchpad.dashboard_learning_userscourse_quizscore USING btree (user_id);
CREATE INDEX idx_24669_skill_id_idx ON launchpad.dashboard_learning_usersskill_quizscore USING btree (skill_id);
CREATE INDEX idx_24669_skill_user_index ON launchpad.dashboard_learning_usersskill_quizscore USING btree (user_id, skill_id);
CREATE UNIQUE INDEX idx_24669_uniq_skill_users ON launchpad.dashboard_learning_usersskill_quizscore USING btree (user_id, skill_id);
CREATE INDEX idx_24669_user_skill_id_idx ON launchpad.dashboard_learning_usersskill_quizscore USING btree (user_id);
CREATE INDEX idx_24675_mgr_user_id_idx ON launchpad.dashboard_learning_userssubtopic_quizscore USING btree (user_id);
CREATE INDEX idx_24675_subtopic_id_idx ON launchpad.dashboard_learning_userssubtopic_quizscore USING btree (sub_topic_id);
CREATE INDEX idx_24675_subtopic_user_index ON launchpad.dashboard_learning_userssubtopic_quizscore USING btree (user_id, sub_topic_id);
CREATE UNIQUE INDEX idx_24675_uniq_subtopic_users ON launchpad.dashboard_learning_userssubtopic_quizscore USING btree (user_id, sub_topic_id);
CREATE INDEX idx_24681_pc_courseid_idx ON launchpad.dashboard_user_courses_completion_rate USING btree (course_id);
CREATE INDEX idx_24681_pc_idx_userid ON launchpad.dashboard_user_courses_completion_rate USING btree (user_id);
CREATE UNIQUE INDEX idx_24681_uniq_course_course_id_users_id ON launchpad.dashboard_user_courses_completion_rate USING btree (user_id, course_id);
CREATE INDEX idx_24681_userid_courseid ON launchpad.dashboard_user_courses_completion_rate USING btree (user_id, course_id);
CREATE INDEX idx_24685_avg_pc_course_userid_idx ON launchpad.dashboard_users_course_completion_avg USING btree (user_id);
CREATE INDEX idx_24690_avg_pc_subtopic_userid_idx ON launchpad.dashboard_users_subtopic_completion_avg USING btree (user_id);
CREATE INDEX idx_24696_id_completionpercentage ON launchpad.dashboard_users_subtopic_completion_rate USING btree (completion_percentage);
CREATE INDEX idx_24696_pc_subtopic_idx ON launchpad.dashboard_users_subtopic_completion_rate USING btree (subtopic_id);
CREATE INDEX idx_24696_pc_subtopic_userid_idx ON launchpad.dashboard_users_subtopic_completion_rate USING btree (user_id);
CREATE INDEX idx_24696_user_course_topic_subtopic_ids ON launchpad.dashboard_users_subtopic_completion_rate USING btree (user_id, subtopic_id);
CREATE UNIQUE INDEX idx_24700_content_id ON launchpad.default_mapping_content_to_unit USING btree (content_id, content_type, unit_id);
CREATE INDEX idx_24700_default_mapping_content_to_unit_contentid_index ON launchpad.default_mapping_content_to_unit USING btree (content_id);
CREATE INDEX idx_24700_default_mapping_content_to_unit_unitid_index ON launchpad.default_mapping_content_to_unit USING btree (unit_id);
CREATE INDEX idx_24704_default_mapping_sub_topic_to_topic_subtopicid_index ON launchpad.default_mapping_sub_topic_to_topic USING btree (sub_topic_id);
CREATE INDEX idx_24704_default_mapping_sub_topic_to_topic_topicid_index ON launchpad.default_mapping_sub_topic_to_topic USING btree (topic_id);
CREATE UNIQUE INDEX idx_24704_sub_topic_id ON launchpad.default_mapping_sub_topic_to_topic USING btree (sub_topic_id, topic_id);
CREATE INDEX idx_24710_default_mapping_tags_to_subtopic_subtopicid_index ON launchpad.default_mapping_tags_to_subtopic USING btree (sub_topic_id);
CREATE INDEX idx_24710_default_mapping_tags_to_subtopic_tagid_index ON launchpad.default_mapping_tags_to_subtopic USING btree (tag_id);
CREATE UNIQUE INDEX idx_24710_tag_id_sub_topic_id ON launchpad.default_mapping_tags_to_subtopic USING btree (tag_id, sub_topic_id);
CREATE INDEX idx_24714_default_mapping_tags_to_course_courseid_index ON launchpad.default_mapping_topic_to_course USING btree (course_id);
CREATE INDEX idx_24714_default_mapping_tags_to_course_topicid_index ON launchpad.default_mapping_topic_to_course USING btree (topic_id);
CREATE UNIQUE INDEX idx_24714_topid_id ON launchpad.default_mapping_topic_to_course USING btree (topic_id, course_id);
CREATE INDEX idx_24719_default_mapping_unit_to_skill_skillid_index ON launchpad.default_mapping_unit_to_skill USING btree (skill_id);
CREATE INDEX idx_24719_default_mapping_unit_to_skill_unitid_index ON launchpad.default_mapping_unit_to_skill USING btree (unit_id);
CREATE UNIQUE INDEX idx_24719_unit_id ON launchpad.default_mapping_unit_to_skill USING btree (unit_id, unit_type, skill_id);
CREATE INDEX idx_24723_default_mapping_unit_to_sub_topic_subtopicid_index ON launchpad.default_mapping_unit_to_sub_topic USING btree (sub_topic_id);
CREATE INDEX idx_24723_default_mapping_unit_to_sub_topic_unitid_index ON launchpad.default_mapping_unit_to_sub_topic USING btree (unit_id);
CREATE UNIQUE INDEX idx_24723_unit_id ON launchpad.default_mapping_unit_to_sub_topic USING btree (unit_id, sub_topic_id, unit_type);
CREATE UNIQUE INDEX idx_24733_id_feedback_form ON launchpad.feedback_form_has_questions USING btree (id_feedback_form, question_id);
CREATE UNIQUE INDEX idx_24737_id_feedback_form ON launchpad.feedback_form_language USING btree (id_feedback_form, id_language);
CREATE INDEX idx_24745_id_feedback_form ON launchpad.feedback_questions USING btree (id_feedback_form);
CREATE UNIQUE INDEX idx_24753_question_id ON launchpad.feedback_questions_language USING btree (question_id, id_language);
CREATE INDEX idx_24762_filter_manger_id_idx ON launchpad.filters USING btree (manager_id);
CREATE INDEX idx_24762_filterid_managerid ON launchpad.filters USING btree (filter_id, manager_id);
CREATE UNIQUE INDEX idx_24790_manager_id_unique ON launchpad.manager_session USING btree (manager_id);
CREATE UNIQUE INDEX idx_24790_manager_index ON launchpad.manager_session USING btree (id);
CREATE INDEX idx_24797_manager_submngr_ids_index ON launchpad.manager_to_manager_mapping USING btree (manager_id, sub_manager_id);
CREATE INDEX idx_24797_manager_to_manager_mapping_managerid_index ON launchpad.manager_to_manager_mapping USING btree (manager_id);
CREATE INDEX idx_24797_sub_manager_id_idx ON launchpad.manager_to_manager_mapping USING btree (sub_manager_id);
CREATE UNIQUE INDEX idx_24797_unique_manager_id ON launchpad.manager_to_manager_mapping USING btree (manager_id, sub_manager_id);
CREATE INDEX idx_24802_manager_to_user_mapping_managerid_index ON launchpad.manager_to_user_mapping USING btree (manager_id);
CREATE INDEX idx_24802_manager_user_index ON launchpad.manager_to_user_mapping USING btree (manager_id, user_id);
CREATE UNIQUE INDEX idx_24802_uniq_manager_user ON launchpad.manager_to_user_mapping USING btree (manager_id, user_id);
CREATE INDEX idx_24802_user_id_idx ON launchpad.manager_to_user_mapping USING btree (user_id);
CREATE INDEX idx_24806_level_id_idx ON launchpad.managers USING btree (level_id);
CREATE INDEX idx_24806_managers_email_index ON launchpad.managers USING btree (email);
CREATE INDEX idx_24806_managers_managerid_index ON launchpad.managers USING btree (id);
CREATE INDEX idx_24806_managers_name_index ON launchpad.managers USING btree (name);
CREATE INDEX idx_24806_name_pwd_index ON launchpad.managers USING btree (user_name, password);
CREATE UNIQUE INDEX idx_24806_unique_name_pwd_email ON launchpad.managers USING btree (user_name, password, email);
CREATE UNIQUE INDEX idx_24819_id_challenge ON launchpad.mapping_challenge_to_evaluation USING btree (id_challenge, id_evaluation);
CREATE UNIQUE INDEX idx_24823_content_id ON launchpad.mapping_content_to_unit USING btree (content_id, content_type, unit_id);
CREATE UNIQUE INDEX idx_24831_sub_topic_id ON launchpad.mapping_sub_topic_to_topic USING btree (sub_topic_id, topic_id, batch_id);
CREATE UNIQUE INDEX idx_24838_id ON launchpad.mapping_timer_challenges_to_company USING btree (id);
CREATE UNIQUE INDEX idx_24844_topid_id ON launchpad.mapping_topic_to_course USING btree (topic_id, course_id, batch_id);
CREATE UNIQUE INDEX idx_24849_unit_id ON launchpad.mapping_unit_to_skill USING btree (unit_id, unit_type, skill_id);
CREATE UNIQUE INDEX idx_24853_unit_id ON launchpad.mapping_unit_to_sub_topic USING btree (unit_id, sub_topic_id, unit_type, batch_id);
CREATE UNIQUE INDEX idx_24857_id_user ON launchpad.mapping_user_to_reviewer USING btree (id_user, id_reviewer);
CREATE UNIQUE INDEX idx_24866_id ON launchpad.meta_active_content_language USING btree (id, id_language);
CREATE UNIQUE INDEX idx_24878_id_challenge ON launchpad.meta_challenges USING btree (id_challenge, name);
CREATE UNIQUE INDEX idx_24892_id ON launchpad.meta_content_unit_language USING btree (id, id_language);
CREATE INDEX idx_24896_meta_course_id_index ON launchpad.meta_course USING btree (id);
CREATE INDEX idx_24896_meta_course_name_index ON launchpad.meta_course USING btree (name);
CREATE UNIQUE INDEX idx_24908_id ON launchpad.meta_course_language USING btree (id, id_language);
CREATE UNIQUE INDEX idx_24920_id_course_type ON launchpad.meta_course_type_language USING btree (id_course_type, id_language);
CREATE UNIQUE INDEX idx_24960_id ON launchpad.meta_gifs_language USING btree (id, id_language);
CREATE UNIQUE INDEX idx_25001_id ON launchpad.meta_pdfs_language USING btree (id, id_language);
CREATE UNIQUE INDEX idx_25020_id ON launchpad.meta_posters_language USING btree (id, id_language);
CREATE INDEX idx_25028_id_language ON launchpad.meta_quiz_questions USING btree (id_language);
CREATE UNIQUE INDEX idx_25028_question_id_quiz_id_unique ON launchpad.meta_quiz_questions USING btree (question_id, quiz_id, id_language);
CREATE INDEX idx_25028_quiz_id ON launchpad.meta_quiz_questions USING btree (quiz_id);
CREATE INDEX idx_25038_meta_quiz_unit_quiz_type_index ON launchpad.meta_quiz_unit USING btree (quiz_type);
CREATE UNIQUE INDEX idx_25052_id ON launchpad.meta_quiz_unit_language USING btree (id, id_language);
CREATE INDEX idx_25067_meta_skill_id_index ON launchpad.meta_skill USING btree (id);
CREATE INDEX idx_25067_meta_skill_name_index ON launchpad.meta_skill USING btree (name);
CREATE UNIQUE INDEX idx_25075_id ON launchpad.meta_skill_language USING btree (id, id_language);
CREATE UNIQUE INDEX idx_25094_id ON launchpad.meta_speciality_page_language USING btree (id, id_language);
CREATE INDEX idx_25101_batch_id ON launchpad.meta_spotlights USING btree (batch_id);
CREATE INDEX idx_25101_course_id ON launchpad.meta_spotlights USING btree (course_id);
CREATE INDEX idx_25101_sub_topic_id ON launchpad.meta_spotlights USING btree (sub_topic_id);
CREATE INDEX idx_25101_topic_id ON launchpad.meta_spotlights USING btree (topic_id);
CREATE INDEX idx_25107_meta_sub_topic_id_index ON launchpad.meta_sub_topic USING btree (id);
CREATE INDEX idx_25107_meta_sub_topic_name_index ON launchpad.meta_sub_topic USING btree (name);
CREATE UNIQUE INDEX idx_25122_id ON launchpad.meta_sub_topic_language USING btree (id, id_language);
CREATE UNIQUE INDEX idx_25135_id_survey ON launchpad.meta_survey_language USING btree (id_survey, id_language);
CREATE UNIQUE INDEX idx_25143_question_id ON launchpad.meta_survey_questions USING btree (question_id, id_survey);
CREATE UNIQUE INDEX idx_25151_question_id ON launchpad.meta_survey_questions_language USING btree (question_id, id_survey, id_language);
CREATE UNIQUE INDEX idx_25214_id ON launchpad.meta_timer_challenges_language USING btree (id, id_language);
CREATE INDEX idx_25234_meta_topic_id_index ON launchpad.meta_topic USING btree (id);
CREATE INDEX idx_25234_meta_topic_name_index ON launchpad.meta_topic USING btree (name);
CREATE UNIQUE INDEX idx_25243_id ON launchpad.meta_topic_language USING btree (id, id_language);
CREATE UNIQUE INDEX idx_25258_id ON launchpad.meta_video_language USING btree (id, id_language);
CREATE UNIQUE INDEX idx_25272_id ON launchpad.meta_videos_language USING btree (id, id_language);
CREATE UNIQUE INDEX idx_25285_id ON launchpad.meta_web_link_language USING btree (id, id_language);
CREATE UNIQUE INDEX idx_25306_id ON launchpad.mile_stone_language USING btree (id, id_language);
CREATE UNIQUE INDEX idx_25318_id_type ON launchpad.mile_stone_type_language USING btree (id_type, id_language);
CREATE INDEX idx_25341_overall_completion_item_id_index ON launchpad.overall_completion USING btree (item_id);
CREATE INDEX idx_25341_overall_completion_item_type_index ON launchpad.overall_completion USING btree (item_type);
CREATE INDEX idx_25341_overall_completion_userid_index ON launchpad.overall_completion USING btree (user_id);
CREATE UNIQUE INDEX idx_25341_user_id ON launchpad.overall_completion USING btree (user_id, item_id, item_type);
CREATE UNIQUE INDEX idx_25347_id_user ON launchpad.params_aggregate_score USING btree (id_user, id_challenge, id_evaluation);
CREATE UNIQUE INDEX idx_25362_id_reviewer ON launchpad.reviewer_aggregate_score USING btree (id_reviewer, id_user, id_challenge);
CREATE UNIQUE INDEX idx_25366_admin_index ON launchpad.reviewer_session USING btree (id);
CREATE INDEX idx_25382_fk_role_has_module_module1_idx ON launchpad.role_has_module USING btree (module_id_module);
CREATE INDEX idx_25382_fk_role_has_module_role1_idx ON launchpad.role_has_module USING btree (role_id_role);
CREATE INDEX idx_25398_tile_batchid_idx ON launchpad.tiles_content_mapping USING btree (id_batch);
CREATE INDEX idx_25398_tiles_itemtype_item_id ON launchpad.tiles_content_mapping USING btree (tile_type_id, item_type);
CREATE INDEX idx_25404_unit_id ON launchpad.unit_completion USING btree (unit_id);
CREATE INDEX idx_25404_unit_type ON launchpad.unit_completion USING btree (unit_type);
CREATE UNIQUE INDEX idx_25404_user_id ON launchpad.unit_completion USING btree (user_id, unit_id, unit_type);
CREATE UNIQUE INDEX idx_25409_id_challenge ON launchpad.user_challenges USING btree (id_challenge, id_user);
CREATE UNIQUE INDEX idx_25422_id_user ON launchpad.user_evaluation_score USING btree (id_user, id_challenge, id_evaluation, id_reviewer);
CREATE UNIQUE INDEX idx_25426_user_id ON launchpad.user_has_feedback_questions USING btree (user_id, question_id, id_feedback_form, sub_topic_id, topic_id, course_id);
CREATE UNIQUE INDEX idx_25432_question_id ON launchpad.user_has_quiz_has_question USING btree (user_id, quiz_id, question_id);
CREATE INDEX idx_25432_quiz_id ON launchpad.user_has_quiz_has_question USING btree (quiz_id);
CREATE INDEX idx_25432_user_id ON launchpad.user_has_quiz_has_question USING btree (user_id);
CREATE UNIQUE INDEX idx_25439_user_id ON launchpad.user_has_survey_questions USING btree (user_id, question_id, id_survey);
CREATE INDEX idx_25457_fk_user_type_id_idx ON launchpad.user_push_notifications USING btree (topic);
CREATE INDEX idx_25457_fk_user_type_id_notifications_idx ON launchpad.user_push_notifications USING btree (topic);
CREATE UNIQUE INDEX idx_25479_id_unique ON launchpad.users USING btree (user_id);
CREATE INDEX idx_25479_meta1 ON launchpad.users USING btree (meta1);
CREATE INDEX idx_25479_meta10_index ON launchpad.users USING btree (meta10);
CREATE INDEX idx_25479_meta11_index ON launchpad.users USING btree (meta11);
CREATE INDEX idx_25479_meta12_index ON launchpad.users USING btree (meta12);
CREATE INDEX idx_25479_meta13_index ON launchpad.users USING btree (meta13);
CREATE INDEX idx_25479_meta14_index ON launchpad.users USING btree (meta14);
CREATE INDEX idx_25479_meta15_index ON launchpad.users USING btree (meta15);
CREATE INDEX idx_25479_meta16_index ON launchpad.users USING btree (meta16);
CREATE INDEX idx_25479_meta17_index ON launchpad.users USING btree (meta17);
CREATE INDEX idx_25479_meta18_index ON launchpad.users USING btree (meta18);
CREATE INDEX idx_25479_meta19_index ON launchpad.users USING btree (meta19);
CREATE INDEX idx_25479_meta2 ON launchpad.users USING btree (meta2);
CREATE INDEX idx_25479_meta20_index ON launchpad.users USING btree (meta20);
CREATE INDEX idx_25479_meta3 ON launchpad.users USING btree (meta3);
CREATE INDEX idx_25479_meta4 ON launchpad.users USING btree (meta4);
CREATE INDEX idx_25479_meta5 ON launchpad.users USING btree (meta5);
CREATE INDEX idx_25479_meta6 ON launchpad.users USING btree (meta6);
CREATE INDEX idx_25479_meta7 ON launchpad.users USING btree (meta7);
CREATE INDEX idx_25479_meta8 ON launchpad.users USING btree (meta8);
CREATE INDEX idx_25479_meta9 ON launchpad.users USING btree (meta9);
CREATE INDEX idx_25479_users_userid_index ON launchpad.users USING btree (user_id);
CREATE UNIQUE INDEX idx_25503_contraint_course_id_user_id ON launchpad.users_certifications USING btree (user_id, course_id);
CREATE INDEX idx_25503_uc_couseid_idx ON launchpad.users_certifications USING btree (course_id);
CREATE INDEX idx_25503_uc_userid_courseidx ON launchpad.users_certifications USING btree (user_id, course_id);
CREATE INDEX idx_25503_uc_userid_idx ON launchpad.users_certifications USING btree (user_id);
CREATE UNIQUE INDEX idx_25507_user_id ON launchpad.users_contribution USING btree (user_id, skill_id);
CREATE INDEX idx_25511_fk_user_id_idx ON launchpad.users_details USING btree (user_id);
CREATE UNIQUE INDEX idx_25518_unique_ids_course_unique ON launchpad.users_lms_data USING btree (unique_id, course_id);
CREATE UNIQUE INDEX idx_25530_user_id ON launchpad.users_mile_stone USING btree (user_id, mile_stone_id);
CREATE UNIQUE INDEX idx_25544_user_id ON launchpad.users_progress USING btree (user_id, item_id, item_type);
CREATE UNIQUE INDEX idx_25549_id_users_rules_unique ON launchpad.users_rules USING btree (id);
CREATE UNIQUE INDEX idx_25576_uniqueid_programid_unique ON launchpad.users_tms_data USING btree (unique_id, program_id);
CREATE UNIQUE INDEX idx_25582_id_batch ON launchpad.vc_batch_has_category USING btree (id_batch, id_category);
CREATE INDEX idx_25582_vctobatch_idcategory ON launchpad.vc_batch_has_category USING btree (id_category);
CREATE UNIQUE INDEX idx_25587_id_batch ON launchpad.vc_batch_has_reviewer USING btree (id_batch, id_reviewer, id_category);
CREATE INDEX idx_25587_vcbatchtorev_id_reviewer ON launchpad.vc_batch_has_reviewer USING btree (id_reviewer);
CREATE INDEX idx_25587_vcbatchtorev_idcategory ON launchpad.vc_batch_has_reviewer USING btree (id_category);
CREATE INDEX idx_25600_vctocategory_idreviewer ON launchpad.vc_category_has_reviewer USING btree (id_reviewer);
CREATE INDEX idx_25600_vctoreviewer_idcategory ON launchpad.vc_category_has_reviewer USING btree (id_category);
CREATE UNIQUE INDEX idx_25615_id_company ON launchpad.vc_company_has_reviewers USING btree (id_company, id_reviewer);
CREATE INDEX idx_25615_vctocompany_idreviewer ON launchpad.vc_company_has_reviewers USING btree (id_reviewer);
CREATE INDEX idx_25619_category_vc_idx ON launchpad.vc_dashboard_categories_completion_rate USING btree (category_id);
CREATE INDEX idx_25619_user_cat_idx ON launchpad.vc_dashboard_categories_completion_rate USING btree (user_id, category_id);
CREATE INDEX idx_25619_vc_user_idx ON launchpad.vc_dashboard_categories_completion_rate USING btree (user_id);
CREATE INDEX idx_25624_challenge_vc_idx ON launchpad.vc_dashboard_challenges_completion_rate USING btree (challenge_id);
CREATE INDEX idx_25624_user_challenge_idx ON launchpad.vc_dashboard_challenges_completion_rate USING btree (user_id, challenge_id);
CREATE INDEX idx_25624_vc_user_idx ON launchpad.vc_dashboard_challenges_completion_rate USING btree (user_id);
CREATE INDEX idx_25629_evaluation_vc_userid_idx ON launchpad.vc_dashboard_evaluation_param_completion_rate USING btree (user_id);
CREATE INDEX idx_25629_evalvc_evaluation_id_idx ON launchpad.vc_dashboard_evaluation_param_completion_rate USING btree (id_evaluation);
CREATE INDEX idx_25629_evalvc_user_evaluation_id ON launchpad.vc_dashboard_evaluation_param_completion_rate USING btree (user_id, id_evaluation);
CREATE UNIQUE INDEX idx_25641_id_users_rules_unique ON launchpad.vc_groups USING btree (id);
CREATE INDEX idx_25649_id_category ON launchpad.vc_mapping_challenge_to_category USING btree (id_category, id_challenge);
CREATE INDEX idx_25649_vctocategory_idchallenge ON launchpad.vc_mapping_challenge_to_category USING btree (id_challenge);
CREATE UNIQUE INDEX idx_25653_id_challenge ON launchpad.vc_mapping_challenge_to_evaluation USING btree (id_challenge, id_evaluation);
CREATE INDEX idx_25653_vctochallenge_idevaluation ON launchpad.vc_mapping_challenge_to_evaluation USING btree (id_evaluation);
CREATE INDEX idx_25657_vc_mapping_user_to_reviewers_userid_index ON launchpad.vc_mapping_user_to_reviewers USING btree (user_id);
CREATE UNIQUE INDEX idx_25662_id_user ON launchpad.vc_params_aggregate_score USING btree (id_user, id_challenge, id_evaluation);
CREATE INDEX idx_25662_vctoparamagg_idchallenge ON launchpad.vc_params_aggregate_score USING btree (id_challenge);
CREATE INDEX idx_25662_vctoparamagg_idevaluation ON launchpad.vc_params_aggregate_score USING btree (id_evaluation);
CREATE UNIQUE INDEX idx_25673_id_reviewer ON launchpad.vc_reviewer_aggregate_score USING btree (id_reviewer, id_user, id_challenge);
CREATE INDEX idx_25673_vcreviewagg_idchallenge ON launchpad.vc_reviewer_aggregate_score USING btree (id_challenge);
CREATE INDEX idx_25673_vcreviewagg_iduser ON launchpad.vc_reviewer_aggregate_score USING btree (id_user);
CREATE UNIQUE INDEX idx_25688_id_challenge ON launchpad.vc_user_challenges USING btree (id_challenge, id_user);
CREATE INDEX idx_25688_vcuserchallenge_iduser ON launchpad.vc_user_challenges USING btree (id_user);
CREATE UNIQUE INDEX idx_25696_id_user ON launchpad.vc_user_evaluation_score USING btree (id_user, id_challenge, id_evaluation, id_reviewer);
CREATE UNIQUE INDEX idx_17080_id_unique ON smartsell.admin USING btree (id);
CREATE UNIQUE INDEX idx_17090_admin_index ON smartsell.admin_session USING btree (id);
CREATE UNIQUE INDEX idx_17096_app_version_unique ON smartsell.app_android USING btree (app_version);
CREATE UNIQUE INDEX idx_17112_app_constants_idcompany ON smartsell.app_constants USING btree (company_id);
CREATE UNIQUE INDEX idx_17121_app_version_unique ON smartsell.app_ios USING btree (app_version);
CREATE UNIQUE INDEX idx_17140_access_token_unique ON smartsell.auth_access_token USING btree (access_token);
CREATE UNIQUE INDEX idx_17144_auth_refresh_token ON smartsell.auth_refresh_token USING btree (refresh_token);
CREATE UNIQUE INDEX idx_17156_admin_id_company_id_unique ON smartsell.company_admins USING btree (admin_id, company_id);
CREATE INDEX idx_17156_company_id ON smartsell.company_admins USING btree (company_id);
CREATE INDEX idx_17160_company_id ON smartsell.company_branding USING btree (company_id);
CREATE INDEX idx_17170_company_id ON smartsell.company_countries USING btree (company_id);
CREATE UNIQUE INDEX idx_17170_country_id_company_id_unique ON smartsell.company_countries USING btree (country_id, company_id);
CREATE INDEX idx_17175_cmp_usrs_rules_cmp_id ON smartsell.company_groups USING btree (company_id);
CREATE UNIQUE INDEX idx_17175_id_users_group_unique ON smartsell.company_groups USING btree (id);
CREATE INDEX idx_17185_company_user_group_configs_user_group_id_foreign ON smartsell.company_user_group_configs USING btree (user_group_id);
CREATE INDEX idx_17190_company_id ON smartsell.company_user_property USING btree (company_id);
CREATE UNIQUE INDEX idx_17200_id_country_unique ON smartsell.country USING btree (id);
CREATE INDEX idx_17208_company_id ON smartsell.country_has_companies USING btree (company_id);
CREATE UNIQUE INDEX idx_17208_country_id_company_id_unique ON smartsell.country_has_companies USING btree (country_id, company_id);
CREATE INDEX idx_17212_id ON smartsell.daily_sync_time USING btree (id);
CREATE INDEX idx_17216_dmsuhdc_user_id_contraints ON smartsell.default_mapping_specific_user_directory_content USING btree (company_id);
CREATE INDEX idx_17216_group_usertype_id_specifictable ON smartsell.default_mapping_specific_user_directory_content USING btree (user_type_id);
CREATE INDEX idx_17226_contraint_ls_user_id ON smartsell.group_livestreams USING btree (livestream_id);
CREATE INDEX idx_17230_contraint_presentatingroup_id ON smartsell.group_presentations USING btree (presentation_id);
CREATE INDEX idx_17234_contraint_productgroup_id ON smartsell.group_products USING btree (product_id);
CREATE INDEX idx_17238_group_quick_links_quick_link_id_foreign ON smartsell.group_quick_links USING btree (quick_link_id);
CREATE INDEX idx_17243_batch_has_users_userid_index ON smartsell.group_users USING btree (user_id);
CREATE INDEX idx_17247_page_id ON smartsell.lookup_mapping_page_to_section USING btree (page_id);
CREATE UNIQUE INDEX idx_17247_section_id ON smartsell.lookup_mapping_page_to_section USING btree (section_id, page_id);
CREATE INDEX idx_17254_lmps_product_id ON smartsell.lookup_mapping_product_section USING btree (product_id);
CREATE INDEX idx_17254_lmps_section_id ON smartsell.lookup_mapping_product_section USING btree (section_id);
CREATE UNIQUE INDEX idx_17254_section_product_id ON smartsell.lookup_mapping_product_section USING btree (section_id, product_id);
CREATE UNIQUE INDEX idx_17259_presentation_id ON smartsell.lookup_mapping_section_to_presentation USING btree (presentation_id, section_id);
CREATE INDEX idx_17265_cmp_pagemaster_cmp_id ON smartsell.lookup_page_master USING btree (company_id);
CREATE INDEX idx_17304_cmp_presentationmaster_cmp_id ON smartsell.lookup_presentation_master USING btree (company_id);
CREATE INDEX idx_17315_cmp_product_category_id ON smartsell.lookup_product USING btree (category_id);
CREATE INDEX idx_17315_cmp_product_cmp_id ON smartsell.lookup_product USING btree (company_id);
CREATE INDEX idx_17321_ctrst_lmpsb_section_id ON smartsell.lookup_product_benefit USING btree (section_id);
CREATE INDEX idx_17321_lpbcid_category_id ON smartsell.lookup_product_benefit USING btree (benefit_category_id);
CREATE INDEX idx_17327_lsblm_sectiontype_id ON smartsell.lookup_product_benefit_category USING btree (section_id);
CREATE INDEX idx_17333_id ON smartsell.lookup_product_bulletlist_collateral USING btree (id);
CREATE INDEX idx_17333_lsblc_sectiontype_id ON smartsell.lookup_product_bulletlist_collateral USING btree (section_id);
CREATE INDEX idx_17347_lsblm_sectiontype_id ON smartsell.lookup_product_bulletlist_multiple USING btree (section_id);
CREATE INDEX idx_17353_cmp_productcat_cmp_id ON smartsell.lookup_product_category USING btree (company_id);
CREATE INDEX idx_17359_lsblfaq_sectiontype_id ON smartsell.lookup_product_faq USING btree (section_id);
CREATE INDEX idx_17365_cmp_lookup_section_cmp_id ON smartsell.lookup_product_section USING btree (company_id);
CREATE INDEX idx_17365_ls_sectiontype_id ON smartsell.lookup_product_section USING btree (sectiontype_id);
CREATE INDEX idx_17373_cmp_quicklinks_cmp_id ON smartsell.lookup_quick_links USING btree (company_id);
CREATE INDEX idx_17395_group_usertype_id_global_specifictable ON smartsell.mapping_specific_user_directory_content USING btree (user_type_id);
CREATE INDEX idx_17395_msuhdc_user_id_contraints ON smartsell.mapping_specific_user_directory_content USING btree (company_id);
CREATE INDEX idx_17401_quiz_id ON smartsell.mapping_timer_challenges_to_user_group USING btree (quiz_id);
CREATE INDEX idx_17401_user_group_id ON smartsell.mapping_timer_challenges_to_user_group USING btree (user_group_id);
CREATE UNIQUE INDEX idx_17401_user_group_quiz ON smartsell.mapping_timer_challenges_to_user_group USING btree (user_group_id, quiz_id);
CREATE UNIQUE INDEX idx_17407_company_id ON smartsell.mapping_timer_challenges_to_user_type USING btree (user_type_id, quiz_id);
CREATE INDEX idx_17407_quiz_id ON smartsell.mapping_timer_challenges_to_user_type USING btree (quiz_id);
CREATE INDEX idx_17407_user_type_id ON smartsell.mapping_timer_challenges_to_user_type USING btree (user_type_id);
CREATE INDEX idx_17413_mudc_company_id ON smartsell.mapping_user_directory_content USING btree (company_id);
CREATE INDEX idx_17419_muhb_company_id_contraints ON smartsell.mapping_user_home_banner USING btree (company_id);
CREATE INDEX idx_17427_muhc_company_id_contraints ON smartsell.mapping_user_home_content USING btree (company_id);
CREATE INDEX idx_17433_muhdc_user_id_contraints ON smartsell.mapping_user_home_directory_content USING btree (company_id);
CREATE UNIQUE INDEX idx_17453_id_unique ON smartsell.mapping_user_types USING btree (id);
CREATE INDEX idx_17457_cmp_cards_cmp_id ON smartsell.meta_cards USING btree (company_id);
CREATE INDEX idx_17509_daily_posters_cmp_id ON smartsell.meta_daily_posters USING btree (company_id);
CREATE INDEX idx_17516_meta_directires_id ON smartsell.meta_directories USING btree (company_id);
CREATE UNIQUE INDEX idx_17527_directory_id ON smartsell.meta_directories_language USING btree (directory_id, language_id);
CREATE UNIQUE INDEX idx_17550_level_unique ON smartsell.meta_fs_achievements USING btree (level);
CREATE UNIQUE INDEX idx_17561_sequence ON smartsell.meta_languages USING btree (sequence);
CREATE INDEX idx_17567_company_id ON smartsell.meta_livestream USING btree (company_id);
CREATE INDEX idx_17589_meta_pdfs_id ON smartsell.meta_pdfs USING btree (company_id);
CREATE INDEX idx_17600_pdftag_id_idx ON smartsell.meta_pdfs_tags USING btree (pdf_id, tag_id);
CREATE INDEX idx_17600_poster_tag_id_idx ON smartsell.meta_pdfs_tags USING btree (tag_id);
CREATE INDEX idx_17600_tag_pdf_id_idx ON smartsell.meta_pdfs_tags USING btree (pdf_id);
CREATE INDEX idx_17618_meta_posters_id ON smartsell.meta_posters USING btree (company_id);
CREATE INDEX idx_17641_poster_tag_id_idx ON smartsell.meta_posters_tags USING btree (tag_id);
CREATE INDEX idx_17641_postertag_id_idx ON smartsell.meta_posters_tags USING btree (poster_id, tag_id);
CREATE INDEX idx_17641_tag_poster_id_idx ON smartsell.meta_posters_tags USING btree (poster_id);
CREATE INDEX idx_17692_cmp_recognitions_cmp_id ON smartsell.meta_recognitions USING btree (company_id);
CREATE UNIQUE INDEX idx_17725_id ON smartsell.meta_timer_challenges USING btree (id);
CREATE UNIQUE INDEX idx_17746_id ON smartsell.meta_timer_challenges_language USING btree (id, id_language);
CREATE INDEX idx_17753_id_language ON smartsell.meta_timer_challenges_questions USING btree (id_language);
CREATE UNIQUE INDEX idx_17753_question_id_quiz_id_unique ON smartsell.meta_timer_challenges_questions USING btree (question_id, quiz_id, id_language);
CREATE INDEX idx_17753_quiz_id ON smartsell.meta_timer_challenges_questions USING btree (quiz_id);
CREATE INDEX idx_17770_meta_videos_id ON smartsell.meta_videos USING btree (company_id);
CREATE INDEX idx_17781_poster_tag_id_idx ON smartsell.meta_videos_tags USING btree (tag_id);
CREATE INDEX idx_17781_tag_video_id_idx ON smartsell.meta_videos_tags USING btree (video_id);
CREATE INDEX idx_17781_videotag_id_idx ON smartsell.meta_videos_tags USING btree (video_id, tag_id);
CREATE UNIQUE INDEX idx_17812_page_id ON smartsell.old_mapping_page_to_section USING btree (page_id, section_id, position_in_section);
CREATE UNIQUE INDEX idx_17822_presentation_id ON smartsell.old_mapping_presentation_to_section USING btree (presentation_id, section_id);
CREATE INDEX idx_17836_id ON smartsell.push_sync_time USING btree (id);
CREATE UNIQUE INDEX idx_17850_id_quiz ON smartsell.quiz_question USING btree (id_quiz, id_question);
CREATE INDEX idx_17873_fk_role_has_module_module1_idx ON smartsell.role_has_module USING btree (module_id_module);
CREATE INDEX idx_17873_fk_role_has_module_role1_idx ON smartsell.role_has_module USING btree (role_id_role);
CREATE INDEX idx_17894_fk_user_type_id_idx ON smartsell.user_announcements USING btree (user_type_id);
CREATE UNIQUE INDEX idx_17902_id_unique ON smartsell.user_excel USING btree (user_id);
CREATE INDEX idx_17902_meta1 ON smartsell.user_excel USING btree (meta1);
CREATE INDEX idx_17902_meta10 ON smartsell.user_excel USING btree (meta10);
CREATE INDEX idx_17902_meta11 ON smartsell.user_excel USING btree (meta11);
CREATE INDEX idx_17902_meta12 ON smartsell.user_excel USING btree (meta12);
CREATE INDEX idx_17902_meta13 ON smartsell.user_excel USING btree (meta13);
CREATE INDEX idx_17902_meta14 ON smartsell.user_excel USING btree (meta14);
CREATE INDEX idx_17902_meta15 ON smartsell.user_excel USING btree (meta15);
CREATE INDEX idx_17902_meta16 ON smartsell.user_excel USING btree (meta16);
CREATE INDEX idx_17902_meta17 ON smartsell.user_excel USING btree (meta17);
CREATE INDEX idx_17902_meta18 ON smartsell.user_excel USING btree (meta18);
CREATE INDEX idx_17902_meta19 ON smartsell.user_excel USING btree (meta19);
CREATE INDEX idx_17902_meta2 ON smartsell.user_excel USING btree (meta2);
CREATE INDEX idx_17902_meta20 ON smartsell.user_excel USING btree (meta20);
CREATE INDEX idx_17902_meta3 ON smartsell.user_excel USING btree (meta3);
CREATE INDEX idx_17902_meta4 ON smartsell.user_excel USING btree (meta4);
CREATE INDEX idx_17902_meta5 ON smartsell.user_excel USING btree (meta5);
CREATE INDEX idx_17902_meta6 ON smartsell.user_excel USING btree (meta6);
CREATE INDEX idx_17902_meta7 ON smartsell.user_excel USING btree (meta7);
CREATE INDEX idx_17902_meta8 ON smartsell.user_excel USING btree (meta8);
CREATE INDEX idx_17902_meta9 ON smartsell.user_excel USING btree (meta9);
CREATE INDEX idx_17911_uf_fk_content_type_id_idx ON smartsell.user_favorites USING btree (content_type_id);
CREATE INDEX idx_17925_cmp_userpushnotification_cmp_id ON smartsell.user_push_notifications USING btree (company_id);
CREATE INDEX idx_17925_fk_user_type_id_idx ON smartsell.user_push_notifications USING btree (topic);
CREATE INDEX idx_17925_fk_user_type_id_notifications_idx ON smartsell.user_push_notifications USING btree (topic);
CREATE UNIQUE INDEX idx_17946_id ON smartsell.user_timer_challenge_question_history USING btree (id);
CREATE INDEX idx_17951_cmp_user_id_contraints ON smartsell.users USING btree (company_id);
CREATE UNIQUE INDEX idx_17951_id_unique ON smartsell.users USING btree (user_id);
CREATE INDEX idx_17951_meta1 ON smartsell.users USING btree (meta1);
CREATE INDEX idx_17951_meta10 ON smartsell.users USING btree (meta10);
CREATE INDEX idx_17951_meta11 ON smartsell.users USING btree (meta11);
CREATE INDEX idx_17951_meta12 ON smartsell.users USING btree (meta12);
CREATE INDEX idx_17951_meta13 ON smartsell.users USING btree (meta13);
CREATE INDEX idx_17951_meta14 ON smartsell.users USING btree (meta14);
CREATE INDEX idx_17951_meta15 ON smartsell.users USING btree (meta15);
CREATE INDEX idx_17951_meta16 ON smartsell.users USING btree (meta16);
CREATE INDEX idx_17951_meta17 ON smartsell.users USING btree (meta17);
CREATE INDEX idx_17951_meta18 ON smartsell.users USING btree (meta18);
CREATE INDEX idx_17951_meta19 ON smartsell.users USING btree (meta19);
CREATE INDEX idx_17951_meta2 ON smartsell.users USING btree (meta2);
CREATE INDEX idx_17951_meta20 ON smartsell.users USING btree (meta20);
CREATE INDEX idx_17951_meta3 ON smartsell.users USING btree (meta3);
CREATE INDEX idx_17951_meta4 ON smartsell.users USING btree (meta4);
CREATE INDEX idx_17951_meta5 ON smartsell.users USING btree (meta5);
CREATE INDEX idx_17951_meta6 ON smartsell.users USING btree (meta6);
CREATE INDEX idx_17951_meta7 ON smartsell.users USING btree (meta7);
CREATE INDEX idx_17951_meta8 ON smartsell.users USING btree (meta8);
CREATE INDEX idx_17951_meta9 ON smartsell.users USING btree (meta9);
CREATE INDEX idx_17951_mobile_number ON smartsell.users USING btree (mobile_number);
CREATE UNIQUE INDEX idx_17965_users_details ON smartsell.users_details USING btree (user_id);
CREATE INDEX idx_17970_index2 ON smartsell.users_has_quiz USING btree (id_quiz, user_id, completed_at);
CREATE UNIQUE INDEX idx_17974_agent_code_unique ON smartsell.users_log USING btree (agent_code);
CREATE UNIQUE INDEX idx_17974_id_unique ON smartsell.users_log USING btree (id);
CREATE INDEX idx_17987_quiz_id ON smartsell.users_timer_challenges USING btree (quiz_id);
CREATE UNIQUE INDEX idx_17987_unique_user_quiz_id ON smartsell.users_timer_challenges USING btree (id, user_id, quiz_id);
CREATE INDEX idx_17987_user_id ON smartsell.users_timer_challenges USING btree (user_id);
CREATE INDEX idx_17994_quiz_id ON smartsell.users_timer_challenges_questions USING btree (quiz_id);
CREATE UNIQUE INDEX idx_17994_unique_user_quiz_question_id ON smartsell.users_timer_challenges_questions USING btree (user_id, quiz_id, question_id);
CREATE INDEX idx_17994_user_id ON smartsell.users_timer_challenges_questions USING btree (user_id);
CREATE INDEX idx_18001_cmp_id_vd_lib_contraints ON smartsell.video_library USING btree (company_id);
CREATE UNIQUE INDEX bname ON storage.buckets USING btree (name);
CREATE UNIQUE INDEX bucketid_objname ON storage.objects USING btree (bucket_id, name);
CREATE INDEX name_prefix_search ON storage.objects USING btree (name text_pattern_ops);
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.admin_has_companies FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_admin_has_companies();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.admin_session FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_admin_session();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.app_android_version FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_app_android_version();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.app_constants FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_app_constants();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.app_ios_version FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_app_ios_version();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.assets_data FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_assets_data();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.auth_access_token FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_auth_access_token();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.auth_refresh_token FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_auth_refresh_token();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.batch FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_batch();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.batch_has_course FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_batch_has_course();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.batch_has_course_type FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_batch_has_course_type();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.batch_has_db FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_batch_has_db();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.batch_has_feedback_form FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_batch_has_feedback_form();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.batch_has_onboard_quiz FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_batch_has_onboard_quiz();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.batch_has_users FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_batch_has_users();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.company FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_company();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.company_has_language FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_company_has_language();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.company_user_property FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_company_user_property();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.country FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_country();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.dashboard_activity_userscourse_quizscore FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_dashboard_activity_userscourse_quiz();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.dashboard_activity_usersskill_quizscore FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_dashboard_activity_usersskill_quizs();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.dashboard_activity_userssubtopic_quizscore FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_dashboard_activity_userssubtopic_qu();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.dashboard_learning_userscourse_quizscore FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_dashboard_learning_userscourse_quiz();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.dashboard_learning_usersskill_quizscore FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_dashboard_learning_usersskill_quizs();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.dashboard_learning_userssubtopic_quizscore FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_dashboard_learning_userssubtopic_qu();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.dashboard_user_courses_completion_rate FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_dashboard_user_courses_completion_r();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.dashboard_users_course_completion_avg FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_dashboard_users_course_completion_a();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.dashboard_users_subtopic_completion_avg FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_dashboard_users_subtopic_completion();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.dashboard_users_subtopic_completion_rate FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_dashboard_users_subtopic_completion();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.default_mapping_content_to_unit FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_default_mapping_content_to_unit();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.default_mapping_sub_topic_to_topic FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_default_mapping_sub_topic_to_topic();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.default_mapping_tags_to_subtopic FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_default_mapping_tags_to_subtopic();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.default_mapping_topic_to_course FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_default_mapping_topic_to_course();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.default_mapping_unit_to_skill FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_default_mapping_unit_to_skill();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.default_mapping_unit_to_sub_topic FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_default_mapping_unit_to_sub_topic();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.feedback_form FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_feedback_form();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.feedback_form_has_questions FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_feedback_form_has_questions();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.feedback_form_language FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_feedback_form_language();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.feedback_questions FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_feedback_questions();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.feedback_questions_language FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_feedback_questions_language();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.filters FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_filters();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.in_app_notification FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_in_app_notification();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.logged_mobile_number FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_logged_mobile_number();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.manager_levels FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_manager_levels();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.manager_session FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_manager_session();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.manager_to_manager_mapping FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_manager_to_manager_mapping();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.manager_to_user_mapping FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_manager_to_user_mapping();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.managers FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_managers();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.mapping_challenge_to_evaluation FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_mapping_challenge_to_evaluation();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.mapping_content_to_unit FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_mapping_content_to_unit();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.mapping_question_to_skill FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_mapping_question_to_skill();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.mapping_sub_topic_to_topic FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_mapping_sub_topic_to_topic();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.mapping_timer_challenges_to_company FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_mapping_timer_challenges_to_company();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.mapping_topic_to_course FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_mapping_topic_to_course();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.mapping_unit_to_skill FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_mapping_unit_to_skill();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.mapping_unit_to_sub_topic FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_mapping_unit_to_sub_topic();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.mapping_user_to_reviewer FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_mapping_user_to_reviewer();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_challenges FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_challenges();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_content_unit FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_content_unit();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_content_unit_language FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_content_unit_language();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_course FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_course();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_course_language FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_course_language();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_course_type FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_course_type();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_course_type_language FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_course_type_language();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_evaluation_params FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_evaluation_params();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_gifs_language FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_gifs_language();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_glossary FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_glossary();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_language FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_language();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_live_streaming FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_live_streaming();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_pdfs_language FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_pdfs_language();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_posters_language FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_posters_language();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_quiz_questions FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_quiz_questions();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_quiz_unit FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_quiz_unit();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_quiz_unit_language FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_quiz_unit_language();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_quiz_unit_temp FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_quiz_unit_temp();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_skill FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_skill();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_skill_language FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_skill_language();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_speciality_page FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_speciality_page();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_speciality_page_language FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_speciality_page_language();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_spotlights FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_spotlights();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_sub_topic FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_sub_topic();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_sub_topic_language FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_sub_topic_language();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_survey FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_survey();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_survey_language FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_survey_language();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_survey_questions FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_survey_questions();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_survey_questions_language FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_survey_questions_language();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_tags FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_tags();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_timer_challenges FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_timer_challenges();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_timer_challenges_language FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_timer_challenges_language();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_timer_challenges_questions FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_timer_challenges_questions();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_topic FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_topic();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_topic_language FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_topic_language();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_video_language FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_video_language();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_videos FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_videos();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_videos_language FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_videos_language();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_web_link FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_web_link();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.meta_web_link_language FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_meta_web_link_language();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.mile_stone FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_mile_stone();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.mile_stone_language FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_mile_stone_language();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.mile_stone_type FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_mile_stone_type();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.mile_stone_type_language FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_mile_stone_type_language();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.module FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_module();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.onboard_quiz FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_onboard_quiz();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.overall_completion FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_overall_completion();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.params_aggregate_score FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_params_aggregate_score();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.quiz_type FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_quiz_type();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.reviewer_aggregate_score FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_reviewer_aggregate_score();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.reviewer_session FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_reviewer_session();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.role FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_role();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.role_has_module FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_role_has_module();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.server_health FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_server_health();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.tiles_content_mapping FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_tiles_content_mapping();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.unit_completion FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_unit_completion();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.user_challenges FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_user_challenges();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.user_has_feedback_questions FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_user_has_feedback_questions();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.user_has_quiz_has_question FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_user_has_quiz_has_question();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.user_has_survey_questions FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_user_has_survey_questions();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.user_push_notifications FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_user_push_notifications();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.users FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_users();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.users_certifications FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_users_certifications();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.users_contribution FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_users_contribution();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.users_lms_data FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_users_lms_data();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.users_meta_properties FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_users_meta_properties();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.users_mile_stone FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_users_mile_stone();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.users_notifications FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_users_notifications();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.users_progress FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_users_progress();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.users_rules FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_users_rules();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.users_timer_challenges FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_users_timer_challenges();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.users_timer_challenges_questions FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_users_timer_challenges_questions();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.users_tms_data FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_users_tms_data();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.vc_batch_has_category FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_vc_batch_has_category();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.vc_batch_has_reviewer FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_vc_batch_has_reviewer();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.vc_category FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_vc_category();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.vc_category_has_reviewer FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_vc_category_has_reviewer();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.vc_challenges FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_vc_challenges();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.vc_company_has_reviewers FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_vc_company_has_reviewers();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.vc_dashboard_categories_completion_rate FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_vc_dashboard_categories_completion_();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.vc_dashboard_challenges_completion_rate FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_vc_dashboard_challenges_completion_();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.vc_dashboard_evaluation_param_completion_rate FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_vc_dashboard_evaluation_param_compl();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.vc_evaluation_params FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_vc_evaluation_params();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.vc_groups FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_vc_groups();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.vc_mapping_challenge_to_category FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_vc_mapping_challenge_to_category();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.vc_mapping_challenge_to_evaluation FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_vc_mapping_challenge_to_evaluation();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.vc_mapping_user_to_reviewers FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_vc_mapping_user_to_reviewers();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.vc_params_aggregate_score FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_vc_params_aggregate_score();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.vc_reviewer_aggregate_score FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_vc_reviewer_aggregate_score();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.vc_user_challenges FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_vc_user_challenges();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON launchpad.vc_users_groups FOR EACH ROW EXECUTE FUNCTION launchpad.on_update_current_timestamp_vc_users_groups();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.admin_session FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_admin_session();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.app_constants FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_app_constants();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.company FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_company();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.company_admins FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_company_admins();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.company_branding FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_company_branding();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.company_countries FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_company_countries();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.company_groups FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_company_groups();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.company_user_property FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_company_user_property();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.country FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_country();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.country_has_companies FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_country_has_companies();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.group_cards FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_group_cards();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.group_livestreams FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_group_livestreams();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.group_presentations FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_group_presentations();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.group_products FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_group_products();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.group_users FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_group_users();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.lookup_mapping_page_to_section FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_lookup_mapping_page_to_section();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.lookup_mapping_product_section FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_lookup_mapping_product_section();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.lookup_mapping_section_to_presentation FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_lookup_mapping_section_to_presentat();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.lookup_page_master FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_lookup_page_master();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.lookup_presentation_category FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_lookup_presentation_category();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.lookup_presentation_master FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_lookup_presentation_master();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.lookup_product FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_lookup_product();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.lookup_product_benefit FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_lookup_product_benefit();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.lookup_product_benefit_category FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_lookup_product_benefit_category();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.lookup_product_bulletlist_collateral FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_lookup_product_bulletlist_collatera();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.lookup_product_bulletlist_multiple FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_lookup_product_bulletlist_multiple();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.lookup_product_category FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_lookup_product_category();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.lookup_product_faq FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_lookup_product_faq();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.lookup_product_section FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_lookup_product_section();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.lookup_product_sectiontype FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_lookup_product_sectiontype();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.lookup_section_master FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_lookup_section_master();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.mapping_timer_challenges_to_user_group FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_mapping_timer_challenges_to_user_gr();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.mapping_timer_challenges_to_user_type FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_mapping_timer_challenges_to_user_ty();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.meta_cards FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_meta_cards();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.meta_cards_image_elements FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_meta_cards_image_elements();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.meta_cards_text_elements FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_meta_cards_text_elements();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.meta_configs FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_meta_configs();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.meta_livestream FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_meta_livestream();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.meta_pdfs FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_meta_pdfs();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.meta_posters FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_meta_posters();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.meta_recognitions FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_meta_recognitions();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.meta_timer_challenges FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_meta_timer_challenges();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.meta_timer_challenges_language FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_meta_timer_challenges_language();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.meta_timer_challenges_questions FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_meta_timer_challenges_questions();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.meta_videos FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_meta_videos();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.module FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_module();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.quiz_type FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_quiz_type();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.role_has_module FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_role_has_module();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.users_meta_properties FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_users_meta_properties();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.users_timer_challenges FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_users_timer_challenges();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.users_timer_challenges_questions FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_users_timer_challenges_questions();
CREATE TRIGGER on_update_current_timestamp BEFORE UPDATE ON smartsell.video_library FOR EACH ROW EXECUTE FUNCTION smartsell.on_update_current_timestamp_video_library();
ALTER TABLE ONLY launchpad.dashboard_activity_userscourse_quizscore
    ADD CONSTRAINT a_users_id_dlucqs FOREIGN KEY (user_id) REFERENCES launchpad.users(user_id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.dashboard_activity_userscourse_quizscore
    ADD CONSTRAINT acourse_id_dlucqs FOREIGN KEY (course_id) REFERENCES launchpad.meta_course(id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.dashboard_activity_usersskill_quizscore
    ADD CONSTRAINT aksubtopic_id_dlusq FOREIGN KEY (skill_id) REFERENCES launchpad.meta_skill(id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.dashboard_activity_usersskill_quizscore
    ADD CONSTRAINT akusers_id_dlusq FOREIGN KEY (user_id) REFERENCES launchpad.users(user_id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.dashboard_activity_userssubtopic_quizscore
    ADD CONSTRAINT asubtopic_id_dlusq FOREIGN KEY (sub_topic_id) REFERENCES launchpad.meta_sub_topic(id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.dashboard_activity_userssubtopic_quizscore
    ADD CONSTRAINT ausers_id_dlusq FOREIGN KEY (user_id) REFERENCES launchpad.users(user_id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.dashboard_users_course_completion_avg
    ADD CONSTRAINT avg_pc_course_userid FOREIGN KEY (user_id) REFERENCES launchpad.users(user_id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.dashboard_users_subtopic_completion_avg
    ADD CONSTRAINT avg_pc_subtopic_userid FOREIGN KEY (user_id) REFERENCES launchpad.users(user_id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.vc_dashboard_categories_completion_rate
    ADD CONSTRAINT categoryvc_id FOREIGN KEY (category_id) REFERENCES launchpad.vc_category(id_category) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.vc_dashboard_challenges_completion_rate
    ADD CONSTRAINT challengevc_id FOREIGN KEY (challenge_id) REFERENCES launchpad.vc_challenges(id_challenge) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.dashboard_learning_userscourse_quizscore
    ADD CONSTRAINT course_id_dlucqs FOREIGN KEY (course_id) REFERENCES launchpad.meta_course(id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.vc_dashboard_evaluation_param_completion_rate
    ADD CONSTRAINT eval_vc_userid FOREIGN KEY (user_id) REFERENCES launchpad.users(user_id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.vc_dashboard_evaluation_param_completion_rate
    ADD CONSTRAINT evalvc_evaluation_id FOREIGN KEY (id_evaluation) REFERENCES launchpad.vc_evaluation_params(id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.filters
    ADD CONSTRAINT filter_manger_id FOREIGN KEY (manager_id) REFERENCES launchpad.managers(id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.const_active_content_image_tags
    ADD CONSTRAINT fk_image_id FOREIGN KEY (image_id) REFERENCES launchpad.const_active_content_images(id);
ALTER TABLE ONLY launchpad.role_has_module
    ADD CONSTRAINT fk_role_has_module_module1 FOREIGN KEY (module_id_module) REFERENCES launchpad.module(id_module);
ALTER TABLE ONLY launchpad.role_has_module
    ADD CONSTRAINT fk_role_has_module_role1 FOREIGN KEY (role_id_role) REFERENCES launchpad.role(id_role);
ALTER TABLE ONLY launchpad.users_details
    ADD CONSTRAINT fk_user_id FOREIGN KEY (user_id) REFERENCES launchpad.users(user_id);
ALTER TABLE ONLY launchpad.managers
    ADD CONSTRAINT level_id FOREIGN KEY (level_id) REFERENCES launchpad.manager_levels(id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.manager_to_manager_mapping
    ADD CONSTRAINT manager_id FOREIGN KEY (manager_id) REFERENCES launchpad.managers(id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.manager_session
    ADD CONSTRAINT mangr_id FOREIGN KEY (manager_id) REFERENCES launchpad.managers(id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.manager_to_user_mapping
    ADD CONSTRAINT mngr_id FOREIGN KEY (manager_id) REFERENCES launchpad.managers(id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.dashboard_user_courses_completion_rate
    ADD CONSTRAINT pc_courseid_idx FOREIGN KEY (course_id) REFERENCES launchpad.meta_course(id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.dashboard_user_courses_completion_rate
    ADD CONSTRAINT pc_idx_userid FOREIGN KEY (user_id) REFERENCES launchpad.users(user_id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.dashboard_users_subtopic_completion_rate
    ADD CONSTRAINT pc_subtopic_idx FOREIGN KEY (subtopic_id) REFERENCES launchpad.meta_sub_topic(id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.dashboard_users_subtopic_completion_rate
    ADD CONSTRAINT pc_subtopic_userid FOREIGN KEY (user_id) REFERENCES launchpad.users(user_id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.dashboard_learning_usersskill_quizscore
    ADD CONSTRAINT skill_id_dlusqs FOREIGN KEY (skill_id) REFERENCES launchpad.meta_skill(id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.manager_to_manager_mapping
    ADD CONSTRAINT sub_manager_id FOREIGN KEY (sub_manager_id) REFERENCES launchpad.managers(id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.dashboard_learning_userssubtopic_quizscore
    ADD CONSTRAINT subtopic_id_dlusq FOREIGN KEY (sub_topic_id) REFERENCES launchpad.meta_sub_topic(id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.users_certifications
    ADD CONSTRAINT uc_couseid FOREIGN KEY (course_id) REFERENCES launchpad.meta_course(id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.users_certifications
    ADD CONSTRAINT uc_userid FOREIGN KEY (user_id) REFERENCES launchpad.users(user_id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.manager_to_user_mapping
    ADD CONSTRAINT user_id FOREIGN KEY (user_id) REFERENCES launchpad.users(user_id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.vc_dashboard_challenges_completion_rate
    ADD CONSTRAINT usercvc_id FOREIGN KEY (user_id) REFERENCES launchpad.users(user_id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.dashboard_learning_userscourse_quizscore
    ADD CONSTRAINT users_id_dlucqs FOREIGN KEY (user_id) REFERENCES launchpad.users(user_id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.dashboard_learning_userssubtopic_quizscore
    ADD CONSTRAINT users_id_dlusq FOREIGN KEY (user_id) REFERENCES launchpad.users(user_id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.dashboard_learning_usersskill_quizscore
    ADD CONSTRAINT users_id_dlusqs FOREIGN KEY (user_id) REFERENCES launchpad.users(user_id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.vc_dashboard_categories_completion_rate
    ADD CONSTRAINT uservc_id FOREIGN KEY (user_id) REFERENCES launchpad.users(user_id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.vc_batch_has_reviewer
    ADD CONSTRAINT vcbatchtorev_id_reviewer FOREIGN KEY (id_reviewer) REFERENCES launchpad.vc_reviewers(id_reviewer) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.vc_batch_has_reviewer
    ADD CONSTRAINT vcbatchtorev_idcategory FOREIGN KEY (id_category) REFERENCES launchpad.vc_category(id_category) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.vc_reviewer_aggregate_score
    ADD CONSTRAINT vcreviewagg_idchallenge FOREIGN KEY (id_challenge) REFERENCES launchpad.vc_challenges(id_challenge) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.vc_reviewer_aggregate_score
    ADD CONSTRAINT vcreviewagg_iduser FOREIGN KEY (id_user) REFERENCES launchpad.users(user_id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.vc_batch_has_category
    ADD CONSTRAINT vctobatch_idcategory FOREIGN KEY (id_category) REFERENCES launchpad.vc_category(id_category) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.vc_mapping_challenge_to_category
    ADD CONSTRAINT vctocategory_idcategory FOREIGN KEY (id_category) REFERENCES launchpad.vc_category(id_category) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.vc_mapping_challenge_to_category
    ADD CONSTRAINT vctocategory_idchallenge FOREIGN KEY (id_challenge) REFERENCES launchpad.vc_challenges(id_challenge) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.vc_category_has_reviewer
    ADD CONSTRAINT vctocategory_idreviewer FOREIGN KEY (id_reviewer) REFERENCES launchpad.vc_reviewers(id_reviewer) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.vc_mapping_challenge_to_evaluation
    ADD CONSTRAINT vctochallenge_idevaluation FOREIGN KEY (id_evaluation) REFERENCES launchpad.vc_evaluation_params(id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.vc_company_has_reviewers
    ADD CONSTRAINT vctocompany_idreviewer FOREIGN KEY (id_reviewer) REFERENCES launchpad.vc_reviewers(id_reviewer) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.vc_mapping_challenge_to_evaluation
    ADD CONSTRAINT vctoevaluation_idchallenge FOREIGN KEY (id_challenge) REFERENCES launchpad.vc_challenges(id_challenge) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.vc_params_aggregate_score
    ADD CONSTRAINT vctoparamagg_idchallenge FOREIGN KEY (id_challenge) REFERENCES launchpad.vc_challenges(id_challenge) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.vc_params_aggregate_score
    ADD CONSTRAINT vctoparamagg_idevaluation FOREIGN KEY (id_evaluation) REFERENCES launchpad.vc_evaluation_params(id) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.vc_category_has_reviewer
    ADD CONSTRAINT vctoreviewer_idcategory FOREIGN KEY (id_category) REFERENCES launchpad.vc_category(id_category) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.vc_company_has_reviewers
    ADD CONSTRAINT vctoreviewer_idcompany FOREIGN KEY (id_company) REFERENCES launchpad.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.vc_user_challenges
    ADD CONSTRAINT vcuserchallenge_idchallenge FOREIGN KEY (id_challenge) REFERENCES launchpad.vc_challenges(id_challenge) ON DELETE CASCADE;
ALTER TABLE ONLY launchpad.vc_user_challenges
    ADD CONSTRAINT vcuserchallenge_iduser FOREIGN KEY (id_user) REFERENCES launchpad.users(user_id) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.app_constants
    ADD CONSTRAINT app_constants_cmp_id FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.meta_cards
    ADD CONSTRAINT cmp_cards_cmp_id FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.video_library
    ADD CONSTRAINT cmp_id_vd_lib_contraints FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.lookup_product_section
    ADD CONSTRAINT cmp_lookup_section_cmp_id FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.lookup_product_benefit_category
    ADD CONSTRAINT cmp_lpbc_cmp_id FOREIGN KEY (section_id) REFERENCES smartsell.lookup_product_section(id) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.lookup_product_bulletlist_collateral
    ADD CONSTRAINT cmp_lsblc_cmp_id FOREIGN KEY (section_id) REFERENCES smartsell.lookup_product_section(id) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.lookup_product_faq
    ADD CONSTRAINT cmp_lsblfaw_cmp_id FOREIGN KEY (section_id) REFERENCES smartsell.lookup_product_section(id) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.lookup_product_bulletlist_multiple
    ADD CONSTRAINT cmp_lsblm_cmp_id FOREIGN KEY (section_id) REFERENCES smartsell.lookup_product_section(id) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.meta_livestream
    ADD CONSTRAINT cmp_metalivestreaming_cmp_id FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.lookup_page_master
    ADD CONSTRAINT cmp_pagemaster_cmp_id FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.lookup_presentation_master
    ADD CONSTRAINT cmp_presentationmaster_cmp_id FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.lookup_product
    ADD CONSTRAINT cmp_product_category_id FOREIGN KEY (category_id) REFERENCES smartsell.lookup_product_category(id) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.lookup_product
    ADD CONSTRAINT cmp_product_cmp_id FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.lookup_product_category
    ADD CONSTRAINT cmp_productcat_cmp_id FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.lookup_quick_links
    ADD CONSTRAINT cmp_quicklinks_cmp_id FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.meta_recognitions
    ADD CONSTRAINT cmp_recognitions_cmp_id FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.lookup_product_section
    ADD CONSTRAINT cmp_sections_sectiontype_id FOREIGN KEY (sectiontype_id) REFERENCES smartsell.lookup_product_sectiontype(id) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.company_branding
    ADD CONSTRAINT cmp_user_branding_cmp_id FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.users
    ADD CONSTRAINT cmp_user_id_contraints FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.company_user_property
    ADD CONSTRAINT cmp_user_property_cmp_id FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.user_push_notifications
    ADD CONSTRAINT cmp_userpushnotification_cmp_id FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.company_groups
    ADD CONSTRAINT cmp_usrs_rules_cmp_id FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.company_user_group_configs
    ADD CONSTRAINT company_user_group_configs_company_id_foreign FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.company_user_group_configs
    ADD CONSTRAINT company_user_group_configs_user_group_id_foreign FOREIGN KEY (user_group_id) REFERENCES smartsell.company_groups(id) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.group_presentations
    ADD CONSTRAINT contraint_gp_group_id FOREIGN KEY (group_id) REFERENCES smartsell.company_groups(id) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.group_presentations
    ADD CONSTRAINT contraint_gp_user_id FOREIGN KEY (presentation_id) REFERENCES smartsell.lookup_presentation_master(id) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.group_products
    ADD CONSTRAINT contraint_gpr_group_id FOREIGN KEY (group_id) REFERENCES smartsell.company_groups(id) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.group_users
    ADD CONSTRAINT contraint_gu_group_id FOREIGN KEY (group_id) REFERENCES smartsell.company_groups(id) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.group_users
    ADD CONSTRAINT contraint_gu_user_id FOREIGN KEY (user_id) REFERENCES smartsell.users(user_id) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.group_livestreams
    ADD CONSTRAINT contraint_ls_group_id FOREIGN KEY (group_id) REFERENCES smartsell.company_groups(id) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.group_livestreams
    ADD CONSTRAINT contraint_ls_user_id FOREIGN KEY (livestream_id) REFERENCES smartsell.meta_livestream(id) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.lookup_product_benefit
    ADD CONSTRAINT ctrst_lmpsb_section_id FOREIGN KEY (section_id) REFERENCES smartsell.lookup_product_section(id) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.meta_daily_posters
    ADD CONSTRAINT daily_posters_cmp_id FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.default_mapping_specific_user_directory_content
    ADD CONSTRAINT dmsuhdc_user_id_contraints FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.role_has_module
    ADD CONSTRAINT fk_role_has_module_module1 FOREIGN KEY (module_id_module) REFERENCES smartsell.module(id_module);
ALTER TABLE ONLY smartsell.role_has_module
    ADD CONSTRAINT fk_role_has_module_role1 FOREIGN KEY (role_id_role) REFERENCES smartsell.role(id_role);
ALTER TABLE ONLY smartsell.group_quick_links
    ADD CONSTRAINT group_quick_links_group_id_foreign FOREIGN KEY (group_id) REFERENCES smartsell.company_groups(id) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.group_quick_links
    ADD CONSTRAINT group_quick_links_quick_link_id_foreign FOREIGN KEY (quick_link_id) REFERENCES smartsell.lookup_quick_links(quick_link_id) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.lookup_mapping_product_section
    ADD CONSTRAINT lmps_section_id FOREIGN KEY (section_id) REFERENCES smartsell.lookup_product_section(id) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.lookup_product_benefit
    ADD CONSTRAINT lpbc_category_id FOREIGN KEY (benefit_category_id) REFERENCES smartsell.lookup_product_benefit_category(id) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.meta_directories
    ADD CONSTRAINT meta_directires_id FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.meta_pdfs
    ADD CONSTRAINT meta_pdfs_id FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.meta_posters
    ADD CONSTRAINT meta_posters_id FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.meta_videos
    ADD CONSTRAINT meta_videos_id FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.mapping_specific_user_directory_content
    ADD CONSTRAINT msuhdc_user_id_contraints FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.mapping_user_directory_content
    ADD CONSTRAINT mudc_company_id FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.mapping_user_home_content
    ADD CONSTRAINT muhc_company_id_contraints FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.mapping_user_home_directory_content
    ADD CONSTRAINT muhdc_user_id_contraints FOREIGN KEY (company_id) REFERENCES smartsell.company(id_company) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.meta_pdfs_tags
    ADD CONSTRAINT pdf_id_tag FOREIGN KEY (tag_id) REFERENCES smartsell.meta_tags(id) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.meta_posters_tags
    ADD CONSTRAINT poster_id_tag FOREIGN KEY (tag_id) REFERENCES smartsell.meta_tags(id) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.meta_pdfs_tags
    ADD CONSTRAINT tag_pdf_id FOREIGN KEY (pdf_id) REFERENCES smartsell.meta_pdfs(id) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.meta_posters_tags
    ADD CONSTRAINT tag_poster_id FOREIGN KEY (poster_id) REFERENCES smartsell.meta_posters(id) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.meta_videos_tags
    ADD CONSTRAINT tag_video_id FOREIGN KEY (video_id) REFERENCES smartsell.meta_videos(id) ON DELETE CASCADE;
ALTER TABLE ONLY smartsell.users_timer_challenges
    ADD CONSTRAINT users_timer_challenges_ibfk_2 FOREIGN KEY (quiz_id) REFERENCES smartsell.meta_timer_challenges(id);
ALTER TABLE ONLY smartsell.meta_videos_tags
    ADD CONSTRAINT video_id_tag FOREIGN KEY (tag_id) REFERENCES smartsell.meta_tags(id) ON DELETE CASCADE;
ALTER TABLE ONLY storage.buckets
    ADD CONSTRAINT buckets_owner_fkey FOREIGN KEY (owner) REFERENCES auth.users(id);
ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT "objects_bucketId_fkey" FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);
ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT objects_owner_fkey FOREIGN KEY (owner) REFERENCES auth.users(id);
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
